import SwiftUI
import DeepSeekMeterCore

/// Token 趋势指标（对齐 macOS PopoverView.TrendMetric）
enum TrendMetric: String, CaseIterable, Identifiable {
    case output = "输出"
    case cacheHit = "缓存命中"
    case total = "总量"
    var id: String { rawValue }

    /// 单个趋势日的取值口径（与 macOS / Android 端一致）
    func value(of day: TrendDay) -> Double {
        switch self {
        case .output: return day.responseTokens
        case .cacheHit: return day.cacheHitTokens
        case .total: return day.totalTokens
        }
    }
}

/// Token 每日用量条目（对齐 macOS SparklineView）
struct TokenDailyEntry: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 近 30 天按天 Token 用量柱状图（对齐 macOS SparklineView；移动端加高、加大日期标注）
struct TokenDailyChart: View {
    let entries: [TokenDailyEntry]

    /// 单根柱的最大宽度：天数少时不让一根柱拉满整块宽度（对齐 macOS）
    private static let maxBarWidth: CGFloat = 18
    private static let barSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let maxV = max(entries.map(\.value).max() ?? 0, 1)
            let barWidth = min(Self.maxBarWidth,
                               (geo.size.width - Self.barSpacing * CGFloat(max(entries.count - 1, 0)))
                                   / CGFloat(max(entries.count, 1)))
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.value > 0 ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.08))
                            .frame(width: max(1, barWidth),
                                   height: max(3, CGFloat(entry.value / maxV) * (geo.size.height - 26)))
                        // 日期标签按平台时区（北京时间）取日，跨时区时不至于与柱子的日期错位
                        Text(Self.dayLabel(entries: entries, index: index))
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// 柱下日号：只在跨月处与首柱带上月份（"9/2" 读作 9 月 2 日），其余柱只显示日号——
    /// 30 天窗口必然跨月，纯日号会出现两个 "1" 这类重复，看不出月份边界。
    /// 标签一律单行不换行（对齐 macOS）
    private static func dayLabel(entries: [TokenDailyEntry], index: Int) -> String {
        let calendar = MonthUsage.platformCalendar
        let date = entries[index].date
        let day = calendar.component(.day, from: date)
        guard index > 0 else {
            return "\(calendar.component(.month, from: date))/\(day)"
        }
        let previousMonth = calendar.component(.month, from: entries[index - 1].date)
        let month = calendar.component(.month, from: date)
        return month == previousMonth ? "\(day)" : "\(month)/\(day)"
    }
}
