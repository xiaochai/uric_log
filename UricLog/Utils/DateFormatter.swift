import Foundation

enum DateFormatters {
    static func dateTime(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
        return formatter
    }
    
    static func date(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }
    
    static func shortDate(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }
    
    static func time(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        return formatter
    }
}

extension Date {
    var chineseDateTime: String {
        DateFormatters.dateTime(locale: AppLanguage.selected.locale).string(from: self)
    }
    
    var chineseDate: String {
        DateFormatters.date(locale: AppLanguage.selected.locale).string(from: self)
    }
    
    var chineseShortDate: String {
        DateFormatters.shortDate(locale: AppLanguage.selected.locale).string(from: self)
    }
    
    var chineseTime: String {
        DateFormatters.time(locale: AppLanguage.selected.locale).string(from: self)
    }
}
