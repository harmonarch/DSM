// 「仪表盘」Hero 卡：应用名叫 DeepSeekMeter，主角就该是一块真正的"表"。
// 240° 刻度表盘：指针弧 = 续航余量——余额按近 7 日日均消耗预计还能用的天数，满弧 = 30 天。
// 油表回答的是"还能开多远"而不是"烧掉了百分之几"；中心叠余额大数字 + "预计可用 N 天"读数，
// 金色铆钉标记指针端点，鲸鱼娘吉祥物从卡片右下角探出身子——品牌记忆点。
package com.deepseek.meter.app

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.MonthUsage
import com.deepseek.meter.core.currencySymbol
import com.deepseek.meter.core.format
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

/// 表盘几何常量（固定尺寸；中心叠字的对齐偏移依赖这些值）
private val GaugeBoxW = 236.dp
private val GaugeBoxH = 180.dp
private const val ARC_START = 150f
private const val ARC_SWEEP = 240f

@Composable
internal fun GaugeHeroCard(state: AppModel.State) {
    val balance = state.lastBalance?.total ?: 0.0
    val symbol = currencySymbol(state.currency)

    Box(
        Modifier
            .fillMaxWidth()
            .graphicsLayer {
                shape = RoundedCornerShape(28.dp)
                clip = true
                shadowElevation = 26.dp.toPx()
                ambientShadowColor = BrandBlueDark.copy(alpha = 0.35f)
                spotShadowColor = BrandBlueDark.copy(alpha = 0.35f)
            }
            .background(Brush.linearGradient(listOf(Color(0xFF2F55EC), BrandBlueDark)))
            .padding(top = 20.dp, start = 20.dp, end = 20.dp, bottom = 18.dp)
    ) {
        Column(Modifier.fillMaxWidth()) {
            // 标题行：账户余额 + 余量健康度 + 币种
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("账户余额", color = Color.White.copy(alpha = 0.88f), style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.width(8.dp))
                BalanceHealthPill(balance)
                Spacer(Modifier.weight(1f))
                Text(
                    state.currency,
                    color = Color.White,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier
                        .background(Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                )
            }
            Spacer(Modifier.height(6.dp))

            // 表盘（固定尺寸居中；中心叠余额大数字）
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                GaugeDial(
                    readout = runwayReadout(balance, state.monthUsage),
                    balance = balance,
                    symbol = symbol
                )
            }
            Spacer(Modifier.height(12.dp))

            // 底部指标胶囊（靠左排布，右侧留给吉祥物；
            // 「本月已用」不在这里展示——下方用量卡已有累计读数，表盘中心专注余额与续航）
            Row(verticalAlignment = Alignment.CenterVertically) {
                HeroChip("赠送", state.lastBalance?.granted, symbol)
                Spacer(Modifier.width(8.dp))
                HeroChip("充值", state.lastBalance?.toppedUp, symbol)
            }
        }

        // 鲸鱼娘吉祥物：站在卡片右下角，脚部被卡片边缘轻轻裁掉，像趴在仪表旁
        Image(
            painter = painterResource(R.drawable.whale_girl),
            contentDescription = null, // 纯装饰，不进无障碍树
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .size(112.dp)
                .offset(x = 2.dp, y = 34.dp)
        )
    }
}

/** 240° 仪表盘：刻度 + 轨道 + 续航弧 + 金色端点铆钉；中心叠「余额 + 预计可用天数」读数 */
@Composable
private fun GaugeDial(readout: RunwayReadout, balance: Double, symbol: String) {
    val animated by animateFloatAsState(
        targetValue = readout.ratio,
        animationSpec = spring(dampingRatio = 0.75f, stiffness = 45f),
        label = "gaugeRatio"
    )
    Box(Modifier.size(GaugeBoxW, GaugeBoxH)) {
        Canvas(Modifier.size(GaugeBoxW, GaugeBoxH)) { drawGauge(animated) }
        // 中心读数：垂直对齐圆心（圆心在盒中心下方约 28dp，见 drawGauge 几何）
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .align(Alignment.Center)
                .offset(y = 24.dp)
        ) {
            Text(
                "可用余额",
                color = Color.White.copy(alpha = 0.72f),
                style = MaterialTheme.typography.labelSmall
            )
            Text(
                symbol + " " + format(balance),
                color = Color.White,
                fontSize = 32.sp,
                style = MeterNumberStyle,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
            Text(
                readout.label,
                color = Color.White.copy(alpha = 0.85f),
                style = MaterialTheme.typography.labelMedium
            )
        }
    }
}

/** 续航读数：label 为表盘中心副标签；ratio 为指针弧占比（满弧 = 30 天） */
private data class RunwayReadout(val label: String, val ratio: Float)

/** 满弧对应的续航天数：以一个月为"满箱" */
private const val RUNWAY_FULL_DAYS = 30.0

/** 由余额 + 本月用量推出续航读数（纯函数；usage 为 null 表示用量数据未就绪） */
private fun runwayReadout(balance: Double, usage: MonthUsage?): RunwayReadout {
    val avg = recentDailyCost(usage)
        ?: return RunwayReadout("预计可用 —", 1f) // 数据未就绪，不贸然报"耗尽"
    if (balance <= 0.0) return RunwayReadout("余额已耗尽", 0f)
    if (avg <= 0.0) return RunwayReadout("近期无消耗", 1f)
    val days = balance / avg
    val ratio = (days / RUNWAY_FULL_DAYS).toFloat().coerceIn(0f, 1f)
    val label = when {
        days >= RUNWAY_FULL_DAYS -> "预计可用 30 天以上"
        days >= 1.0 -> "预计可用 " + floor(days).toInt().toString() + " 天"
        else -> "预计可用不足 1 天"
    }
    return RunwayReadout(label, ratio)
}

