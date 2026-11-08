import Foundation
import StoreKit

enum AppStoreRegion {
	static var localeCountryCode: String? {
		Locale.current.region?.identifier
	}

	static var cachedStorefrontCountryCode: String? {
		UserDefaults.standard.string(forKey: AppSettingsKey.cachedStorefrontCountryCode)
	}

	static var launchCountryCode: String? {
		if isMainlandChina(localeCountryCode) {
			return localeCountryCode
		}
		return cachedStorefrontCountryCode ?? localeCountryCode
	}

	static func resolveCountryCode() async -> String? {
		for attempt in 0..<4 {
			if let countryCode = await Storefront.current?.countryCode {
				return countryCode
			}
			if attempt < 3 {
				try? await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
			}
		}
		return nil
	}

	static func refreshStorefrontCountryCode() async {
		guard let countryCode = await resolveCountryCode() else { return }
		UserDefaults.standard.set(countryCode, forKey: AppSettingsKey.cachedStorefrontCountryCode)
	}

	static func isMainlandChina(_ countryCode: String?) -> Bool {
		countryCode == "CHN" || countryCode == "CN"
	}
}

enum UricUnit: String, CaseIterable, Identifiable, Codable, Sendable {
	case umolL
	case mgdL

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .umolL:
			return "μmol/L"
		case .mgdL:
			return "mg/dL"
		}
	}

	/// Preserve full precision; decimal formatting belongs only in the interface.
	static func convert(value: Double, from: UricUnit, to: UricUnit) -> Double {
		guard from != to else { return value }
		switch (from, to) {
		case (.umolL, .mgdL):
			return (value * 168.1103) / 10000
		case (.mgdL, .umolL):
			return (value * 10000) / 168.1103
		default:
			return value
		}
	}

	/// Explicit alias for callers that require an unrounded conversion.
	static func convertWithoutRounding(value: Double, from: UricUnit, to: UricUnit) -> Double {
		convert(value: value, from: from, to: to)
	}

	/// Ignore only floating-point noise introduced by unit conversion.
	static func isAtOrBelow(_ value: Double, upperBound: Double) -> Bool {
		if value <= upperBound { return true }
		guard value.isFinite, upperBound.isFinite else { return false }
		let tolerance = max(value.ulp, upperBound.ulp) * 4
		return value - upperBound <= tolerance
	}
}

enum AppSettingsKey {
	static let appLanguage = "appLanguage"
	static let preferredUnit = "preferredUnit"
	static let userGender = "userGender"
	static let targetEnabled = "targetEnabled"
	static let targetValue = "targetValue"
	static let selectedTimeRange = "selectedTimeRange"
	static let iCloudEnabled = "iCloudEnabled"
	static let cachedStorefrontCountryCode = "cachedStorefrontCountryCode"
	static let measurementReminderEnabled = "measurementReminderEnabled"
	static let measurementReminderWeekdays = "measurementReminderWeekdays"
	static let measurementReminderHour = "measurementReminderHour"
	static let measurementReminderMinute = "measurementReminderMinute"

	static let legacyKeys = [
		preferredUnit,
		userGender,
		targetEnabled,
		targetValue,
		iCloudEnabled,
	]
}

enum UserGender: String, CaseIterable, Identifiable, Codable {
	case male
	case female
	
	var id: String { rawValue }
	
	var displayName: String {
		switch self {
		case .male:
			return L10n.string("SEX_MALE")
		case .female:
			return L10n.string("SEX_FEMALE")
		}
	}
	
	/// Upper limit of the normal range (μmol/L).
	var normalRangeUpper: Double {
		switch self {
		case .male:
			return 428
		case .female:
			return 357
		}
	}
	
	/// Lower limit of the normal range (μmol/L).
	var normalRangeLower: Double {
		switch self {
		case .male:
			return 208
		case .female:
			return 155
		}
	}
	
	/// Return the normal range as display text in the specified unit.
	func normalRangeText(unit: UricUnit) -> String {
		let lower = UricUnit.convertWithoutRounding(value: normalRangeLower, from: .umolL, to: unit)
		let upper = UricUnit.convertWithoutRounding(value: normalRangeUpper, from: .umolL, to: unit)
		let format = FloatingPointFormatStyle<Double>.number
			.locale(AppLanguage.selected.locale)
			.grouping(.never)
			.precision(.fractionLength(2))
		return "\(lower.formatted(format))-\(upper.formatted(format)) \(unit.displayName)"
	}
}

enum TimeRange: String, CaseIterable, Identifiable {
	case days7
	case days30
	case days90
	case all

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .days7:
			return L10n.string("RANGE_7_DAYS")
		case .days30:
			return L10n.string("RANGE_30_DAYS")
		case .days90:
			return L10n.string("RANGE_90_DAYS")
		case .all:
			return L10n.string("RANGE_ALL")
		}
	}

	func startDate(now: Date = Date()) -> Date? {
		let calendar = Calendar.current
		switch self {
		case .days7:
			return calendar.date(byAdding: .day, value: -7, to: now)
		case .days30:
			return calendar.date(byAdding: .day, value: -30, to: now)
		case .days90:
			return calendar.date(byAdding: .day, value: -90, to: now)
		case .all:
			return nil
		}
	}
}
