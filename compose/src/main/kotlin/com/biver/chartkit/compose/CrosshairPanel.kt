package com.biver.chartkit.compose

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame
import kotlin.math.abs

/** 图例单项：值变化时滚动过渡（animate=true，最新根 live 更新用）；十字光标拖动时即时显示。 */
@Composable
internal fun LegendItem(name: String, value: Double, color: Color, fmt: (Double) -> String, animate: Boolean, fontSize: TextUnit) {
    val anim = animateFloatAsState(targetValue = value.toFloat(), animationSpec = tween(280), label = "legend")
    val shown = if (animate) anim.value.toDouble() else value
    BasicText(text = "$name ${fmt(shown)}", style = TextStyle(color = color, fontSize = fontSize))
}

/** 大数缩写（成交量等）：1.2K / 3.4M / 5.6B。 */
internal fun abbrevNum(v: Double): String {
    val a = abs(v)
    return when {
        a >= 1e9 -> fixed(v / 1e9, 2) + "B"
        a >= 1e6 -> fixed(v / 1e6, 2) + "M"
        a >= 1e3 -> fixed(v / 1e3, 2) + "K"
        else -> fixed(v, 2)
    }
}

/** 内置详情行：开 / 高 / 低 / 收 / 涨跌 / 涨跌幅 / 量（caller 未自定义时使用）。 */
internal fun defaultCrosshairRows(
    candle: Candle,
    formatter: ChartFormatter,
    labels: ChartLabels,
    theme: ChartTheme,
    upDownColor: UpDownColor,
    timeFrame: TimeFrame,
): List<CrosshairDetailRow> {
    val change = candle.close - candle.open
    val pct = if (candle.open != 0.0) change / candle.open * 100.0 else 0.0
    val amp = if (candle.close != 0.0) (candle.high - candle.low) / candle.close * 100.0 else 0.0
    val chColor = if (change >= 0) theme.upColor(upDownColor) else theme.downColor(upDownColor)
    val sign = if (change >= 0) "+" else ""
    fun pct2(v: Double) = fixed(v, 2)
    return listOf(
        CrosshairDetailRow(labels.time, formatter.crosshairTime(candle.time, timeFrame)),
        CrosshairDetailRow(labels.open, formatter.price(candle.open)),
        CrosshairDetailRow(labels.high, formatter.price(candle.high)),
        CrosshairDetailRow(labels.low, formatter.price(candle.low)),
        CrosshairDetailRow(labels.close, formatter.price(candle.close)),
        CrosshairDetailRow(labels.change, sign + formatter.price(change), chColor),
        CrosshairDetailRow(labels.changePct, "$sign${pct2(pct)}%", chColor),
        CrosshairDetailRow(labels.amplitude, "${pct2(amp)}%"),
        CrosshairDetailRow(labels.volume, formatter.volume(candle.volume)),
        CrosshairDetailRow(labels.turnover, formatter.volume(candle.turnover)),
    )
}

/** 十字光标详情浮窗：渲染若干「标签 / 数据」两列行。 */
@Composable
internal fun CrosshairPanel(
    rows: List<CrosshairDetailRow>,
    theme: ChartTheme,
    modifier: Modifier = Modifier,
) {
    val valueColor = if (theme.background.luminance() < 0.5f) Color.White else Color.Black
    Column(
        modifier = modifier
            .width(150.dp)
            .background(theme.background.copy(alpha = 0.92f), RoundedCornerShape(6.dp))
            .border(0.5.dp, theme.grid, RoundedCornerShape(6.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        rows.forEach { row ->
            Metric(
                label = row.label,
                value = row.value,
                labelColor = row.labelColor ?: theme.axisText,
                valueColor = row.color ?: valueColor,
                arrowColor = theme.axisText,   // › 用中性色，不跟涨跌
                onClick = row.onClick,
            )
        }
    }
}

/** 浮窗内一行：标签靠左、数据靠右（标题列 / 数据列）。可点击行（买/卖记录）尾部加中性色 › 提示。 */
@Composable
private fun Metric(
    label: String, value: String, labelColor: Color, valueColor: Color,
    arrowColor: Color, onClick: (() -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val rowMod = if (onClick != null) {
        Modifier.fillMaxWidth().clickable(interactionSource = interaction, indication = null) { onClick() }
    } else {
        Modifier.fillMaxWidth()
    }
    val font = 11.sp
    Row(
        modifier = rowMod,
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(label, style = TextStyle(color = labelColor, fontSize = font))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            BasicText(value, style = TextStyle(color = valueColor, fontSize = font))
            if (onClick != null) BasicText("›", style = TextStyle(color = arrowColor, fontSize = 17.sp))
        }
    }
}
