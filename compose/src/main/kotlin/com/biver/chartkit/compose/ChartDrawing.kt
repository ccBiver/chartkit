package com.biver.chartkit.compose

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** 全屏按钮图标：四角括号（自绘，无需图片资源）。 */
@Composable
internal fun FullscreenGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val s = size.minDimension
        val len = s * 0.34f
        val w = (s * 0.10f).coerceAtLeast(2f)
        drawLine(color, Offset(0f, len), Offset(0f, 0f), w)
        drawLine(color, Offset(0f, 0f), Offset(len, 0f), w)
        drawLine(color, Offset(s - len, 0f), Offset(s, 0f), w)
        drawLine(color, Offset(s, 0f), Offset(s, len), w)
        drawLine(color, Offset(0f, s - len), Offset(0f, s), w)
        drawLine(color, Offset(0f, s), Offset(len, s), w)
        drawLine(color, Offset(s, s - len), Offset(s, s), w)
        drawLine(color, Offset(s - len, s), Offset(s, s), w)
    }
}

// 确定性「假行情」：多个正弦叠加，形似真实 K 线（归一化大致 0..1，按 i 取值，无随机）。
private fun skClose(i: Int): Float {
    val t = i.toFloat()
    return (0.5f + 0.26f * sin(t * 0.16f) + 0.12f * sin(t * 0.045f + 1.2f) + 0.05f * sin(t * 0.9f))
        .coerceIn(0.05f, 0.95f)
}
private fun skWick(i: Int): Float = 0.018f + 0.022f * abs(sin(i * 1.3f))
private fun skVol(i: Int): Float = 0.30f + 0.45f * abs(sin(i * 0.22f + 0.5f))

/**
 * 骨架屏：无数据时画一套「幽灵行情」——淡网格 + 蜡烛（含影线、涨跌着色）+ 平滑均线 + 成交量 + 副图占位。
 * 窗格分配（主图/量/副图）与真实图一致，根数与实体宽由 [candleWidthPx] / [gapRatio] 决定；整体压低透明度并叠扫光。
 */
