import Foundation
import PostHog

@MainActor
enum Analytics {
	private static var hasStarted = false

	static func start() {
		guard !hasStarted else {
			return
		}

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
		PostHogSDK.shared.register(["environment": analyticsEnvironment])

		hasStarted = true
		track("app_launched")
		PostHogSDK.shared.flush()
	}

	static func track(_ event: String, properties: [String: Any] = [:]) {
		guard hasStarted else { return }
		PostHogSDK.shared.capture(event, properties: properties)
	}

	private static var analyticsEnvironment: String {
		#if DEBUG
			"debug"
		#else
			"production"
		#endif
	}
}
