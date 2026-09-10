import SwiftUI

struct DailySplashContainer<Content: View>: View {
	@State private var isShowingSplash = true
	private let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		ZStack {
			content

			if isShowingSplash {
				DailySplashView()
					.zIndex(1)
					.transition(.opacity)
					.task {
						Analytics.track("launch_splash_shown")
						try? await Task.sleep(for: .seconds(1))

						let deadline = ContinuousClock.now + .seconds(2)
						var didPresentAd = AppOpenAdManager.shared.presentIfAvailable()
						while !didPresentAd,
							AppOpenAdManager.shared.isWaitingForLoad,
							ContinuousClock.now < deadline {
							try? await Task.sleep(for: .milliseconds(100))
							didPresentAd = AppOpenAdManager.shared.presentIfAvailable()
						}

						if !didPresentAd {
							Analytics.track("app_open_ad_not_ready", properties: [
								"waiting_for_load": AppOpenAdManager.shared.isWaitingForLoad,
							])
						}
						withAnimation(.easeOut(duration: 0.15)) {
							isShowingSplash = false
						}
					}
			}
		}
	}
}

private struct DailySplashView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var dropSettled = false
	@State private var lineProgress: CGFloat = 0
	@State private var contentVisible = false

	var body: some View {
		ZStack {
			Color(.systemBackground)
				.ignoresSafeArea()

			VStack(spacing: 18) {
				ZStack {
					Circle()
						.stroke(Color.blue.opacity(0.14), lineWidth: 2)
						.frame(width: 82, height: 82)
						.scaleEffect(dropSettled ? 1.55 : 0.7)
						.opacity(dropSettled ? 0 : 1)

					Image(systemName: "drop.fill")
						.font(.system(size: 42, weight: .semibold))
						.foregroundStyle(.blue)
						.offset(y: dropSettled ? -22 : -58)
						.scaleEffect(dropSettled ? 1 : 0.72)

					SplashTrendLine()
						.trim(from: 0, to: lineProgress)
						.stroke(
							LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
							style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
						)
						.frame(width: 150, height: 48)
						.offset(y: 30)
				}
				.frame(width: 180, height: 120)

				VStack(spacing: 7) {
					Text("尿酸记录")
						.font(.system(size: 32, weight: .bold, design: .rounded))
					Text("记录变化，关注趋势")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.opacity(contentVisible ? 1 : 0)
				.offset(y: contentVisible ? 0 : 8)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("尿酸记录")
		.onAppear {
			if reduceMotion {
				dropSettled = true
				lineProgress = 1
				contentVisible = true
				return
			}

			withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
				dropSettled = true
			}
			withAnimation(.easeOut(duration: 0.82).delay(0.18)) {
				lineProgress = 1
			}
			withAnimation(.easeOut(duration: 0.28).delay(0.22)) {
				contentVisible = true
			}
		}
	}
}

private struct SplashTrendLine: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.76))
		path.addCurve(
			to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.58),
			control1: CGPoint(x: rect.width * 0.12, y: rect.height * 0.92),
			control2: CGPoint(x: rect.width * 0.25, y: rect.height * 0.46)
		)
		path.addCurve(
			to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.7),
			control1: CGPoint(x: rect.width * 0.48, y: rect.height * 0.46),
			control2: CGPoint(x: rect.width * 0.57, y: rect.height * 0.84)
		)
		path.addCurve(
			to: CGPoint(x: rect.maxX, y: rect.height * 0.2),
			control1: CGPoint(x: rect.width * 0.8, y: rect.height * 0.72),
			control2: CGPoint(x: rect.width * 0.9, y: rect.height * 0.24)
		)
		return path
	}
}
