package com.biver.chartkit

import com.biver.chartkit.indicator.ChartRegistry
import com.biver.chartkit.indicator.IndicatorLine
import com.biver.chartkit.indicator.IndicatorSeries
import com.biver.chartkit.indicator.Pane
import com.biver.chartkit.indicator.builtin.Indicators
import com.biver.chartkit.indicator.indicator
import com.biver.chartkit.model.Candle
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

private fun c(close: Double) = Candle(0L, close, close, close, close)

class IndicatorApiTest {

    @AfterTest fun tearDown() = ChartRegistry.clear()

    @Test fun dsl_creates_indicator_from_formula() {
        // 接入方只给一个公式即可创建副图（开源扩展点）
        val typicalPrice = indicator("TP", Pane.Sub) { candles ->
            listOf(IndicatorLine("TP", candles.map { (it.high + it.low + it.close) / 3.0 }))
        }
        val s = typicalPrice.compute(listOf(c(3.0), c(6.0)))
        assertEquals("TP", s.id)
        assertEquals(Pane.Sub, s.pane)
        assertEquals(listOf(3.0, 6.0), s.lines.single().values)
    }

    @Test fun registry_register_get_clear() {
        assertNull(ChartRegistry.get("MACD"))
        Indicators.registerDefaults()
        assertNotNull(ChartRegistry.get("MACD"))
        assertNotNull(ChartRegistry.get("RSI"))
        assertNotNull(ChartRegistry.get("SAR"))
        assertEquals(10, ChartRegistry.all().size)
        ChartRegistry.clear()
        assertNull(ChartRegistry.get("MACD"))
    }

    @Test fun series_requires_equal_length_lines() {
        assertFailsWith<IllegalArgumentException> {
            IndicatorSeries(
                "BAD", Pane.Sub,
                listOf(
                    IndicatorLine("a", listOf(1.0, 2.0)),
                    IndicatorLine("b", listOf(1.0)),
                )
            )
        }
    }
}
