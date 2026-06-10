import Foundation
import CoreData
import CloudKit

final class PersistenceController: ObservableObject {
	@Published private(set) var isLoaded: Bool = false
	@Published var loadErrorMessage: String?
	@Published var iCloudStatus: String = "检查中..."
	@Published var isSyncing: Bool = false
	let container: NSPersistentContainer
	private var iCloudEnabled: Bool

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
					self.iCloudStatus = "同步完成"
				} else {
					self.iCloudStatus = "同步失败"
				}
			}
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
