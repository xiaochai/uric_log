import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
	case simplifiedChinese = "zh-Hans"
	case english = "en"

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .simplifiedChinese:
			return "简体中文"
		case .english:
			return "English"
		}
	}

	var locale: Locale {
		Locale(identifier: rawValue)
	}

	static var selected: AppLanguage {
		let rawValue = UserDefaults.standard.string(forKey: AppSettingsKey.appLanguage)
		return AppLanguage(rawValue: rawValue ?? "") ?? .simplifiedChinese
	}

	@discardableResult
	static func initializeIfNeeded(
		userDefaults: UserDefaults = .standard,
		preferredLanguages: [String] = Locale.preferredLanguages,
		hasExistingStore: Bool = Persistence.hasExistingStore
	) -> AppLanguage {
		if let rawValue = userDefaults.string(forKey: AppSettingsKey.appLanguage),
			let language = AppLanguage(rawValue: rawValue) {
			return language
		}

		let hasExistingSettings = AppSettingsKey.legacyKeys.contains {
			userDefaults.object(forKey: $0) != nil
		}
		let language: AppLanguage
		if hasExistingStore || hasExistingSettings {
			language = .simplifiedChinese
		} else {
			language = languageForNewInstallation(preferredLanguages: preferredLanguages)
		}

		userDefaults.set(language.rawValue, forKey: AppSettingsKey.appLanguage)
		return language
	}

	static func languageForNewInstallation(preferredLanguages: [String]) -> AppLanguage {
		guard let preferredLanguage = preferredLanguages.first?.lowercased() else {
			return .english
		}
		// Traditional Chinese currently uses the Simplified Chinese UI by product choice.
		return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
	}
}

enum L10n {
	static func string(_ key: String) -> String {
		let language = AppLanguage.selected.rawValue
		guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
			let bundle = Bundle(path: path) else {
			return key
		}
		return bundle.localizedString(forKey: key, value: key, table: nil)
	}

	static func format(_ key: String, _ arguments: CVarArg...) -> String {
		String(format: string(key), locale: AppLanguage.selected.locale, arguments: arguments)
	}
}
