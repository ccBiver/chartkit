package com.biver.chartkit.indicator.builtin

import com.biver.chartkit.indicator.ChartRegistry
import com.biver.chartkit.indicator.Indicator
import com.biver.chartkit.indicator.IndicatorLine
import com.biver.chartkit.indicator.IndicatorSeries
import com.biver.chartkit.indicator.LineStyle
import com.biver.chartkit.indicator.MovingAverage
import com.biver.chartkit.indicator.Pane
import com.biver.chartkit.model.Candle
import kotlin.math.abs
import kotlin.math.max

/** MA：主图多周期简单均线（默认 7 / 30，可配）。 */
class Ma(private val periods: IntArray = intArrayOf(7, 30)) : Indicator {
    override val id = "MA"
    override val pane = Pane.Main
    override val lookback = (periods.maxOrNull() ?: 1).coerceAtLeast(1)   // SMA 精确
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val close = candles.map { it.close }
        val lines = periods.map { p -> IndicatorLine("MA$p", MovingAverage.sma(close, p)) }
        return IndicatorSeries(id, pane, lines)
    }
}

/** EMA：主图多周期指数均线（默认 5 / 10 / 30，可配）。连续无断点。 */
class Ema(private val periods: IntArray = intArrayOf(5, 10, 30)) : Indicator {
    override val id = "EMA"
    override val pane = Pane.Main
    override val lookback = (periods.maxOrNull() ?: 1) * 10               // 递归：×10 衰减到浮点精度
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val close = candles.map { it.close }
        val lines = periods.map { p -> IndicatorLine("EMA$p", MovingAverage.ema(close, p)) }
        return IndicatorSeries(id, pane, lines)
    }
}

/** BOLL：主图布林带（默认 20, 2，标准口径）。 */
class Boll(private val period: Int = 20, private val k: Double = 2.0) : Indicator {
    override val id = "BOLL"
    override val pane = Pane.Main
    override val lookback = period.coerceAtLeast(1)   // 精确
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val close = candles.map { it.close }
        val (up, mb, dn) = MovingAverage.boll(close, period, k)
        return IndicatorSeries(
            id, pane,
            listOf(
                IndicatorLine("UP", up),
                IndicatorLine("MB", mb),
                IndicatorLine("DN", dn),
            )
        )
    }
}

/** MACD：副图。DIF=EMA(fast)−EMA(slow)，DEA=EMA(DIF, signal)，柱=mult·(DIF−DEA)。 */
class Macd(
    private val fast: Int = 12,
    private val slow: Int = 26,
    private val signal: Int = 9,
    private val multiplier: Double = 2.0,
) : Indicator {
    override val id = "MACD"
    override val pane = Pane.Sub
    override val lookback = (slow + signal) * 10
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val close = candles.map { it.close }
        if (close.isEmpty()) {
            return IndicatorSeries(id, pane, listOf(
                IndicatorLine("DIF", emptyList()),
                IndicatorLine("DEA", emptyList()),
                IndicatorLine("MACD", emptyList(), LineStyle.Histogram),
            ))
        }
        val emaFast = MovingAverage.ema(close, fast)
        val emaSlow = MovingAverage.ema(close, slow)
        val dif = close.indices.map { emaFast[it] - emaSlow[it] }
        val dea = MovingAverage.ema(dif, signal)
        val bar = close.indices.map { multiplier * (dif[it] - dea[it]) }
        return IndicatorSeries(
            id, pane,
            listOf(
                IndicatorLine("DIF", dif),
                IndicatorLine("DEA", dea),
                IndicatorLine("MACD", bar, LineStyle.Histogram),
            )
        )
    }
}

/** KDJ：副图（默认 9,3,3）。K/D 以 50 播种，全程连续。 */
class Kdj(private val n: Int = 9, private val m1: Int = 3, private val m2: Int = 3) : Indicator {
    override val id = "KDJ"
    override val pane = Pane.Sub
    override val lookback = (n + m1 + m2) * 10
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val size = candles.size
        val kList = MutableList<Double?>(size) { null }
        val dList = MutableList<Double?>(size) { null }
        val jList = MutableList<Double?>(size) { null }
        var prevK = 50.0
        var prevD = 50.0
        for (i in 0 until size) {
            val start = maxOf(0, i - n + 1)
            var hh = candles[start].high
            var ll = candles[start].low
            for (x in start..i) {
                if (candles[x].high > hh) hh = candles[x].high
                if (candles[x].low < ll) ll = candles[x].low
            }
            val rsv = if (hh == ll) 0.0 else (candles[i].close - ll) / (hh - ll) * 100.0
            val kv = ((m1 - 1) * prevK + rsv) / m1
            val dv = ((m2 - 1) * prevD + kv) / m2
            kList[i] = kv
            dList[i] = dv
            jList[i] = 3 * kv - 2 * dv
            prevK = kv
            prevD = dv
        }
        return IndicatorSeries(
            id, pane,
            listOf(IndicatorLine("K", kList), IndicatorLine("D", dList), IndicatorLine("J", jList))
        )
    }
}

/**
 * RSI：副图（默认 6/12/24）。
 * 修正旧实现两处问题：
 *  1) 涨跌用 **收盘对收盘** close[i]−close[i-1]（旧代码错用单根振幅 (close−open)/open）；
 *  2) 采用 **Wilder 平滑**（旧代码用简单平均）。
 */
