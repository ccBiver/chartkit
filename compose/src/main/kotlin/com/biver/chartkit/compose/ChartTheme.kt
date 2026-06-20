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

/** 文案/数值格式化，由宿主注入（精度、时间、量纲）。 */
@Immutable
class ChartFormatter(
    val price: (Double) -> String = { fmt(it, 2) },
    val volume: (Double) -> String = { compact(it) },
    val time: (Long, TimeFrame) -> String = { t, _ -> defaultTime(t) },
    /** 十字光标底部时间标签（比刻度更完整，含日期）。 */
    val crosshairTime: (Long, TimeFrame) -> String = { t, _ -> defaultDateTime(t) },
) {
    companion object {
        val Default = ChartFormatter()

        private fun fmt(v: Double, digits: Int): String {
            if (v.isNaN()) return "--"
            val p = Math.pow(10.0, digits.toDouble())
            return (Math.round(v * p) / p).toString()
        }

        private fun compact(v: Double): String = when {
            v >= 1_000_000_000 -> fmt(v / 1_000_000_000, 2) + "B"
            v >= 1_000_000 -> fmt(v / 1_000_000, 2) + "M"
            v >= 1_000 -> fmt(v / 1_000, 2) + "K"
            else -> fmt(v, 2)
        }

        private fun defaultTime(t: Long): String {
            // 本地时区 HH:mm（之前用 UTC 算导致与本地时间差时区偏移；宿主可注入更完整格式）
            val cal = java.util.Calendar.getInstance()
            cal.timeInMillis = t
            return "%02d:%02d".format(cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE))
        }

        private fun defaultDateTime(t: Long): String {
            val cal = java.util.Calendar.getInstance()
            cal.timeInMillis = t
            return "%02d-%02d %02d:%02d".format(
                cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH),
                cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE),
            )
        }
    }
}