/**
 * 近 N 日日均费用（平台统计口径为北京时间）：N = min(7, 本月已过天数)——
 * 本月之前的日桶不在 monthUsage 的查询窗口内，窗口只向月初方向收缩。
 * 无用量日按 0 计（消耗速率不应跳过空闲日）；usage 为 null 时返回 null。
 */
private fun recentDailyCost(usage: MonthUsage?): Double? {
    usage ?: return null
    val now = Calendar.getInstance(MonthUsage.PLATFORM_TIME_ZONE).apply {
        set(Calendar.HOUR_OF_DAY, 12) // 正午取 key，避开时区边界
    }
    val window = minOf(7, now.get(Calendar.DAY_OF_MONTH))
    val total = (0 until window).sumOf { offset ->
        val day = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -offset) }
        usage.cost(day.time)
    }
    return total / window
}

/** 表盘绘制（几何：stroke 15dp，R = 宽/2 - stroke/2 - 4dp，圆心 y = 4 + R + stroke/2） */
private fun DrawScope.drawGauge(ratio: Float) {
    val strokeW = 15.dp.toPx()
    val radius = size.width / 2f - strokeW / 2f - 4.dp.toPx()
    val center = Offset(size.width / 2f, 4.dp.toPx() + radius + strokeW / 2f)
    val trackColor = Color.White.copy(alpha = 0.20f)
    val tickColor = Color.White.copy(alpha = 0.32f)
    val arcStyle = Stroke(width = strokeW, cap = StrokeCap.Round)

    // 轨道（完整 240°）
    drawArc(
        color = trackColor,
        startAngle = ARC_START,
        sweepAngle = ARC_SWEEP,
        useCenter = false,
        topLeft = Offset(center.x - radius, center.y - radius),
        size = androidx.compose.ui.geometry.Size(radius * 2f, radius * 2f),
        style = arcStyle
    )

    // 内圈刻度：每 40° 一根，仪表仪器的"刻度感"
    val tickOuter = radius - strokeW / 2f - 3.dp.toPx()
    val tickInner = tickOuter - 6.dp.toPx()
    for (i in 0..6) {
        val angle = Math.toRadians((ARC_START + ARC_SWEEP / 6f * i).toDouble())
        val cosV = cos(angle).toFloat()
        val sinV = sin(angle).toFloat()
        drawLine(
            color = tickColor,
            start = Offset(center.x + tickInner * cosV, center.y + tickInner * sinV),
            end = Offset(center.x + tickOuter * cosV, center.y + tickOuter * sinV),
            strokeWidth = 2.dp.toPx(),
            cap = StrokeCap.Round
        )
    }

    // 续航弧（随弹簧动画展开：满弧 = 预计可用 30 天）
    if (ratio > 0.003f) {
        drawArc(
            color = Color.White,
            startAngle = ARC_START,
            sweepAngle = ARC_SWEEP * ratio,
            useCenter = false,
            topLeft = Offset(center.x - radius, center.y - radius),
            size = androidx.compose.ui.geometry.Size(radius * 2f, radius * 2f),
            style = arcStyle
        )
        // 端点金色铆钉（白描边），仪表指针的"轴心帽"
        val endAngle = Math.toRadians((ARC_START + ARC_SWEEP * ratio).toDouble())
        val capPos = Offset(
            center.x + radius * cos(endAngle).toFloat(),
            center.y + radius * sin(endAngle).toFloat()
        )
        drawCircle(color = MeterGold, radius = 5.5.dp.toPx(), center = capPos)
        drawCircle(
            color = Color.White,
            radius = 5.5.dp.toPx(),
            center = capPos,
            style = Stroke(width = 2.dp.toPx())
        )
    }
}

/** 余量健康度胶囊：余额阈值与旧版渐变卡一致（≥10 充足 / ≥1 偏低 / 其余告急） */
@Composable
private fun BalanceHealthPill(balance: Double) {
    val (dot, text) = when {
        balance >= 10 -> Color(0xFF8BE39A) to "余量充足"
        balance >= 1 -> Color(0xFFFFCE7A) to "余额偏低"
        else -> Color(0xFFFF9E93) to "余额告急"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(Color.White.copy(alpha = 0.16f), RoundedCornerShape(50))
            .padding(horizontal = 9.dp, vertical = 4.dp)
    ) {
        Box(Modifier.size(6.dp).background(dot, RoundedCornerShape(50)))
        Spacer(Modifier.width(5.dp))
        Text(text, color = Color.White, style = MaterialTheme.typography.labelSmall)
    }
}

/** 表盘下方的小指标胶囊 */
@Composable
private fun HeroChip(title: String, value: Double?, symbol: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(Color.White.copy(alpha = 0.15f), RoundedCornerShape(50))
            .padding(horizontal = 11.dp, vertical = 5.dp)
    ) {
        Text(
            title,
            color = Color.White.copy(alpha = 0.72f),
            style = MaterialTheme.typography.labelSmall
        )
        Spacer(Modifier.width(4.dp))
        Text(
            value?.let { symbol + format(it) } ?: "—",
            color = Color.White,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold
        )
    }
}