internal fun DrawScope.drawSkeleton(
    theme: ChartTheme, up: Color, down: Color, phase: Float,
    candleWidthPx: Float, gapRatio: Float, showVolume: Boolean, subCount: Int,
) {
    val w = size.width
    val h = size.height
    val cw = candleWidthPx.coerceAtLeast(1f)
    val n = (w / cw).toInt().coerceIn(1, 400)
    val bodyW = cw * (1f - gapRatio)

    // 窗格分配：与真实图同比例（主图 + 可选成交量 + 各副图）
    val gap = h * 0.02f
    val volH = if (showVolume) h * theme.dims.volumePaneFraction else 0f
    val subTotal = if (subCount > 0) (h * theme.dims.subPaneFraction * subCount).coerceAtMost(h * 0.5f) else 0f
    val mainTop = h * 0.05f
    val mainBot = h - volH - subTotal - gap
    val volTop = mainBot + gap
    val volBot = mainBot + volH

    fun cx(i: Int): Float = cw * (i + 0.5f)
    fun sweep(i: Int, base: Float, peak: Float): Float =
        (peak - abs(i.toFloat() / n - phase) * (peak - base) * 2.4f).coerceIn(base, peak)

    // 主图网格
    val rows = 4
    for (r in 0..rows) {
        val y = mainTop + (mainBot - mainTop) * r / rows
        drawLine(theme.grid, Offset(0f, y), Offset(w, y), 1f)
    }

    // 价格区间（含影线）
    var lo = Float.MAX_VALUE; var hi = -Float.MAX_VALUE
    for (i in 0 until n) {
        hi = max(hi, skClose(i) + skWick(i))
        lo = min(lo, skClose(i) - skWick(i))
    }
    val pad = (hi - lo) * 0.08f
    lo -= pad; hi += pad
    fun yMain(v: Float): Float = mainTop + (hi - v) / (hi - lo) * (mainBot - mainTop)

    // 蜡烛（影线 + 实体，涨跌淡色）
    for (i in 0 until n) {
        val close = skClose(i)
        val open = if (i == 0) close - 0.03f else skClose(i - 1)
        val bull = close >= open
        val color = (if (bull) up else down).copy(alpha = sweep(i, 0.10f, 0.30f))
        val x = cx(i)
        drawLine(color, Offset(x, yMain(max(open, close) + skWick(i))), Offset(x, yMain(min(open, close) - skWick(i))), 1f)
        val top = yMain(max(open, close)); val bot = yMain(min(open, close))
        drawRect(color, Offset(x - bodyW / 2f, top), androidx.compose.ui.geometry.Size(bodyW, max(1f, bot - top)))
    }

    // 平滑均线（窗口 5 居中），淡指标色
    val maColor = theme.indicatorColors.firstOrNull() ?: theme.axisText
    val path = Path()
    var started = false
    for (i in 0 until n) {
        var sum = 0f; var cnt = 0
        for (k in (i - 2)..(i + 2)) if (k in 0 until n) { sum += skClose(k); cnt++ }
        val y = yMain(sum / cnt); val x = cx(i)
        if (!started) { path.moveTo(x, y); started = true } else path.lineTo(x, y)
    }
    drawPath(path, maColor.copy(alpha = 0.28f), style = Stroke(width = 1.6f))

    // 成交量
    if (showVolume) {
        for (i in 0 until n) {
            val bull = skClose(i) >= (if (i == 0) skClose(i) else skClose(i - 1))
            val vh = skVol(i) * (volBot - volTop)
            val color = (if (bull) up else down).copy(alpha = sweep(i, 0.08f, 0.22f))
            drawRect(color, Offset(cx(i) - bodyW / 2f, volBot - vh), androidx.compose.ui.geometry.Size(bodyW, vh))
        }
    }

    // 副图占位：每格一条幽灵指标线（不同相位错开，像 MACD/KDJ/RSI）
    if (subCount > 0) {
        val eachH = (subTotal - gap * subCount) / subCount
        var top = volBot + gap
        for (p in 0 until subCount) {
            val bottom = top + eachH
            drawLine(theme.grid, Offset(0f, top), Offset(w, top), 1f)
            val col = theme.indicatorColors[p % theme.indicatorColors.size]
            val subPath = Path()
            var st = false
            for (i in 0 until n) {
                // 0..1 波形，按副图序号错开相位
                val v = 0.5f + 0.32f * sin(i * 0.18f + p * 1.7f) + 0.12f * sin(i * 0.06f)
                val y = top + (eachH * 0.18f) + (1f - v.coerceIn(0f, 1f)) * (eachH * 0.64f)
                val x = cx(i)
                if (!st) { subPath.moveTo(x, y); st = true } else subPath.lineTo(x, y)
            }
            drawPath(subPath, col.copy(alpha = 0.26f), style = Stroke(width = 1.4f))
            top = bottom + gap
        }
    }
}

/** 跨 null 不连线地绘制一条指标线（解决断续）。 */
internal fun DrawScope.drawSeriesLine(
    values: List<Double?>,
    first: Int,
    last: Int,
    centerX: (Int) -> Float,
    yOf: (Double) -> Float,
    color: Color,
    alpha: Float,
    path: Path,
) {
    path.reset()
    var started = false
    for (i in first..last) {
        val v = values.getOrNull(i)
        if (v == null) { started = false; continue }
        val x = centerX(i); val y = yOf(v)
        if (!started) { path.moveTo(x, y); started = true } else path.lineTo(x, y)
    }
    drawPath(path, color, alpha = alpha, style = Stroke(width = 1.5f))
}

/** 散点绘制（SAR 等）：每个非空值画一个小圆点，不连线。半径随蜡烛宽自适应。 */
internal fun DrawScope.drawSeriesPoints(
    values: List<Double?>,
    first: Int,
    last: Int,
    centerX: (Int) -> Float,
    yOf: (Double) -> Float,
    color: Color,
    candleWidth: Float,
) {
    val r = (candleWidth * 0.12f).coerceIn(1.2f, 3f)
    for (i in first..last) {
        val v = values.getOrNull(i) ?: continue
        drawCircle(color, r, Offset(centerX(i), yOf(v)))
    }
}
