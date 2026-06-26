package com.biver.chartkit.compose

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.biver.chartkit.model.TimeFrame

/** 蜡烛/折线模式。 */
enum class ChartMode { Candle, TimeLine }

/** 涨跌配色方案。 */
enum class UpDownColor { GreenUpRedDown, RedUpGreenDown }

/** 尺寸配置，集中管理，杜绝散落的魔法数。 */
@Immutable
data class ChartDims(
    val candleMinWidth: Dp = 3.dp,
    val candleMaxWidth: Dp = 30.dp,
    val candleDefaultWidth: Dp = 8.dp,
    val candleGapRatio: Float = 0.25f,   // 间隙占单根宽度比例
    val axisTextSize: TextUnit = 10.sp,
    val legendTextSize: TextUnit = 11.sp,
    val rightAxisWidth: Dp = 46.dp,      // 右侧价格刻度留白
    val bottomAxisHeight: Dp = 18.dp,    // 底部时间轴高度
    val paneGap: Dp = 6.dp,
    val subLegendHeight: Dp = 16.dp,             // 副图顶部图例独占行高（数值不与指标重叠，类 Binance）
    val volumePaneFraction: Float = 0.16f,       // 成交量窗格占图高比例
    val subPaneFraction: Float = 0.18f,          // 每个副图窗格占图高比例
    val tradeMarkMaxVisibleBars: Int = 50,       // 可见 K 线超过此值时隐藏买卖标记
)

/** 主题：颜色 + 尺寸 + 网格密度。内置 [Dark]/[Light]，可自定义。 */
@Immutable
data class ChartTheme(
    val background: Color,
    val grid: Color,
    val axisText: Color,
    val candleUp: Color,
    val candleDown: Color,
    val crosshair: Color,
    val crosshairLabelBg: Color,
    val crosshairLabelText: Color,
    val lastPriceLine: Color,
    val timeLineStroke: Color,
    val timeLineFillTop: Color,
    val timeLineFillBottom: Color,
    val indicatorColors: List<Color>,    // 指标多线循环取色
    val volumeUpAlpha: Float = 0.6f,
    val gridRows: Int = 4,
    val dims: ChartDims = ChartDims(),
) {
    companion object {
        val Dark = ChartTheme(
            background = Color(0xFF0E1116),
            grid = Color(0xFF222934),
            axisText = Color(0xFF8A93A2),
            candleUp = Color(0xFF16C784),
            candleDown = Color(0xFFEA3943),
            crosshair = Color(0xFF9AA4B2),
            crosshairLabelBg = Color(0xFF2A313C),
            crosshairLabelText = Color(0xFFE6E9EE),
            lastPriceLine = Color(0xFFF0A020),
            timeLineStroke = Color(0xFF3B82F6),
            timeLineFillTop = Color(0x333B82F6),
            timeLineFillBottom = Color(0x003B82F6),
            indicatorColors = listOf(
                Color(0xFFF0A020), Color(0xFF3B82F6), Color(0xFFB44BE0),
                Color(0xFF16C784), Color(0xFFEA3943),
            ),
        )
        val Light = ChartTheme(
            background = Color(0xFFFFFFFF),
            grid = Color(0xFFEDEDED),
            axisText = Color(0xFF757880),
            candleUp = Color(0xFF16C784),
            candleDown = Color(0xFFEA3943),
            crosshair = Color(0xFF757880),
            crosshairLabelBg = Color(0xFF2A313C),
            crosshairLabelText = Color(0xFFFFFFFF),
            lastPriceLine = Color(0xFFF0A020),
            timeLineStroke = Color(0xFF3B82F6),
            timeLineFillTop = Color(0x333B82F6),
            timeLineFillBottom = Color(0x003B82F6),
            indicatorColors = listOf(
                Color(0xFFE0860E), Color(0xFF3B82F6), Color(0xFFB44BE0),
                Color(0xFF0E9C66), Color(0xFFD32E3B),
            ),
        )
    }

    fun upColor(scheme: UpDownColor): Color =
        if (scheme == UpDownColor.GreenUpRedDown) candleUp else candleDown

    fun downColor(scheme: UpDownColor): Color =
        if (scheme == UpDownColor.GreenUpRedDown) candleDown else candleUp
}

// 注：ChartFormatter 已抽到独立文件 ChartFormatter.kt（KMP 模块需平台特定的时间格式化实现）。
