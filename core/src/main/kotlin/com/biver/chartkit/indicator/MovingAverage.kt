package com.biver.chartkit.indicator

import kotlin.math.sqrt

/**
 * 指标计算的纯函数工具。全部无副作用，便于单测。
 */
internal object MovingAverage {

    /**
     * 简单移动平均 SMA(period)。前 period-1 个位置返回 null（无值，不连线）。
     */
    fun sma(src: List<Double>, period: Int): List<Double?> {
        val out = MutableList<Double?>(src.size) { null }
        if (period <= 0) return out
        var sum = 0.0
        for (i in src.indices) {
            sum += src[i]
            if (i >= period) sum -= src[i - period]
            if (i >= period - 1) out[i] = sum / period
        }
        return out
    }

    /**
     * 指数移动平均 EMA(period)，系数 k = 2/(period+1)，以 src[0] 播种。
     * 全程非空、连续 —— 解决旧实现 EMA 断续问题。
     */
    fun ema(src: List<Double>, period: Int): List<Double> {
        if (src.isEmpty()) return emptyList()
        val k = 2.0 / (period + 1)
        val out = ArrayList<Double>(src.size)
        var prev = src[0]
        out.add(prev)
        for (i in 1 until src.size) {
            prev += k * (src[i] - prev)
            out.add(prev)
        }
        return out
    }

    /**
     * 标准 Bollinger Band：
     * - 中轨 MB = SMA(close, period)              ← 修正旧代码用 (period-1) 均线的 bug
     * - 标准差 MD = 总体标准差（÷period），以 MB 为均值
     * - 上轨 UP = MB + k·MD，下轨 DN = MB − k·MD
     *
     * @return Triple(up, mb, dn)，三条等长、与 src 对齐，前 period-1 为 null。
     */
    fun boll(src: List<Double>, period: Int, k: Double): Triple<List<Double?>, List<Double?>, List<Double?>> {
        val mb = sma(src, period)
        val up = MutableList<Double?>(src.size) { null }
        val dn = MutableList<Double?>(src.size) { null }
        for (i in src.indices) {
            val mean = mb[i] ?: continue
            var sq = 0.0
            for (j in i - period + 1..i) {
                val d = src[j] - mean
                sq += d * d
            }
            val md = sqrt(sq / period)
            up[i] = mean + k * md
            dn[i] = mean - k * md
        }
        return Triple(up, mb, dn)
    }
}
