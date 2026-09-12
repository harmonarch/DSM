import Foundation

/// 余额格式化：千元以上保留 1 位小数，其余保留 2 位
func format(_ value: Double) -> String {
    if value >= 1000 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.2f", value)
}

/// 币种代码 -> 常用符号
func currencySymbol(_ code: String) -> String {
    switch code.uppercased() {
    case "CNY": return "¥"
    case "USD": return "$"
    case "EUR": return "€"
    case "JPY", "KRW": return "¥"
    case "HKD": return "HK$"
    case "GBP": return "£"
    default: return code
    }
}

// MARK: - 峰谷时段判定（DeepSeek 官方峰谷定价）

/// 峰谷时段（官方定价页：https://api-docs.deepseek.com/zh-cn/quick_start/pricing）
enum TariffPeriod: Equatable {
    /// 高峰时段（单价为低谷时段的两倍）
    case peak
    /// 低谷（空闲）时段，价格为高峰的一半
    case offPeak
}

/// 判定给定时刻属于高峰还是低谷时段。
/// 官方规则：高峰时段为北京时间周一至周五 9:00–12:00、14:00–18:00，
/// 其余（含周六、周日全天）为空闲（低谷）时段，价格为高峰的一半。
/// 时区用平台统计口径的北京时间（与 MonthUsage.platformCalendar 一致），用户跨时区时判定不漂移。
func tariffPeriod(on date: Date, calendar: Calendar = MonthUsage.platformCalendar) -> TariffPeriod {
    let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    guard let weekday = comps.weekday else { return .offPeak }
    // 周日=1、周六=7：周末全天为低谷价
    if weekday == 1 || weekday == 7 { return .offPeak }
    let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    // 高峰窗口左闭右开：9:00–12:00、14:00–18:00
    let peakWindows = [(9 * 60, 12 * 60), (14 * 60, 18 * 60)]
    for (start, end) in peakWindows where minuteOfDay >= start && minuteOfDay < end {
        return .peak
    }
    return .offPeak
}

// MARK: - 版本号比较（应用内更新判断用）

/// 判断版本号 a 是否严格新于 b（相等或更旧返回 false）。
/// 支持可选 "v"/"V" 前缀（GitHub tag 形如 v0.0.6）；按 "." 分段逐段比较数值，
/// 段数不齐按 0 补齐（"1.0" 等价 "1.0.0"），非数字段按 0 处理。
func isVersion(_ a: String, newerThan b: String) -> Bool {
    func segments(_ version: String) -> [Int] {
        var v = version.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }
    let lhs = segments(a)
    let rhs = segments(b)
    for i in 0..<max(lhs.count, rhs.count) {
        let l = i < lhs.count ? lhs[i] : 0
        let r = i < rhs.count ? rhs[i] : 0
        if l != r { return l > r }
    }
    return false
}
