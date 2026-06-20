package com.biver.chartkit

import com.biver.chartkit.indicator.LineStyle
import com.biver.chartkit.indicator.MovingAverage
import com.biver.chartkit.indicator.Pane
import com.biver.chartkit.indicator.builtin.Boll
import com.biver.chartkit.indicator.builtin.Ema
import com.biver.chartkit.indicator.builtin.Kdj
import com.biver.chartkit.indicator.builtin.Macd
import com.biver.chartkit.indicator.builtin.Ma
import com.biver.chartkit.indicator.builtin.Obv
import com.biver.chartkit.indicator.builtin.Rsi
import com.biver.chartkit.indicator.builtin.Sar
import com.biver.chartkit.indicator.builtin.VolMa
import com.biver.chartkit.indicator.builtin.Wr
import com.biver.chartkit.model.Candle
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val TOL = 1e-6

/** 测试用 candle：仅关心 close/high/low。 */
private fun c(close: Double, high: Double = close, low: Double = close, vol: Double = 0.0) =
    Candle(time = 0L, open = close, high = high, low = low, close = close, volume = vol)

private fun closes(vararg v: Double) = v.map { c(it) }

class BuiltinIndicatorTest {

    @Test fun ma_pane_and_values() {
        val s = Ma(intArrayOf(3)).compute(closes(1.0, 2.0, 3.0, 4.0, 5.0))
        assertEquals(Pane.Main, s.pane)
        assertEquals("MA3", s.lines[0].name)
        assertEquals(listOf(null, null, 2.0, 3.0, 4.0), s.lines[0].values)
    }

    @Test fun rsi_golden_wilder_close_to_close() {
        // close: 10,11,10,11,12,11 ; period 2
        // 期望: [null,null,50,75,87.5,43.75]（见设计文档手算）
        val s = Rsi(intArrayOf(2)).compute(closes(10.0, 11.0, 10.0, 11.0, 12.0, 11.0))
        val v = s.lines.single().values
        assertNull(v[0]); assertNull(v[1])
        assertEquals(50.0, v[2]!!, TOL)
        assertEquals(75.0, v[3]!!, TOL)
        assertEquals(87.5, v[4]!!, TOL)
        assertEquals(43.75, v[5]!!, TOL)
    }

    @Test fun kdj_seed_50_when_rsv_50() {
        // 单根: high12 low8 close10 -> rsv=50 -> K=D=J=50
        val s = Kdj().compute(listOf(c(close = 10.0, high = 12.0, low = 8.0)))
        assertEquals(50.0, s.lines[0].values[0]!!, TOL) // K
        assertEquals(50.0, s.lines[1].values[0]!!, TOL) // D
        assertEquals(50.0, s.lines[2].values[0]!!, TOL) // J
    }

    @Test fun kdj_j_equals_3k_minus_2d_invariant() {
        val data = listOf(
            c(10.0, 12.0, 8.0), c(11.0, 13.0, 9.0), c(9.0, 11.0, 7.0),
            c(12.0, 14.0, 10.0), c(13.0, 15.0, 11.0)
        )
        val s = Kdj().compute(data)
        val (k, d, j) = Triple(s.lines[0].values, s.lines[1].values, s.lines[2].values)
        for (i in data.indices) {
            assertEquals(3 * k[i]!! - 2 * d[i]!!, j[i]!!, TOL, "J invariant at $i")
        }
    }

    @Test fun macd_wiring_and_histogram_style() {
        val data = (1..10).map { c(it.toDouble()) }
        val s = Macd().compute(data)
        assertEquals(Pane.Sub, s.pane)
        assertEquals(listOf("DIF", "DEA", "MACD"), s.lines.map { it.name })
        assertEquals(LineStyle.Histogram, s.lines[2].style)
        // 交叉校验：DIF == EMA12 - EMA26 ; 柱 == 2*(DIF-DEA)
        val close = data.map { it.close }
        val e12 = MovingAverage.ema(close, 12)
        val e26 = MovingAverage.ema(close, 26)
        val dif = s.lines[0].values
        val dea = s.lines[1].values
        val bar = s.lines[2].values
        for (i in close.indices) {
            assertEquals(e12[i] - e26[i], dif[i]!!, TOL, "dif@$i")
            assertEquals(2.0 * (dif[i]!! - dea[i]!!), bar[i]!!, TOL, "bar@$i")
        }
        // 单调上涨 -> DIF 最终为正
        assertTrue(dif.last()!! > 0)
    }

    @Test fun boll_indicator_three_bands() {
        val data = closes(2.0, 4.0, 6.0, 8.0, 10.0)
        val s = Boll(period = 3, k = 2.0).compute(data)
        assertEquals(listOf("UP", "MB", "DN"), s.lines.map { it.name })
        assertEquals(4.0, s.lines[1].values[2]!!, TOL) // MB = MA(3)
    }

    @Test fun wr_golden() {
        // (close,high,low): (10,12,8)(11,13,9)(9,14,7) ; period 3
        val data = listOf(c(10.0, 12.0, 8.0), c(11.0, 13.0, 9.0), c(9.0, 14.0, 7.0))
        val v = Wr(intArrayOf(3)).compute(data).lines.single().values
        assertEquals(50.0, v[0]!!, TOL)                 // (12-10)/(12-8)*100
        assertEquals(40.0, v[1]!!, TOL)                 // (13-11)/(13-8)*100
        assertEquals(5.0 / 7.0 * 100.0, v[2]!!, TOL)    // (14-9)/(14-7)*100
    }

    @Test fun obv_golden() {
        val data = listOf(c(10.0, vol = 100.0), c(11.0, vol = 200.0), c(10.0, vol = 150.0), c(12.0, vol = 300.0))
        val v = Obv().compute(data).lines.single().values
        assertEquals(listOf(0.0, 200.0, 50.0, 350.0), v)
    }

    @Test fun sar_points_style_and_warmup() {
        val data = listOf(c(10.0, 11.0, 9.0), c(11.0, 12.0, 10.0), c(12.0, 13.0, 11.0), c(13.0, 14.0, 12.0))
        val s = Sar().compute(data)
        assertEquals(Pane.Main, s.pane)
        assertEquals(LineStyle.Points, s.lines[0].style)
        assertNull(s.lines[0].values[0])
        assertTrue(s.lines[0].values.drop(1).all { it != null })
    }

    /** #4 增量计算前提：最后 lookback 根重算的末值 == 全量末值（验证 lookback 取值足够）。 */
    @Test fun lookback_window_matches_full_last_value() {
        val data = (0 until 300).map { i ->
            val p = 50.0 + 10.0 * sin(i * 0.1)
            c(close = p, high = p + 1, low = p - 1, vol = 100.0 + i)
        }
        val inds = listOf(Ma(intArrayOf(7, 30)), Ema(), Boll(), Macd(), Kdj(), Rsi(), Wr(), VolMa())
        for (ind in inds) {
            if (ind.lookback >= data.size) continue
            val full = ind.compute(data)
            val tail = ind.compute(data.subList(data.size - ind.lookback, data.size))
            full.lines.indices.forEach { li ->
                val a = full.lines[li].values.last()
                val b = tail.lines[li].values.last()
                // 递归型（EMA/RSI/…）末值衰减到显示精度内即可（1e-2 远小于 2 位小数显示）
                if (a == null) assertNull(b) else assertEquals(a, b!!, 1e-2, "${ind.id} line$li last")
            }
        }
    }
}
