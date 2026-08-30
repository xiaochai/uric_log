import Foundation
import CoreData
import CloudKit
import os

final class PersistenceController: ObservableObject {
	@Published private(set) var isLoaded: Bool = false
	@Published var loadErrorMessage: String?
	@Published var iCloudStatus: String = "检查中..."
	@Published var isSyncing: Bool = false
	@Published private(set) var iCloudSyncFailed: Bool = false
	let container: NSPersistentContainer
	private var iCloudEnabled: Bool
	private var lastFailedEventType: NSPersistentCloudKitContainer.EventType?
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tech.xiaochai.uriclog", category: "CloudKit")

	init(iCloudEnabled: Bool) {
		self.iCloudEnabled = iCloudEnabled
		self.container = Persistence.buildContainer(iCloudEnabled: iCloudEnabled)
		
		if iCloudEnabled {
			checkiCloudStatus()
			setupCloudKitMonitoring()
		} else {
			self.iCloudStatus = "已禁用"
		}
		
		DispatchQueue.global(qos: .userInitiated).async {
			self.container.loadPersistentStores { _, error in
				if let error {
					if iCloudEnabled {
						UserDefaults.standard.set(false, forKey: AppSettingsKey.iCloudEnabled)
						DispatchQueue.main.async {
							self.loadErrorMessage = "iCloud 存储初始化失败，已回退到本地存储。\n\n\(error.localizedDescription)"
							self.iCloudStatus = "连接失败"
						}
						let local = Persistence.buildContainer(iCloudEnabled: false)
						local.loadPersistentStores { _, localError in
							if let localError {
								fatalError("Failed to load local persistent stores: \(localError)")
							}
							local.viewContext.automaticallyMergesChangesFromParent = true
							local.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
							DispatchQueue.main.async {
								self.isLoaded = true
							}
						}
						return
					}
					fatalError("Failed to load persistent stores: \(error)")
				}
				self.container.viewContext.automaticallyMergesChangesFromParent = true
				self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
				DispatchQueue.main.async {
					self.isLoaded = true
					if iCloudEnabled {
						self.iCloudStatus = "已连接"
					}
				}
			}
		}
	}
	
	private func checkiCloudStatus() {
		CKContainer.default().accountStatus { status, error in
			DispatchQueue.main.async {
				switch status {
				case .available:
					self.iCloudStatus = "账户可用"
				case .noAccount:
					self.iCloudStatus = "未登录 iCloud"
				case .restricted:
					self.iCloudStatus = "受限"
				case .couldNotDetermine:
					self.iCloudStatus = "无法确定"
                case .temporarilyUnavailable:
                    self.iCloudStatus = "暂不可用"
                @unknown default:
					self.iCloudStatus = "未知状态"
				}
				
				if let error {
					self.iCloudStatus = "错误: \(error.localizedDescription)"
				}
			}
		}
	}
	
	private func setupCloudKitMonitoring() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleCloudKitEvent),
			name: NSPersistentCloudKitContainer.eventChangedNotification,
			object: container
		)
	}
	
	@objc private func handleCloudKitEvent(_ notification: Notification) {
		guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
		
		DispatchQueue.main.async {
			switch event.type {
			case .setup:
				self.iCloudStatus = "初始化中..."
			case .import:
				self.isSyncing = true
				self.iCloudStatus = "导入中..."
			case .export:
				self.isSyncing = true
				self.iCloudStatus = "同步到 iCloud..."
			default:
				break
			}
			
			if event.endDate != nil {
				self.isSyncing = false
				if event.succeeded {
					// A setup/import success must not hide a failure of another event type.
					if self.lastFailedEventType == event.type {
						self.lastFailedEventType = nil
						self.iCloudSyncFailed = false
					}
					if self.lastFailedEventType == nil {
						self.iCloudStatus = "同步完成"
					}
				} else {
					let message = self.userFacingMessage(for: event.error)
					self.lastFailedEventType = event.type
					self.iCloudSyncFailed = true
					self.iCloudStatus = "同步失败：\(message)"
					self.logger.error(
						"CloudKit \(String(describing: event.type), privacy: .public) failed: \(String(describing: event.error), privacy: .public)"
					)
				}
			}
		}
	}

	private func userFacingMessage(for error: Error?) -> String {
		guard let error else { return "暂时无法连接 iCloud，请稍后重试" }

		let nsError = error as NSError
		guard nsError.domain == CKErrorDomain,
			let code = CKError.Code(rawValue: nsError.code) else {
			return "暂时无法连接 iCloud，请稍后重试"
		}

		switch code {
		case .notAuthenticated:
			return "未登录 iCloud，请前往系统设置登录"
		case .networkUnavailable, .networkFailure:
			return "网络不可用，请检查网络后重试"
		case .serviceUnavailable:
			return "iCloud 服务暂不可用，请稍后重试"
		case .requestRateLimited:
			if let retryAfter = nsError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
				return "同步请求较频繁，请在 \(max(1, Int(retryAfter.rounded()))) 秒后重试"
			}
			return "同步请求较频繁，请稍后重试"
		case .quotaExceeded:
			return "iCloud 存储空间不足"
		case .permissionFailure:
			return "没有访问 iCloud 数据的权限"
		case .accountTemporarilyUnavailable:
			return "iCloud 账户暂不可用，请稍后重试"
		case .zoneNotFound, .unknownItem:
			return "iCloud 数据尚未准备好，请稍后重试"
		case .serverRejectedRequest, .invalidArguments:
			return "云端数据配置异常，请联系开发者"
		case .partialFailure:
			return "部分数据未能同步，请稍后重试"
		default:
			return "暂时无法连接 iCloud，请稍后重试"
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
