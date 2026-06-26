package com.biver.chartkit.compose

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.TextUnit

/**
 * 多平台文字绘制助手：取代 Android 专有的 `android.graphics.Paint` + `nativeCanvas.drawText`，
 * 改用 Compose 的 [TextMeasurer]，使渲染层在 Android / iOS / Desktop 上共用同一份代码。
 *
 * 坐标语义与原 Paint 实现保持一致：
 * - [drawBaselineLeft]：文本基线落在给定 y，左边缘在给定 x（≈ `Paint` 默认的 baseline 绘制）。
 * - [drawVCenterLeft]：文本竖直中心落在给定 y，左边缘在给定 x（用于右轴/光标标签）。
 *
 * 复用同一 [TextMeasurer] 实例时 Compose 内部会缓存测量结果，逐帧重复绘制开销很小。
 */
internal class ChartText(
    private val measurer: TextMeasurer,
    fontSize: TextUnit,
) {
    private val style = TextStyle(fontSize = fontSize)
    private val sample = measurer.measure("0", style)

    /** 行高（≈ `Paint.fontMetrics` 的 descent - ascent）。 */
    val lineHeight: Float = sample.size.height.toFloat()

    /** 文本像素宽度（≈ `Paint.measureText`）。 */
    fun measure(text: String): Float = measurer.measure(text, style).size.width.toFloat()

    private fun layout(text: String, color: Color, alpha: Float) =
        measurer.measure(
            text,
            if (alpha >= 1f) style.copy(color = color)
            else style.copy(color = color.copy(alpha = color.alpha * alpha)),
        )

    /** 基线语义绘制：基线在 [baselineY]，左边缘在 [left]。 */
    fun drawBaselineLeft(scope: DrawScope, text: String, left: Float, baselineY: Float, color: Color, alpha: Float = 1f) {
        val lr = layout(text, color, alpha)
        scope.drawText(lr, topLeft = Offset(left, baselineY - lr.firstBaseline))
    }

    /** 竖直居中绘制：竖直中心在 [yCenter]，左边缘在 [left]。 */
    fun drawVCenterLeft(scope: DrawScope, text: String, left: Float, yCenter: Float, color: Color, alpha: Float = 1f) {
        val lr = layout(text, color, alpha)
        scope.drawText(lr, topLeft = Offset(left, yCenter - lr.size.height / 2f))
    }
}
