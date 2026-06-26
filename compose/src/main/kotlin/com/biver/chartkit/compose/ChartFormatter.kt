package com.biver.chartkit.compose

import androidx.compose.runtime.Immutable
import com.biver.chartkit.model.TimeFrame

/**
 * 文案/数值格式化，由宿主注入（精度、时间、量纲）。
 *
 * 数值格式化复用多平台的 [trimmed]（见 NumberFormat.kt）；默认时间格式化为本地时区，
 * 用 `java.util.Calendar` 实现（Android/JVM 专有）。KMP 模块用 kotlinx-datetime 提供等价实现。
 */
@Immutable
class ChartFormatter(
    val price: (Double) -> String = { trimmed(it, 2) },
    val volume: (Double) -> String = { compact(it) },
    val time: (Long, TimeFrame) -> String = { t, _ -> defaultTime(t) },
    /** 十字光标底部时间标签（比刻度更完整，含日期）。 */
    val crosshairTime: (Long, TimeFrame) -> String = { t, _ -> defaultDateTime(t) },
) {
    companion object {
        val Default = ChartFormatter()

        private fun compact(v: Double): String = when {
            v >= 1_000_000_000 -> trimmed(v / 1_000_000_000, 2) + "B"
            v >= 1_000_000 -> trimmed(v / 1_000_000, 2) + "M"
            v >= 1_000 -> trimmed(v / 1_000, 2) + "K"
            else -> trimmed(v, 2)
        }

        private fun defaultTime(t: Long): String {
            // 本地时区 HH:mm（之前用 UTC 算导致与本地时间差时区偏移；宿主可注入更完整格式）
            val cal = java.util.Calendar.getInstance()
            cal.timeInMillis = t
            return pad2(cal.get(java.util.Calendar.HOUR_OF_DAY)) + ":" + pad2(cal.get(java.util.Calendar.MINUTE))
        }

        private fun defaultDateTime(t: Long): String {
            val cal = java.util.Calendar.getInstance()
            cal.timeInMillis = t
            return pad2(cal.get(java.util.Calendar.MONTH) + 1) + "-" + pad2(cal.get(java.util.Calendar.DAY_OF_MONTH)) +
                " " + pad2(cal.get(java.util.Calendar.HOUR_OF_DAY)) + ":" + pad2(cal.get(java.util.Calendar.MINUTE))
        }
    }
}
