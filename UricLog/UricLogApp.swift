import SwiftUI
import CoreData

@main
struct UricLogApp: App {
	@Environment(\.scenePhase) private var scenePhase
	@AppStorage(AppSettingsKey.appLanguage) private var appLanguageRawValue = AppLanguage.simplifiedChinese.rawValue
	@StateObject private var persistenceController: PersistenceController
	@StateObject private var iCloudSettingsSync = ICloudSettingsSync()
	@State private var backgroundEnteredAt: Date?

	init() {
		AppLanguage.initializeIfNeeded()
		Analytics.start()

		let iCloudEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.iCloudEnabled)
		_persistenceController = StateObject(wrappedValue: PersistenceController(iCloudEnabled: iCloudEnabled))
	}

	var body: some Scene {
		WindowGroup {
			PrivacyConsentContainer {
				DailySplashContainer {
				Group {
					if persistenceController.isLoaded {
						RootTabView()
							.environment(\.managedObjectContext, persistenceController.container.viewContext)
							.environmentObject(persistenceController)
					} else {
						ProgressView("正在加载数据...")
							.progressViewStyle(.circular)
					}
				}
				.alert(
					"存储初始化提示",
					isPresented: Binding(
						get: { persistenceController.loadErrorMessage != nil },
						set: { newValue in
							if !newValue { persistenceController.loadErrorMessage = nil }
						}
					)
					) {
						Button("知道了") {
							Analytics.track("storage_error_acknowledged")
						}
				} message: {
					Text(persistenceController.loadErrorMessage ?? "")
					}
				.id(appLanguageRawValue)
				}
			}
			.environment(\.locale, appLanguage.locale)
			.onChange(of: scenePhase) { _, newPhase in
				handleScenePhaseChange(newPhase)
			}
		}
	}

	private func handleScenePhaseChange(_ newPhase: ScenePhase) {
		switch newPhase {
		case .background:
			backgroundEnteredAt = Date()
		case .active:
			guard let backgroundEnteredAt,
				Date().timeIntervalSince(backgroundEnteredAt) >= 10 else {
				return
			}
			self.backgroundEnteredAt = nil
			AppOpenAdManager.shared.attemptForegroundPresentation()
		default:
			break
		}
	}

	private var appLanguage: AppLanguage {
		AppLanguage(rawValue: appLanguageRawValue) ?? .simplifiedChinese
	}
}
