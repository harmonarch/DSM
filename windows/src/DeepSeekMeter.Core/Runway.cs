namespace DeepSeekMeter.Core;

// MARK: - 续航读数（油表语义：余额按近期消耗速率预计还能用的天数，满格 = 30 天）
// 与 Android 端 GaugeHero.kt / Swift 端 Models.swift 同口径：
// 近 7 日日均费用（北京时间）、天数向下取整、≥30 显示「30 天以上」

/// <summary>续航健康度（驱动 UI 配色；与 DataStatus 的「数据可信度」语义无关）。</summary>
public enum RunwayLevel
{
    /// <summary>用量数据未就绪：中性展示，不贸然报「耗尽」也不虚标「满格」。</summary>
    Unknown,
    /// <summary>余额已耗尽。</summary>
    Exhausted,
    /// <summary>预计可用不足 1 天。</summary>
    Warning,
    /// <summary>正常（含「近期无消耗」满格）。</summary>
    Healthy,
}

/// <summary>续航读数：Label 为展示文案；Ratio 为余量占比（0...1，满格 = FullDays 天），供余量条/仪表使用。</summary>
public sealed record RunwayReadout(string Label, double Ratio, RunwayLevel Level)
{
    /// <summary>满格对应的续航天数：以一个月为「满箱」。</summary>
    public const double FullDays = 30.0;
}

/// <summary>续航读数推算（纯函数，可测）。</summary>
public static class Runway
{
    /// <summary>由余额 + 本月用量推出续航读数；usage 传 null 表示用量数据未就绪。</summary>
    public static RunwayReadout Evaluate(double balance, MonthUsage? usage, DateTimeOffset? now = null)
    {
        if (usage is null)
        {
            // ratio 归 0 + Unknown：UI 以中性样式渲染余量条（不模拟「满格」避免误读）
            return new RunwayReadout("预计可用 —", 0, RunwayLevel.Unknown);
        }
        if (balance <= 0) return new RunwayReadout("余额已耗尽", 0, RunwayLevel.Exhausted);
        var avg = usage.RecentDailyCost(now);
        if (avg <= 0) return new RunwayReadout("近期无消耗", 1, RunwayLevel.Healthy);
        var days = balance / avg;
        var ratio = Math.Min(days / RunwayReadout.FullDays, 1);
        var label = days >= RunwayReadout.FullDays
            ? "预计可用 30 天以上"
            : days >= 1
                ? $"预计可用 {(int)Math.Floor(days)} 天"
                : "预计可用不足 1 天";
        return new RunwayReadout(label, ratio, days >= 1 ? RunwayLevel.Healthy : RunwayLevel.Warning);
    }
}
