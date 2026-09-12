// 主页：仪表 Header + 余额仪表盘 Hero + 本月用量卡 + Token 趋势卡（Material 3）。
// 滚动与边距由根布局（DeepSeekMeterApp）提供，这里只负责内容本身。
package com.deepseek.meter.app

import android.graphics.Paint
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.DataStatus
import com.deepseek.meter.core.ModelUsage
import com.deepseek.meter.core.MonthUsage
import com.deepseek.meter.core.UsageDay
import com.deepseek.meter.core.currencySymbol
import com.deepseek.meter.core.format
import com.deepseek.meter.core.tokenString
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max

@Composable
internal fun HomeScreen(state: AppModel.State, controller: AppController, onLogin: () -> Unit) {
    var trendMetric by remember { mutableStateOf(TrendMetric.OUTPUT) }

    Column(Modifier.fillMaxWidth()) {
        MeterHeader(state, controller)
        Spacer(Modifier.height(18.dp))
        when (state.status) {
            DataStatus.NOT_LOGGED_IN -> LoginShowcase(onLogin)
            DataStatus.TOKEN_EXPIRED -> ExpiredShowcase(onLogin)
            else -> {
                GaugeHeroCard(state)
                Spacer(Modifier.height(16.dp))
                UsageCard(state)
                Spacer(Modifier.height(16.dp))
                TrendCard(state, trendMetric, onMetricChange = { trendMetric = it })
                if (state.status == DataStatus.STALE) {
                    Spacer(Modifier.height(12.dp))
                    NoticeBanner(
                        text = "刷新失败，正在显示上次成功的数据",
                        colors = LocalStatusPalette.current.stale
                    )
                }
                (state.lastError ?: state.usageError)?.let { error ->
                    Spacer(Modifier.height(12.dp))
                    NoticeBanner(text = error, colors = LocalStatusPalette.current.bad)
                }
            }
        }
        Spacer(Modifier.height(28.dp))
        Text(
            "数据来自 DeepSeek 官方平台接口，仅使用你自己的登录态，不向任何第三方上报",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.outline,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
        )
    }
}

// MARK: - 顶部 Header：应用名 + 数据状态 + 手动刷新

@Composable
private fun MeterHeader(state: AppModel.State, controller: AppController) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("DeepSeek 仪表", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusDot(state)
                Spacer(Modifier.width(8.dp))
                val updated = state.lastUpdate?.let { " · 更新于 " + timeText(it) } ?: ""
                Text(
                    statusLabel(state) + updated,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        RefreshIconButton(enabled = !state.fetching, onClick = { controller.refresh() })
    }
}

@Composable
private fun RefreshIconButton(enabled: Boolean, onClick: () -> Unit) {
    FilledTonalIconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(42.dp)
    ) {
        if (enabled) {
            Icon(
                imageVector = Icons.Filled.Refresh,
                contentDescription = "刷新",
                modifier = Modifier.size(20.dp)
            )
        } else {
            CircularProgressIndicator(Modifier.size(17.dp), strokeWidth = 2.2.dp)
        }
    }
}

@Composable
private fun statusColor(state: AppModel.State): Color {
    val palette = LocalStatusPalette.current
    return when (state.status) {
        DataStatus.FRESH -> palette.ok.fg
        DataStatus.STALE -> palette.stale.fg
        DataStatus.ERROR -> palette.bad.fg
        DataStatus.TOKEN_EXPIRED -> palette.bad.fg
        DataStatus.LOADING -> palette.neutral.fg
        DataStatus.NOT_LOGGED_IN -> palette.neutral.fg
    }
}

@Composable
private fun StatusDot(state: AppModel.State) {
    Box(
        Modifier
            .size(8.dp)
            .background(statusColor(state), CircleShape)
    )
}

