package com.biver.chartkit.compose

import androidx.compose.runtime.Immutable
import com.biver.chartkit.model.TimeFrame

/**
 * 文案/数值格式化（KMP 版）。与 :compose 的 ChartFormatter 行为一致，
 * 区别仅在默认时间格式化经由平台日历（expect/actual，见 PlatformTime.kt）取本地时区，
 * 而非 `java.util.Calendar`——这样 chartkit 不依赖任何 kotlinx-datetime 版本。
 *
 * 数值格式化复用多平台的 [trimmed]（见 NumberFormat.kt，与 :compose 共享同一份）。
 * 文件名与 :compose 的 ChartFormatter.kt 不同，以便在 srcDir 共享中被精确排除而不误伤本副本。
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
            val dt = localTimeParts(t)
            return pad2(dt.hour) + ":" + pad2(dt.minute)
        }

        private fun defaultDateTime(t: Long): String {
            val dt = localTimeParts(t)
            return pad2(dt.month) + "-" + pad2(dt.dayOfMonth) + " " + pad2(dt.hour) + ":" + pad2(dt.minute)
        }
    }
}
