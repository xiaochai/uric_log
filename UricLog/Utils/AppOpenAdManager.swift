import GoogleMobileAds
import OSLog
import StoreKit
import UIKit
import UMCommon
import UMUnionSDK
import UserMessagingPlatform

private enum AdProvider: String {
	case admob
	case umeng
}

@MainActor
final class AppOpenAdManager: NSObject, @preconcurrency UMUnionSplashAdDelegate, FullScreenContentDelegate {
	static let shared = AppOpenAdManager()
	private static let logger = Logger(subsystem: "tech.xiaochai.uriclog", category: "AppOpenAd")
	private static let umengSlotID = "100013882"
	private static let admobTestDeviceID = "395FCF70-CBFE-495E-973D-87725F9C6E3A"
	private static var admobAdUnitID: String {
		#if DEBUG
		"ca-app-pub-3940256099942544/5575463023"
		#else
		"ca-app-pub-7908959231552914/2968162810"
		#endif
	}

	private var provider: AdProvider?
	private var umengAd: UMUnionSplashAd?
	private var admobAd: AppOpenAd?
	private var isLoading = false
	private var isPresenting = false
	private var shouldPresentWhenLoaded = false
	private var hasRequestedAdMobConsent = false

	private override init() {
		super.init()
	}

	func startIfAllowed() {
		guard UserDefaults.standard.bool(forKey: AppSettingsKey.privacyConsentGranted) else { return }
		let resolvedProvider = resolveProvider()
		guard provider == nil || provider == resolvedProvider else {
			Self.logger.info("Ad provider change will apply after the next app launch")
			return
		}
		let needsInitialization = provider == nil
		provider = resolvedProvider

		if needsInitialization {
			switch resolvedProvider {
			case .umeng:
				#if DEBUG
				UMUnionAdSdk.enableLogs(true)
				#endif
				UMConfigure.setAnalyticsEnabled(false)
				UMConfigure.initWithAppkey("6aa03577d5481f0b42f00cd6", channel: "App Store")
				UMUnionAdSdk.start()
		case .admob:
				requestAdMobConsentAndStart()
			}
		}

		guard resolvedProvider != .admob, !hasDisplayedToday else { return }
		load()
	}

	@discardableResult
	func presentIfAvailable() -> Bool {
		guard !hasDisplayedToday, !isPresenting else { return false }

		switch provider {
		case .umeng:
			guard let umengAd, let window = activeWindow else { return false }
			isPresenting = true
			umengAd.showFullScreenAd(in: window, skip: nil)
		case .admob:
			guard let admobAd, let viewController = topViewController else { return false }
			do {
				try admobAd.canPresent(from: viewController)
			} catch {
				logFailure("present", provider: .admob, error: error)
				self.admobAd = nil
				return false
			}
			isPresenting = true
			admobAd.present(from: viewController)
		case nil:
			return false
		}

		Analytics.track("app_open_ad_presented", properties: ["provider": provider?.rawValue ?? "unknown"])
		return true
	}

	var isWaitingForLoad: Bool { isLoading }

	func attemptForegroundPresentation() {
		guard UserDefaults.standard.bool(forKey: AppSettingsKey.privacyConsentGranted),
			!hasDisplayedToday,
			!isPresenting else { return }

		startIfAllowed()
		if presentIfAvailable() { return }
		shouldPresentWhenLoaded = true
		load()
	}

	func resetDailyExposure() {
		UserDefaults.standard.removeObject(forKey: AppSettingsKey.lastAppOpenAdExposureDate)
		shouldPresentWhenLoaded = false
		if !isPresenting {
			umengAd = nil
			admobAd = nil
			isLoading = false
		}
	}

	func resetAdMobPrivacyConsentForTesting() {
		ConsentInformation.shared.reset()
		UserDefaults.standard.set(true, forKey: AppSettingsKey.admobConsentTestMode)
		hasRequestedAdMobConsent = false
		resetDailyExposure()
	}

	private func resolveProvider() -> AdProvider {
		let preference = AdProviderPreference(
			rawValue: UserDefaults.standard.string(forKey: AppSettingsKey.adProviderOverride) ?? ""
		) ?? .automatic
		switch preference {
		case .admob: return .admob
		case .umeng: return .umeng
		case .automatic:
			let countryCode = SKPaymentQueue.default().storefront?.countryCode
			Self.logger.info("App Store storefront: \(countryCode ?? "unknown", privacy: .public)")
			return countryCode == "CHN" ? .umeng : .admob
		}
	}

	private func load() {
		guard !isLoading, umengAd == nil, admobAd == nil, let provider else { return }
		isLoading = true

		switch provider {
		case .umeng:
			let ad = UMUnionSplashAd(slotId: Self.umengSlotID)
			ad.delegate = self
			ad.timeout = 2.5
			ad.disableShake = true
			umengAd = ad
			Self.logger.info("Requesting Umeng app-open ad for slot \(Self.umengSlotID, privacy: .public)")
			ad.load()
		case .admob:
			Self.logger.info("Requesting AdMob app-open ad")
			AppOpenAd.load(with: Self.admobAdUnitID, request: Request()) { [weak self] ad, error in
				Task { @MainActor in
					guard let self else { return }
					self.isLoading = false
					if let error {
						self.logFailure("load", provider: .admob, error: error)
						self.shouldPresentWhenLoaded = false
						return
					}
					self.admobAd = ad
					self.admobAd?.fullScreenContentDelegate = self
					Analytics.track("app_open_ad_loaded", properties: ["provider": "admob"])
					self.presentAfterBackgroundRetryIfNeeded()
				}
			}
		}
	}

