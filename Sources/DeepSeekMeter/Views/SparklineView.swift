import SwiftUI

/// Token 每日用量条目
struct TokenDailyEntry: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 本月按天 Token 用量柱状图
struct TokenDailyChart: View {
    let entries: [TokenDailyEntry]

    /// 单根柱的最大宽度：天数少时（月初、或近 30 天窗口未取满）不让一根柱拉满整块宽度
    private static let maxBarWidth: CGFloat = 14
    private static let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let maxV = max(entries.map(\.value).max() ?? 0, 1)
            let barWidth = min(Self.maxBarWidth,
                               (geo.size.width - Self.barSpacing * CGFloat(max(entries.count - 1, 0)))
                                   / CGFloat(max(entries.count, 1)))
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(entry.value > 0 ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.08))
                            .frame(width: max(1, barWidth),
                                   height: max(2, CGFloat(entry.value / maxV) * (geo.size.height - 12)))
                        // 日期标签按平台时区（北京时间）取日，跨时区时不至于与柱子的日期错位
                        Text(Self.dayLabel(entries: entries, index: index))
                            .font(.system(size: 6))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: 42)
    }

    /// 柱下日号：只在跨月处与首柱带上月份（"9/2" 读作 9 月 2 日），其余柱只显示日号——
    /// 30 天窗口必然跨月，纯日号会出现两个 "1" 这类重复，看不出月份边界。
    /// 标签一律单行不换行：柱子约 6pt 宽，两行会把日号挤到图外
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
