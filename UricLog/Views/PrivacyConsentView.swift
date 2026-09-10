import SwiftUI

struct PrivacyConsentContainer<Content: View>: View {
	@AppStorage(AppSettingsKey.privacyConsentGranted) private var hasConsent = false
	@AppStorage(AppSettingsKey.privacyConsentChoiceMade) private var hasMadeChoice = false
	private let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		Group {
			if hasMadeChoice {
				content
			} else {
				PrivacyConsentView(
					accept: {
						hasConsent = true
						hasMadeChoice = true
						AppOpenAdManager.shared.startIfAllowed()
					},
					decline: {
						hasConsent = false
						hasMadeChoice = true
					}
				)
			}
		}
	}
}

private struct PrivacyConsentView: View {
	let accept: () -> Void
	let decline: () -> Void

	var body: some View {
		ZStack {
			VStack(spacing: 14) {
				Image(systemName: "drop.fill")
					.font(.system(size: 54, weight: .semibold))
					.foregroundStyle(.blue)
				Text("尿酸记录")
					.font(.title.bold())
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(Color(.systemGroupedBackground))
			.blur(radius: 2)

			Color.black.opacity(0.32)
				.ignoresSafeArea()

			VStack(spacing: 22) {
				Text("用户协议和隐私政策说明")
					.font(.title3.weight(.semibold))
					.multilineTextAlignment(.center)

				VStack(spacing: 10) {
					Text("请充分阅读并理解隐私政策。同意后，应用会初始化广告服务并展示广告。匿名功能统计不包含您的健康记录，也不受此授权选择影响。")
						.font(.body)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.leading)

					Text("不会上传您的尿酸记录、备注或其他健康内容。")
						.font(.body.weight(.medium))
						.frame(maxWidth: .infinity, alignment: .leading)

					Link(
						"查看隐私政策",
						destination: URL(string: "https://xiaochai.tech/uric_log/privacy-policy.html")!
					)
					.frame(maxWidth: .infinity, alignment: .leading)
				}

				Button("不同意", action: decline)
					.buttonStyle(.plain)
					.font(.subheadline)
					.foregroundStyle(.secondary)

				Button(action: accept) {
					Text("同意并继续")
						.font(.headline)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
				}
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.capsule)
			}
			.padding(24)
			.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
			.shadow(color: .black.opacity(0.2), radius: 24, y: 8)
			.padding(.horizontal, 28)
		}
		.ignoresSafeArea()
	}
}