	private func requestAdMobConsentAndStart() {
		guard !hasRequestedAdMobConsent else { return }
		hasRequestedAdMobConsent = true
		isLoading = true
		shouldPresentWhenLoaded = true

		let parameters = RequestParameters()
		#if DEBUG
		if UserDefaults.standard.bool(forKey: AppSettingsKey.admobConsentTestMode) {
			let debugSettings = DebugSettings()
			debugSettings.geography = .EEA
			debugSettings.testDeviceIdentifiers = [Self.admobTestDeviceID]
			parameters.debugSettings = debugSettings
		}
		#endif

		ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
			Task { @MainActor in
				guard let self else { return }
				if let error {
					self.isLoading = false
					self.logFailure("consent", provider: .admob, error: error)
					return
				}

				ConsentForm.loadAndPresentIfRequired(from: self.topViewController) { [weak self] formError in
					Task { @MainActor in
						guard let self else { return }
						if let formError {
							self.isLoading = false
							self.logFailure("consent_form", provider: .admob, error: formError)
							return
						}
						guard ConsentInformation.shared.canRequestAds else {
							self.isLoading = false
							Self.logger.info("AdMob consent does not allow ad requests")
							return
						}
						MobileAds.shared.start(completionHandler: nil)
						self.isLoading = false
						if !self.hasDisplayedToday { self.load() }
					}
				}
			}
		}
	}

	private func presentAfterBackgroundRetryIfNeeded() {
		guard shouldPresentWhenLoaded else { return }
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(150))
			if !presentIfAvailable() { shouldPresentWhenLoaded = false }
		}
	}

	func uadSplashDidLoad(_ splashAd: UMUnionSplashAd) {
		isLoading = false
		Self.logger.info("Umeng app-open ad loaded")
		Analytics.track("app_open_ad_loaded", properties: ["provider": "umeng"])
		presentAfterBackgroundRetryIfNeeded()
	}

	func uadSplashDidLoad(_ splashAd: UMUnionSplashAd, failWithError error: Error?) {
		isLoading = false
		shouldPresentWhenLoaded = false
		umengAd = nil
		logFailure("load", provider: .umeng, error: error)
	}

	func uadSplashRenderFail(_ splashAd: UMUnionSplashAd, error: Error?) {
		umengAd = nil
		isPresenting = false
		shouldPresentWhenLoaded = false
		logFailure("render", provider: .umeng, error: error)
	}

	func uadSplashExposeSuccess(_ splashAd: UMUnionSplashAd) {
		markDisplayed(provider: .umeng)
	}

	func uadSplashClicked(_ splashAd: UMUnionSplashAd) {
		Analytics.track("app_open_ad_clicked", properties: ["provider": "umeng"])
	}

	func uadSplashClose(_ splashAd: UMUnionSplashAd) {
		umengAd = nil
		isPresenting = false
		Analytics.track("app_open_ad_dismissed", properties: ["provider": "umeng"])
	}

	func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
		markDisplayed(provider: .admob)
	}

	func adDidRecordClick(_ ad: FullScreenPresentingAd) {
		Analytics.track("app_open_ad_clicked", properties: ["provider": "admob"])
	}

	func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
		admobAd = nil
		isPresenting = false
		logFailure("present", provider: .admob, error: error)
	}

	func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
		admobAd = nil
		isPresenting = false
		Analytics.track("app_open_ad_dismissed", properties: ["provider": "admob"])
	}

	private func markDisplayed(provider: AdProvider) {
		UserDefaults.standard.set(Date(), forKey: AppSettingsKey.lastAppOpenAdExposureDate)
		shouldPresentWhenLoaded = false
		Self.logger.info("\(provider.rawValue, privacy: .public) app-open ad displayed")
		Analytics.track("app_open_ad_exposed", properties: ["provider": provider.rawValue])
	}

	private func logFailure(_ stage: String, provider: AdProvider, error: Error?) {
		let nsError = error as NSError?
		let description = nsError?.localizedDescription ?? "Unknown error"
		Self.logger.error(
			"\(provider.rawValue, privacy: .public) app-open ad \(stage, privacy: .public) failed: domain=\(nsError?.domain ?? "unknown", privacy: .public) code=\(nsError?.code ?? -1) description=\(description, privacy: .public)"
		)
		Analytics.track("app_open_ad_\(stage)_failed", properties: [
			"provider": provider.rawValue,
			"error": description,
		])
	}

	private var activeWindow: UIWindow? {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first { $0.isKeyWindow }
	}

	private var topViewController: UIViewController? {
		var current = activeWindow?.rootViewController
		while let presented = current?.presentedViewController { current = presented }
		return current
	}

	private var hasDisplayedToday: Bool {
		guard let lastExposureDate = UserDefaults.standard.object(
			forKey: AppSettingsKey.lastAppOpenAdExposureDate
		) as? Date else { return false }
		return Calendar.current.isDateInToday(lastExposureDate)
	}
}
