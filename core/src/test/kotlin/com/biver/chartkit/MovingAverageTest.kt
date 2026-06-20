package com.biver.chartkit

import com.biver.chartkit.indicator.MovingAverage
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

private const val TOL = 1e-6

private fun assertSeries(expected: List<Double?>, actual: List<Double?>, tol: Double = TOL) {
    assertEquals(expected.size, actual.size, "size mismatch")
    for (i in expected.indices) {
        val e = expected[i]
        if (e == null) assertNull(actual[i], "index $i should be null")
        else assertEquals(e, actual[i] ?: error("index $i null"), tol, "index $i")
    }
}

class MovingAverageTest {

    @Test fun sma_basic_with_leading_nulls() {
        val src = listOf(1.0, 2.0, 3.0, 4.0, 5.0)
        assertSeries(listOf(null, null, 2.0, 3.0, 4.0), MovingAverage.sma(src, 3))
    }

    @Test fun ema_is_continuous_and_correct() {
        // k = 2/3; ema0=1; ema1=1+2/3*(2-1)=1.66667; ema2=1.66667+2/3*(3-1.66667)=2.55556
        val out = MovingAverage.ema(listOf(1.0, 2.0, 3.0), 2)
        assertEquals(3, out.size)
        assertEquals(1.0, out[0], TOL)
        assertEquals(1.6666667, out[1], 1e-6)
        assertEquals(2.5555556, out[2], 1e-6)
    }

    @Test fun boll_middle_band_equals_sma_n() {
        // 修复点：中轨必须等于 MA(n)，而不是旧代码的 MA(n-1)
        val src = listOf(2.0, 4.0, 6.0, 8.0, 10.0)
        val (_, mb, _) = MovingAverage.boll(src, 3, 2.0)
        assertSeries(MovingAverage.sma(src, 3), mb)
        assertSeries(listOf(null, null, 4.0, 6.0, 8.0), mb)
    }

    @Test fun boll_bands_golden() {
        val src = listOf(2.0, 4.0, 6.0, 8.0, 10.0)
        val (up, _, dn) = MovingAverage.boll(src, 3, 2.0)
        val md = sqrt(8.0 / 3.0) // 窗口 [2,4,6] 关于均值4 的总体标准差
        assertEquals(4.0 + 2 * md, up[2]!!, TOL)
        assertEquals(4.0 - 2 * md, dn[2]!!, TOL)
        assertEquals(8.0 + 2 * md, up[4]!!, TOL)
        assertEquals(8.0 - 2 * md, dn[4]!!, TOL)
        assertNull(up[1])
    }
}
