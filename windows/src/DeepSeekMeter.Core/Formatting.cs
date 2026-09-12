using System.Globalization;

namespace DeepSeekMeter.Core;

/// <summary>
/// 纯格式化函数（对齐 macOS 版 Formatting.swift，自测覆盖）。
/// </summary>
public static class Formatting
{
    /// <summary>余额格式化：千元以上保留 1 位小数，其余保留 2 位。</summary>
    public static string Format(double value)
    {
        // 与 Swift String(format:) 行为对齐：固定小数点，不受区域设置影响
        return value >= 1000
            ? value.ToString("0.0", CultureInfo.InvariantCulture)
            : value.ToString("0.00", CultureInfo.InvariantCulture);
    }

    /// <summary>币种代码 -> 常用符号。</summary>
    public static string CurrencySymbol(string code)
    {
        switch (code.ToUpperInvariant())
        {
            case "CNY": return "¥";
            case "USD": return "$";
            case "EUR": return "€";
            case "JPY":
            case "KRW": return "¥";
            default: return code;
        }
    }

    /// <summary>Token 数量展示（紧凑）：亿 / 万 / 原样；0 显示 "0"。</summary>
    public static string TokenString(double n)
    {
        if (n == 0) return "0";
        if (n >= 1e8) return string.Format(CultureInfo.InvariantCulture, "{0:0.00}亿", n / 1e8);
        if (n >= 1e4) return string.Format(CultureInfo.InvariantCulture, "{0:0.0}万", n / 1e4);
        return Format(n);
    }

    /// <summary>Token 完整数值（千分位，用于悬停详情）。不用 long 强转以避免超大数值溢出。</summary>
    public static string TokenFullString(double n)
    {
        return n.ToString("N0", CultureInfo.InvariantCulture);
    }

    /// <summary>请求数展示：千分位。</summary>
    public static string CountString(int n) => n.ToString("N0", CultureInfo.InvariantCulture);

    /// <summary>模型展示名：去掉 deepseek- 前缀。</summary>
    public static string ModelDisplayName(string model) => model.Replace("deepseek-", "");

    /// <summary>
    /// 判断版本号 a 是否严格新于 b（相等或更旧返回 false）。支持可选 v/V 前缀（GitHub tag 形如 v0.0.6）；
    /// 按 "." 分段逐段比较数值，段数不齐按 0 补齐，非数字段按 0 处理（对齐 macOS/iOS isVersion）。
    /// </summary>
    public static bool IsVersion(string? a, string? b)
    {
        static int[] Segments(string? version)
        {
            if (string.IsNullOrWhiteSpace(version)) return [0];
            var v = version.Trim();
            if (v.StartsWith("v") || v.StartsWith("V")) v = v[1..];
            var parts = v.Split('.');
            var result = new int[parts.Length];
            for (var i = 0; i < parts.Length; i++)
            {
                _ = int.TryParse(parts[i], out var n);
                result[i] = n;
            }
            return result;
        }

        var lhs = Segments(a);
        var rhs = Segments(b);
        for (var i = 0; i < Math.Max(lhs.Length, rhs.Length); i++)
        {
            var l = i < lhs.Length ? lhs[i] : 0;
            var r = i < rhs.Length ? rhs[i] : 0;
            if (l != r) return l > r;
        }
        return false;
    }
}