private fun statusLabel(state: AppModel.State): String = when (state.status) {
    DataStatus.FRESH -> "数据正常"
    DataStatus.STALE -> "数据可能过期"
    DataStatus.ERROR -> "获取异常"
    DataStatus.TOKEN_EXPIRED -> "登录已过期"
    DataStatus.LOADING -> "正在同步"
    DataStatus.NOT_LOGGED_IN -> "未登录"
}

// MARK: - 通用卡片与横幅（Material 3：tonal surface + 大圆角，无阴影堆叠）

@Composable
internal fun MeterCard(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(20.dp),
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(contentPadding),
        content = content
    )
}

/** 语义横幅（过期数据 / 错误）：tonal 容器色 + 图标，不用侧边条纹 */
@Composable
private fun NoticeBanner(text: String, colors: StatusColors) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.container)
            .padding(horizontal = 14.dp, vertical = 11.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = colors.fg,
            modifier = Modifier.size(17.dp)
        )
        Spacer(Modifier.width(10.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.fg)
    }
}

// MARK: - 本月用量卡

@Composable
private fun UsageCard(state: AppModel.State) {
    MeterCard {
        val usage = state.monthUsage
        if (usage != null) {
            val symbol = currencySymbol(state.currency)
            Row(verticalAlignment = Alignment.Bottom) {
                Column {
                    Text("本月用量", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(2.dp))
                    Text(
                        usage.year.toString() + "年" + usage.month.toString() + "月",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    "累计 " + symbol + format(usage.totalCost),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Spacer(Modifier.height(14.dp))
            val today = usage.tokens(Date())
            Row {
                StatCell("今日费用", symbol + format(usage.cost(Date())), Modifier.weight(1f))
                StatCell("今日请求", countString(today.requests), Modifier.weight(1f))
                StatCell("今日输出", tokenString(today.response), Modifier.weight(1f))
            }
            Spacer(Modifier.height(10.dp))
            Row {
                StatCell("本月请求", countString(usage.totalRequests), Modifier.weight(1f))
                StatCell("本月输出", tokenString(usage.responseTokens), Modifier.weight(1f))
                StatCell("缓存命中", tokenString(usage.cacheHitTokens), Modifier.weight(1f))
            }
            val activeModels = usage.amountModels.filter { it.requests > 0 }
            if (activeModels.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f))
                Spacer(Modifier.height(6.dp))
                activeModels.forEach { item ->
                    ModelRow(item, usage, symbol)
                }
            }
        } else if (state.usageError != null) {
            Text(
                if (state.tokenExpired) "平台登录已过期，请重新登录" else (state.usageError ?: ""),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else if (state.fetching) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text("正在同步本月用量…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Text("登录后显示余额与用量明细", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun StatCell(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(2.dp))
        Text(
            value,
            style = MeterNumberStyle.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
            maxLines = 1
        )
    }
}

/** 模型分项：名称/请求数/费用 + 费用占比条（品牌蓝），三端数据口径一致 */
@Composable
private fun ModelRow(item: ModelUsage, usage: MonthUsage, symbol: String) {
    val cost = usage.costModels.firstOrNull { it.model == item.model }?.usage?.sumOf { it.amount } ?: 0.0
    val share = if (usage.totalCost > 0) (cost / usage.totalCost).toFloat().coerceIn(0f, 1f) else 0f
    Column(Modifier.padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                modelDisplayName(item.model),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                modifier = Modifier.weight(1f)
            )
            Text(
                countString(item.requests) + " 次 · " + symbol + format(cost),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(6.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
        ) {
            Box(
                Modifier
                    .fillMaxWidth(share)
                    .height(5.dp)
                    .clip(RoundedCornerShape(50))
                    .background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}

// MARK: - Token 趋势卡（M3 分段按钮 + 动画柱状图）

enum class TrendMetric(val label: String) { OUTPUT("输出"), CACHE_HIT("缓存命中"), TOTAL("总量") }

@Composable
private fun TrendCard(state: AppModel.State, metric: TrendMetric, onMetricChange: (TrendMetric) -> Unit) {
    MeterCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("Token 趋势", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(2.dp))
                Text(
                    "按天统计 · 北京时间",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.weight(1f))
        }
        Spacer(Modifier.height(12.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            TrendMetric.entries.forEachIndexed { index, m ->
                SegmentedButton(
                    selected = metric == m,
                    onClick = { onMetricChange(m) },
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = TrendMetric.entries.size)
                ) {
                    Text(m.label, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        val usage = state.monthUsage
        if (usage != null) {
            val entries = dailyEntries(usage, metric)
            if (entries.isEmpty()) {
                Text("本月暂无用量数据", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                TokenDailyChart(entries, Modifier.fillMaxWidth().height(150.dp))
                Spacer(Modifier.height(8.dp))
                Row {
                    val todayKey = dayFormatter.format(Date())
                    val todayVal = usage.amountDays.firstOrNull { it.date == todayKey }
                        ?.let { dailyValue(it, metric) } ?: 0.0
                    Text("今日 " + tokenString(todayVal), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.weight(1f))
                    val peak = entries.maxByOrNull { it.second }
                    if (peak != null) {
                        Text(
                            "峰值 " + tokenString(peak.second) + "（" + dayLabel(peak.first) + "）",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                }
            }
        } else if (state.usageError == null && !state.fetching) {
            Text("登录后查看 Token 用量趋势", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** 按天柱状图（Canvas 自绘）：柱体品牌蓝、今日柱金色高亮；数据/维度切换时弹簧生长 */
@Composable
private fun TokenDailyChart(entries: List<Pair<String, Double>>, modifier: Modifier = Modifier) {
    val maxV = max(entries.maxOfOrNull { it.second } ?: 0.0, 1.0)
    val barColor = MaterialTheme.colorScheme.primary
    val todayBarColor = MeterGold
    val zeroColor = MaterialTheme.colorScheme.surfaceContainerHighest
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val baselineColor = MaterialTheme.colorScheme.outlineVariant

    val growth = remember { Animatable(1f) }
    LaunchedEffect(entries) {
        growth.snapTo(0f)
        growth.animateTo(1f, spring(stiffness = 70f, dampingRatio = Spring.DampingRatioLowBouncy))
    }

    Canvas(modifier = modifier) {
        val labelH = 18.dp.toPx()
        val barArea = size.height - labelH
        val slot = size.width / entries.size.coerceAtLeast(1)
        val barW = (slot * 0.62f).coerceAtLeast(1.5f)
        val paint = Paint().apply {
            textSize = 9.sp.toPx()
            color = labelColor.toArgb()
            textAlign = Paint.Align.CENTER
        }
        // 基线
        drawLine(
            color = baselineColor,
            start = Offset(0f, barArea + 1.dp.toPx()),
            end = Offset(size.width, barArea + 1.dp.toPx()),
            strokeWidth = 1.dp.toPx()
        )
        entries.forEachIndexed { index, entry ->
            val value = entry.second
            // Double→Float：value/maxV 是 Double，先转 Float 再乘动画系数，避免整条链退化为 Double
            val frac = ((value / maxV).toFloat() * growth.value).coerceIn(0f, 1f)
            val h = (frac * barArea * 0.95f)
                .coerceAtLeast(if (value > 0) 3.dp.toPx() else 1.5.dp.toPx())
            val x = index * slot + (slot - barW) / 2
            drawRoundRect(
                color = if (value > 0) {
                    if (index == entries.lastIndex) todayBarColor else barColor
                } else zeroColor,
                topLeft = Offset(x, barArea - h),
                size = Size(barW, h),
                cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx())
            )
            drawContext.canvas.nativeCanvas.drawText(entry.first, x + barW / 2, size.height - 4.dp.toPx(), paint)
        }
    }
}

// MARK: - 未登录 / 登录过期展示卡（鲸鱼娘吉祥物出迎）

@Composable
internal fun LoginShowcase(onLogin: () -> Unit) {
    ShowcaseCard(
        image = { Image(painterResource(R.drawable.whale_girl), contentDescription = null, modifier = Modifier.size(124.dp)) },
        title = "欢迎来到 DeepSeek 仪表",
        body = "登录 DeepSeek 平台后，这里会展示账户余额、本月费用与 Token 用量趋势。",
        buttonText = "登录 DeepSeek 平台",
        onButton = onLogin
    )
}

@Composable
internal fun ExpiredShowcase(onLogin: () -> Unit) {
    val palette = LocalStatusPalette.current
    ShowcaseCard(
        image = {
            Box(
                Modifier
                    .size(96.dp)
                    .background(palette.stale.container, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = palette.stale.fg,
                    modifier = Modifier.size(40.dp)
                )
            }
        },
        title = "登录已过期",
        body = "平台登录态已失效，请重新登录以恢复余额与用量展示。",
        buttonText = "重新登录",
        onButton = onLogin
    )
}

@Composable
private fun ShowcaseCard(
    image: @Composable () -> Unit,
    title: String,
    body: String,
    buttonText: String,
    onButton: () -> Unit
) {
    MeterCard(contentPadding = PaddingValues(horizontal = 24.dp, vertical = 28.dp)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            image()
            Spacer(Modifier.height(14.dp))
            Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(
                body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(18.dp))
            Button(
                onClick = onButton,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Text(buttonText, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

// MARK: - 工具（对齐 iOS HomeView 助手）

private fun countString(n: Int): String = java.text.NumberFormat.getNumberInstance(Locale.US).format(n)

private fun modelDisplayName(model: String): String = model.replace("deepseek-", "")

// 平台计日格式（主线程单实例复用；SimpleDateFormat 非线程安全，调用方均为主线程/单线程执行器）
private val dayFormatter: SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }

private fun timeText(ms: Long): String =
    SimpleDateFormat("HH:mm", Locale.US).format(Date(ms))

private fun dayLabel(dateKey: String): String {
    // dailyEntries 的 key 是「日」数字（如 "16"，供图表坐标标签），这里按当月渲染；
    // 兼容完整日期 key（"2026-08-16"）——A4 真机曾因用 yyyy-MM-dd 解析 "16" 崩溃（ParseException）
    val dayOnly = dateKey.toIntOrNull()
    if (dayOnly != null) {
        val cal = Calendar.getInstance()
        cal.set(Calendar.DAY_OF_MONTH, dayOnly)
        return (cal.get(Calendar.MONTH) + 1).toString() + "月" + dayOnly.toString() + "日"
    }
    val f = dayFormatter
    val date = f.parse(dateKey) ?: return dateKey
    val cal = Calendar.getInstance().apply { time = date }
    return (cal.get(Calendar.MONTH) + 1).toString() + "月" + cal.get(Calendar.DAY_OF_MONTH).toString() + "日"
}

private fun dailyValue(day: UsageDay, metric: TrendMetric): Double {
    val resp = day.data.sumOf { it.value("RESPONSE_TOKEN") }
    val hit = day.data.sumOf { it.value("PROMPT_CACHE_HIT_TOKEN") }
    val miss = day.data.sumOf { it.value("PROMPT_CACHE_MISS_TOKEN") }
    return when (metric) {
        TrendMetric.OUTPUT -> resp
        TrendMetric.CACHE_HIT -> hit
        TrendMetric.TOTAL -> resp + hit + miss
    }
}

private fun dailyEntries(usage: MonthUsage, metric: TrendMetric): List<Pair<String, Double>> {
    val todayKey = dayFormatter.format(Date())
    val f = dayFormatter
    return usage.amountDays
        .filter { it.date <= todayKey }
        .mapNotNull { day ->
            val date = f.parse(day.date) ?: return@mapNotNull null
            val cal = Calendar.getInstance().apply { time = date }
            cal.get(Calendar.DAY_OF_MONTH).toString() to dailyValue(day, metric)
        }
}
