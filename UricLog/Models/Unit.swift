import Foundation

enum UricUnit: String, CaseIterable, Identifiable, Codable {
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

	static func convert(value: Double, from: UricUnit, to: UricUnit) -> Double {
		guard from != to else { return value }
		switch (from, to) {
		case (.umolL, .mgdL):
			return value / 59.48
		case (.mgdL, .umolL):
			return value * 59.48
		default:
			return value
		}
	}
}

enum AppSettingsKey {
	static let preferredUnit = "preferredUnit"
	static let userGender = "userGender"
	static let targetEnabled = "targetEnabled"
	static let targetValue = "targetValue"
	static let iCloudEnabled = "iCloudEnabled"
}

enum UserGender: String, CaseIterable, Identifiable, Codable {
	case male
	case female
	
	var id: String { rawValue }
	
	var displayName: String {
		switch self {
		case .male:
			return "男性"
		case .female:
			return "女性"
		}
	}
	
	/// 正常范围上限（μmol/L）
	var normalRangeUpper: Double {
		switch self {
		case .male:
			return 420
		case .female:
			return 360
		}
	}
	
	/// 正常范围下限（μmol/L）
	var normalRangeLower: Double {
		switch self {
		case .male:
			return 210
		case .female:
			return 150
		}
	}
	
	/// 获取当前单位的正常范围显示文本
	func normalRangeText(unit: UricUnit) -> String {
		let lower = UricUnit.convert(value: normalRangeLower, from: .umolL, to: unit)
		let upper = UricUnit.convert(value: normalRangeUpper, from: .umolL, to: unit)
		let format = unit == .umolL ? "%.0f" : "%.1f"
		return String(format: "\(format)-\(format) \(unit.displayName)", lower, upper)
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
			return "7天"
		case .days30:
			return "30天"
		case .days90:
			return "90天"
		case .all:
			return "全部"
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

