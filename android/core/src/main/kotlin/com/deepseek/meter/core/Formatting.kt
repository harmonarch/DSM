package com.deepseek.meter.core

import java.util.Locale

/** 余额格式化：千元以上保留 1 位小数，其余保留 2 位（对齐 iOS Formatting.swift） */
fun format(value: Double): String {
    return if (value >= 1000) String.format(Locale.US, "%.1f", value)
    else String.format(Locale.US, "%.2f", value)
}

/** 币种代码 -> 常用符号（对齐 iOS Formatting.swift） */
fun currencySymbol(code: String): String {
    return when (code.uppercase(Locale.US)) {
        "CNY" -> "¥"
        "USD" -> "$"
        "EUR" -> "€"
        "JPY", "KRW" -> "¥"
        "HKD" -> "HK$"
        "GBP" -> "£"
        else -> code
    }
}

/** Token/数量展示：亿/万单位（对齐 iOS HomeView.tokenString） */
fun tokenString(n: Double): String {
    return when {
        n >= 1e8 -> String.format(Locale.US, "%.2f亿", n / 1e8)
        n >= 1e4 -> String.format(Locale.US, "%.1f万", n / 1e4)
        else -> format(n)
    }
}

/**
 * 版本号比较：a 是否严格新于 b（相等或更旧返回 false）。
 * 支持可选 "v"/"V" 前缀（GitHub tag 形如 v0.0.6）；按 "." 分段逐段比较数值，
 * 段数不齐按 0 补齐（"1.0" 等价 "1.0.0"），非数字段按 0 处理（对齐 macOS/iOS isVersion）。
 */
fun isVersion(a: String, newerThan: String): Boolean {
    fun segments(version: String): List<Int> {
        var v = version.trim()
        if (v.startsWith("v") || v.startsWith("V")) v = v.substring(1)
        return v.split(".").map { it.toIntOrNull() ?: 0 }
    }
    val lhs = segments(a)
    val rhs = segments(newerThan)
    for (i in 0 until maxOf(lhs.size, rhs.size)) {
        val l = lhs.getOrElse(i) { 0 }
        val r = rhs.getOrElse(i) { 0 }
        if (l != r) return l > r
    }
    return false
}