class Rsi(private val periods: IntArray = intArrayOf(6, 12, 24)) : Indicator {
    override val id = "RSI"
    override val pane = Pane.Sub
    override val lookback = (periods.maxOrNull() ?: 1) * 10
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val close = candles.map { it.close }
        val n = close.size
        val gains = DoubleArray(n)
        val losses = DoubleArray(n)
        for (i in 1 until n) {
            val d = close[i] - close[i - 1]
            gains[i] = max(d, 0.0)
            losses[i] = max(-d, 0.0)
        }
        val lines = periods.map { p -> IndicatorLine("RSI$p", rsiLine(gains, losses, p, n)) }
        return IndicatorSeries(id, pane, lines)
    }

    private fun rsiLine(gains: DoubleArray, losses: DoubleArray, p: Int, n: Int): List<Double?> {
        val out = MutableList<Double?>(n) { null }
        if (p <= 0 || n <= p) return out
        var avgGain = 0.0
        var avgLoss = 0.0
        for (i in 1..p) {
            avgGain += gains[i]
            avgLoss += losses[i]
        }
        avgGain /= p
        avgLoss /= p
        out[p] = rsiFrom(avgGain, avgLoss)
        for (i in p + 1 until n) {
            avgGain = (avgGain * (p - 1) + gains[i]) / p
            avgLoss = (avgLoss * (p - 1) + losses[i]) / p
            out[i] = rsiFrom(avgGain, avgLoss)
        }
        return out
    }

    private fun rsiFrom(avgGain: Double, avgLoss: Double): Double =
        if (avgLoss == 0.0) 100.0 else 100.0 - 100.0 / (1.0 + avgGain / avgLoss)
}

/** 成交量均线：副图（默认 5/10）。柱由渲染层按涨跌着色，这里只算均线。 */
class VolMa(private val periods: IntArray = intArrayOf(5, 10)) : Indicator {
    override val id = "VOLMA"
    override val pane = Pane.Sub
    override val lookback = (periods.maxOrNull() ?: 1).coerceAtLeast(1)
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val vol = candles.map { it.volume }
        val lines = periods.map { p -> IndicatorLine("VOLMA$p", MovingAverage.sma(vol, p)) }
        return IndicatorSeries(id, pane, lines)
    }
}

/** WR：威廉指标（副图，默认 14）。WR=(Hn−C)/(Hn−Ln)×100，区间 0..100。 */
class Wr(private val periods: IntArray = intArrayOf(14)) : Indicator {
    override val id = "WR"
    override val pane = Pane.Sub
    override val lookback = (periods.maxOrNull() ?: 1).coerceAtLeast(1)   // 仅依赖最近 n 根，精确
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val lines = periods.map { n ->
            val out = MutableList<Double?>(candles.size) { null }
            for (i in candles.indices) {
                val start = maxOf(0, i - n + 1)
                var hh = candles[start].high
                var ll = candles[start].low
                for (x in start..i) {
                    if (candles[x].high > hh) hh = candles[x].high
                    if (candles[x].low < ll) ll = candles[x].low
                }
                out[i] = if (hh == ll) 0.0 else (hh - candles[i].close) / (hh - ll) * 100.0
            }
            IndicatorLine("WR$n", out)
        }
        return IndicatorSeries(id, pane, lines)
    }
}

/** OBV：能量潮（副图，单线累计量）。依赖全历史，故全量重算。 */
class Obv : Indicator {
    override val id = "OBV"
    override val pane = Pane.Sub
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val out = MutableList<Double?>(candles.size) { null }
        var obv = 0.0
        for (i in candles.indices) {
            if (i > 0) {
                val d = candles[i].close - candles[i - 1].close
                obv += if (d > 0) candles[i].volume else if (d < 0) -candles[i].volume else 0.0
            }
            out[i] = obv
        }
        return IndicatorSeries(id, pane, listOf(IndicatorLine("OBV", out)))
    }
}

/** SAR：抛物线转向（主图散点）。路径相关（依赖历次转向），故全量重算。 */
class Sar(private val step: Double = 0.02, private val maxAf: Double = 0.2) : Indicator {
    override val id = "SAR"
    override val pane = Pane.Main
    override fun compute(candles: List<Candle>): IndicatorSeries {
        val n = candles.size
        val out = MutableList<Double?>(n) { null }
        if (n < 2) return IndicatorSeries(id, pane, listOf(IndicatorLine("SAR", out, LineStyle.Points)))
        var up = candles[1].close >= candles[0].close
        var af = step
        var ep = if (up) candles[1].high else candles[1].low
        var sar = if (up) candles[0].low else candles[0].high
        for (i in 1 until n) {
            sar += af * (ep - sar)
            if (up) {
                sar = minOf(sar, candles[i - 1].low, candles[if (i >= 2) i - 2 else i - 1].low)
                if (candles[i].low < sar) {          // 转空
                    up = false; sar = ep; ep = candles[i].low; af = step
                } else if (candles[i].high > ep) {
                    ep = candles[i].high; af = minOf(af + step, maxAf)
                }
            } else {
                sar = maxOf(sar, candles[i - 1].high, candles[if (i >= 2) i - 2 else i - 1].high)
                if (candles[i].high > sar) {         // 转多
                    up = true; sar = ep; ep = candles[i].high; af = step
                } else if (candles[i].low < ep) {
                    ep = candles[i].low; af = minOf(af + step, maxAf)
                }
            }
            out[i] = sar
        }
        return IndicatorSeries(id, pane, listOf(IndicatorLine("SAR", out, LineStyle.Points)))
    }
}

/** 一键注册全部内置指标。 */
object Indicators {
    fun registerDefaults() {
        listOf(Ma(), Ema(), Boll(), Sar(), Macd(), Kdj(), Rsi(), Wr(), Obv(), VolMa())
            .forEach(ChartRegistry::register)
    }
}
