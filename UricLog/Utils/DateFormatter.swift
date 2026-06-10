import Foundation

enum DateFormatters {
    static let chineseDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter
    }()
    
    static let chineseDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter
    }()
    
    static let chineseShortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    
    static let chineseTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension Date {
    var chineseDateTime: String {
        DateFormatters.chineseDateTime.string(from: self)
    }
    
    var chineseDate: String {
        DateFormatters.chineseDate.string(from: self)
    }
    
    var chineseShortDate: String {
        DateFormatters.chineseShortDate.string(from: self)
    }
    
    var chineseTime: String {
        DateFormatters.chineseTime.string(from: self)
    }
}
