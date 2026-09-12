// Material 3 主题（Material You 风格）：品牌深蓝 #1D4ADA 作为种子手工构建 tonal 色板，
// 中性色全部向品牌蓝色相倾斜（不用纯灰）；金色取自鲸鱼娘围裙缎带，作为第三强调色
// 只用在「今日柱」「峰值」等少数高亮点缀（60-30-10 里的 10%）。
// 零第三方依赖（红线 11）：仅用 Compose 官方 material3。
package com.deepseek.meter.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// 品牌色（与四端图标 / 余额卡渐变保持一致）
internal val BrandBlue = Color(0xFF1D4ADA)
internal val BrandBlueLight = Color(0xFF2F55EC)
internal val BrandBlueDark = Color(0xFF0D2E8A)

// 鲸鱼娘缎带金：仪表指针铆钉 / 今日柱 / 峰值等高亮点缀
internal val MeterGold = Color(0xFFE8B04B)

// 数据可信度语义色（前景 / 容器底色，明暗两套）
@Immutable
internal data class StatusColors(val fg: Color, val container: Color)

internal data class MeterStatusPalette(
    val ok: StatusColors,
    val stale: StatusColors,
    val bad: StatusColors,
    val neutral: StatusColors
)

private val LightStatus = MeterStatusPalette(
    ok = StatusColors(Color(0xFF196C38), Color(0xFFDCF3E2)),
    stale = StatusColors(Color(0xFF8F5600), Color(0xFFFFEDCB)),
    bad = StatusColors(Color(0xFFB3261E), Color(0xFFFFDAD6)),
    neutral = StatusColors(Color(0xFF4C5670), Color(0xFFE3E7F3))
)

private val DarkStatus = MeterStatusPalette(
    ok = StatusColors(Color(0xFF9BD8A8), Color(0xFF1D3B28)),
    stale = StatusColors(Color(0xFFF2C063), Color(0xFF453312)),
    bad = StatusColors(Color(0xFFFFB4AB), Color(0xFF5C1A16)),
    neutral = StatusColors(Color(0xFFBAC2D6), Color(0xFF2A3145))
)

internal val LocalStatusPalette = staticCompositionLocalOf { LightStatus }

// MARK: - Material 3 色板（明 / 暗）

private val LightColors = lightColorScheme(
    primary = BrandBlue,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFDBE2FF),
    onPrimaryContainer = Color(0xFF001159),
    secondary = Color(0xFF575E71),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFDBE2F9),
    onSecondaryContainer = Color(0xFF151B2C),
    tertiary = Color(0xFF7C5800),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFFFDEA6),
    onTertiaryContainer = Color(0xFF271900),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFF7F8FE),
    onBackground = Color(0xFF1A1B26),
    surface = Color(0xFFF7F8FE),
    onSurface = Color(0xFF1A1B26),
    surfaceVariant = Color(0xFFE1E2F0),
    onSurfaceVariant = Color(0xFF454961),
    outline = Color(0xFF767A91),
    outlineVariant = Color(0xFFC6CADB),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF1F2FC),
    surfaceContainer = Color(0xFFEBEDF8),
    surfaceContainerHigh = Color(0xFFE5E7F4),
    surfaceContainerHighest = Color(0xFFDFE2EF),
    inverseSurface = Color(0xFF2F303C),
    inverseOnSurface = Color(0xFFF1F0FA),
    inversePrimary = Color(0xFFB7C4FF)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFB7C4FF),
    onPrimary = Color(0xFF00239B),
    primaryContainer = Color(0xFF0B37BE),
    onPrimaryContainer = Color(0xFFDBE2FF),
    secondary = Color(0xFFBFC6E1),
    onSecondary = Color(0xFF293041),
    secondaryContainer = Color(0xFF3F4759),
    onSecondaryContainer = Color(0xFFDBE2F9),
    tertiary = Color(0xFFEFC069),
    onTertiary = Color(0xFF432C00),
    tertiaryContainer = Color(0xFF604200),
    onTertiaryContainer = Color(0xFFFFDEA6),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF10121D),
    onBackground = Color(0xFFE3E2EE),
    surface = Color(0xFF10121D),
    onSurface = Color(0xFFE3E2EE),
    surfaceVariant = Color(0xFF454961),
    onSurfaceVariant = Color(0xFFC6CADB),
    outline = Color(0xFF9094AB),
    outlineVariant = Color(0xFF454961),
    surfaceContainerLowest = Color(0xFF0B0D18),
    surfaceContainerLow = Color(0xFF181A26),
    surfaceContainer = Color(0xFF1C1E2B),
    surfaceContainerHigh = Color(0xFF262936),
    surfaceContainerHighest = Color(0xFF313441),
    inverseSurface = Color(0xFFE3E2EE),
    inverseOnSurface = Color(0xFF2F303C),
    inversePrimary = BrandBlue
)

// MARK: - 字阶（系统字体 + 强对比层级；数字统一 tnum 等宽，仪表读数不跳动）

private fun meterTypography() = Typography(
    displaySmall = TextStyle(fontWeight = FontWeight.Black, fontSize = 34.sp, letterSpacing = (-0.8).sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 28.sp, letterSpacing = (-0.4).sp),
    headlineSmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 23.sp, letterSpacing = (-0.3).sp),
    titleLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 20.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp),
    titleSmall = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 14.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp, letterSpacing = 0.1.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp, letterSpacing = 0.1.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 17.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 14.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, letterSpacing = 0.2.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 0.2.sp)
)

/// 仪表读数专用：等宽数字 + 紧字距 + 黑体字重
internal val MeterNumberStyle = TextStyle(
    fontWeight = FontWeight.Black,
    fontFeatureSettings = "tnum",
    letterSpacing = (-0.6).sp
)

/// Material3 主题（浅色/深色跟随系统）+ 语义色注入
@Composable
fun DeepSeekMeterTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    CompositionLocalProvider(
        LocalStatusPalette provides if (dark) DarkStatus else LightStatus
    ) {
        MaterialTheme(
            colorScheme = if (dark) DarkColors else LightColors,
            typography = meterTypography(),
            content = content
        )
    }
}
