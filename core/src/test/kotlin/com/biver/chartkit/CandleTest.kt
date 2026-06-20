package com.biver.chartkit

import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CandleTest {

    @Test fun bullish_and_change() {
        val up = Candle(0L, open = 100.0, high = 110.0, low = 99.0, close = 105.0)
        assertTrue(up.isBullish)
        assertEquals(5.0, up.change, 1e-9)
        assertEquals(0.05, up.changeRate, 1e-9)

        val down = Candle(0L, open = 100.0, high = 101.0, low = 90.0, close = 95.0)
        assertFalse(down.isBullish)
        assertEquals(-0.05, down.changeRate, 1e-9)
    }

    @Test fun change_rate_safe_on_zero_open() {
        assertEquals(0.0, Candle(0L, 0.0, 0.0, 0.0, 0.0).changeRate, 1e-9)
    }

    @Test fun timeframe_open_alignment() {
        // M15 = 900_000ms；1_000_000 落在 [900_000,1_800_000) -> 起始 900_000
        assertEquals(900_000L, TimeFrame.M15.openTimeOf(1_000_000L))
        assertEquals(0L, TimeFrame.H1.openTimeOf(3_599_999L))
    }
}
