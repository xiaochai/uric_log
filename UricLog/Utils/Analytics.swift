import Foundation
import PostHog

enum Analytics {
	static func track(_ event: String, properties: [String: Any] = [:]) {
		PostHogSDK.shared.capture(event, properties: properties)
	}
}
