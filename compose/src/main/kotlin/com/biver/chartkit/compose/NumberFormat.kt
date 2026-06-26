package com.biver.chartkit.compose

import kotlin.math.abs
import kotlin.math.round

/**
 * 多平台数字格式化（仅用 kotlin.math，无 `java.lang.Math` / `String.format`），
 * 供 Android / iOS / Desktop 共用，行为与原 JVM 实现保持一致。
 */

/** 定点小数：始终保留 [digits] 位（≈ `String.format("%.Nf", v)`）。 */
internal fun fixed(v: Double, digits: Int): String {
    if (v.isNaN()) return "NaN"
    val neg = v < 0
    var p = 1.0
    repeat(digits) { p *= 10 }
    val scaled = round(abs(v) * p).toLong()
    val unit = p.toLong()
    val intPart = scaled / unit
    val frac = scaled % unit
    val fracStr = if (digits > 0) "." + frac.toString().padStart(digits, '0') else ""
    val sign = if (neg && scaled != 0L) "-" else ""
    return "$sign$intPart$fracStr"
}

/** 四舍五入到 [digits] 位后去掉多余尾零（≈ 原 ChartFormatter 的 `Math.round(v*p)/p` 风格）。 */
internal fun trimmed(v: Double, digits: Int): String {
    if (v.isNaN()) return "--"
    var p = 1.0
    repeat(digits) { p *= 10 }
    return (round(v * p) / p).toString()
}

/** 左补零到 2 位（≈ `"%02d".format(n)`）。 */
internal fun pad2(n: Int): String = if (n < 10) "0$n" else n.toString()
