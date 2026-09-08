import SwiftUI
import CoreData
import PostHog

@main
struct UricLogApp: App {
	@AppStorage(AppSettingsKey.appLanguage) private var appLanguageRawValue = AppLanguage.simplifiedChinese.rawValue
	@StateObject private var persistenceController: PersistenceController
	@StateObject private var iCloudSettingsSync = ICloudSettingsSync()

	init() {
		AppLanguage.initializeIfNeeded()

		let postHogConfig = PostHogConfig(
			projectToken: "phc_rufq8pYVnivNQ6Bw7gybU48Bby8JtEmUoG2GqgSjXcci",
			host: "https://us.i.posthog.com"
		)
		postHogConfig.captureScreenViews = false
		postHogConfig.captureElementInteractions = false
		postHogConfig.sessionReplay = false
		postHogConfig.surveys = false
		postHogConfig.errorTrackingConfig.autoCapture = false
		postHogConfig.capturePushNotificationSubscriptions = false
		postHogConfig.capturePushNotificationOpened = false
		PostHogSDK.shared.setup(postHogConfig)
		PostHogSDK.shared.capture("app_launched")
		PostHogSDK.shared.flush()

		let iCloudEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.iCloudEnabled)
		_persistenceController = StateObject(wrappedValue: PersistenceController(iCloudEnabled: iCloudEnabled))
	}

	var body: some Scene {
		WindowGroup {
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
			.environment(\.locale, appLanguage.locale)
		}
	}

	private var appLanguage: AppLanguage {
		AppLanguage(rawValue: appLanguageRawValue) ?? .simplifiedChinese
	}
}
