import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
	case simplifiedChinese = "zh-Hans"
	case english = "en"
	case italian = "it"
	case spanish = "es"
	case german = "de"
	case french = "fr"
	case portuguese = "pt-PT"

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .simplifiedChinese:
			return "简体中文"
		case .german:
			return "Deutsch"
		case .english:
			return "English"
		case .spanish:
			return "Español"
		case .french:
			return "Français"
		case .italian:
			return "Italiano"
		case .portuguese:
			return "Português"
		}
	}

	var locale: Locale {
		Locale(identifier: rawValue)
	}

	static var selected: AppLanguage {
		let rawValue = UserDefaults.standard.string(forKey: AppSettingsKey.appLanguage)
		return AppLanguage(rawValue: rawValue ?? "") ?? .english
	}

	@discardableResult
	static func initializeIfNeeded(
		userDefaults: UserDefaults = .standard,
		preferredLanguages: [String] = Locale.preferredLanguages
	) -> AppLanguage {
		let language: AppLanguage
		if let rawValue = userDefaults.string(forKey: AppSettingsKey.appLanguage),
			let savedLanguage = AppLanguage(rawValue: rawValue) {
			language = savedLanguage
		} else {
			language = languageForNewInstallation(preferredLanguages: preferredLanguages)
			userDefaults.set(language.rawValue, forKey: AppSettingsKey.appLanguage)
		}

		initializeUnitIfNeeded(for: language, userDefaults: userDefaults)
		return language
	}

	static func languageForNewInstallation(preferredLanguages: [String]) -> AppLanguage {
		for preferredLanguage in preferredLanguages {
			let languageCode = preferredLanguage
				.trimmingCharacters(in: .whitespacesAndNewlines)
				.replacingOccurrences(of: "_", with: "-")
				.lowercased()
				.components(separatedBy: "-")
				.first
			switch languageCode {
			case "en": return .english
			case "it": return .italian
			case "es": return .spanish
			case "de": return .german
			case "fr": return .french
			case "pt": return .portuguese
			// Traditional Chinese currently uses the Simplified Chinese UI by product choice.
			case "zh": return .simplifiedChinese
			default: continue
			}
		}
		return .english
	}

	/// Unit used for a new installation when no preference has been saved yet.
	/// Italian clinical reports conventionally use mg/dL. For the other
	/// supported languages the convention depends heavily on country and
	/// health system, so keep the unambiguous SI default (μmol/L) rather than
	/// guessing from language alone. Existing selections are never overwritten.
	static func defaultUnit(for language: AppLanguage) -> UricUnit {
		switch language {
		case .italian:
			return .mgdL
		default:
			return .umolL
		}
	}

	private static func initializeUnitIfNeeded(for language: AppLanguage, userDefaults: UserDefaults) {
		let savedUnit = userDefaults.string(forKey: AppSettingsKey.preferredUnit)
			.flatMap(UricUnit.init(rawValue:))
		let unit = savedUnit ?? defaultUnit(for: language)
		let hasSavedTarget = userDefaults.object(forKey: AppSettingsKey.targetValue) != nil

		if savedUnit == nil || !hasSavedTarget {
			// Without a saved unit, older versions interpreted the target as μmol/L.
			let targetInMicromoles = hasSavedTarget
				? userDefaults.double(forKey: AppSettingsKey.targetValue)
				: 420
			let target = UricUnit.convertWithoutRounding(value: targetInMicromoles, from: .umolL, to: unit)
			userDefaults.set(target, forKey: AppSettingsKey.targetValue)
		}
		if savedUnit == nil {
			userDefaults.set(unit.rawValue, forKey: AppSettingsKey.preferredUnit)
		}
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
