package com.biver.chartkit.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.biver.chartkit.compose.ChartTheme
import com.biver.chartkit.compose.KLineChart
import com.biver.chartkit.compose.KLineUpdate
import com.biver.chartkit.compose.UpDownColor
import com.biver.chartkit.compose.rememberKLineChartState
import com.biver.chartkit.indicator.builtin.Boll
import com.biver.chartkit.indicator.builtin.Ema
import com.biver.chartkit.indicator.builtin.Kdj
import com.biver.chartkit.indicator.builtin.Ma
import com.biver.chartkit.indicator.builtin.Macd
import com.biver.chartkit.indicator.builtin.Obv
import com.biver.chartkit.indicator.builtin.Rsi
import com.biver.chartkit.indicator.builtin.Sar
import com.biver.chartkit.indicator.builtin.Wr
import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            var dark by remember { mutableStateOf(true) }
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                DemoScreen(dark = dark, onToggleTheme = { dark = !dark })
            }
        }
    }
}

private val TIMEFRAMES = listOf(
    "1m" to TimeFrame.M1, "5m" to TimeFrame.M5, "15m" to TimeFrame.M15,
    "1H" to TimeFrame.H1, "1D" to TimeFrame.D1,
)
private val MAIN_OPTIONS = listOf("MA", "EMA", "BOLL", "SAR")
private val SUB_OPTIONS = listOf("MACD", "KDJ", "RSI", "WR", "OBV")

@Composable
private fun DemoScreen(dark: Boolean, onToggleTheme: () -> Unit) {
    var timeFrame by remember { mutableStateOf(TimeFrame.M15) }
    val mainSel = remember { mutableStateListOf("MA") }
    val subs = remember { mutableStateListOf("MACD") }

    // Regenerate sample data when the timeframe (bar spacing) changes → replays the entrance reveal.
    val candles = remember(timeFrame) { sampleCandles(intervalMs = timeFrame.millis) }
    val state = rememberKLineChartState(timeFrame = timeFrame)
    LaunchedEffect(candles) { state.applyUpdate(KLineUpdate.RESET, candles) }

    val mainIndicators = mainSel.mapNotNull {
        when (it) {
            "MA" -> Ma(intArrayOf(7, 25, 99)); "EMA" -> Ema()
            "BOLL" -> Boll(20, 2.0); "SAR" -> Sar(); else -> null
        }
    }
    val subIndicators = subs.mapNotNull {
        when (it) {
            "MACD" -> Macd(); "KDJ" -> Kdj(); "RSI" -> Rsi()
            "WR" -> Wr(); "OBV" -> Obv(); else -> null
        }
    }

    // Page background follows the chart theme so the whole screen is cohesive (no light band around the chart).
    val pageBg = if (dark) ChartTheme.Dark.background else ChartTheme.Light.background
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = pageBg,
        contentColor = if (dark) Color.White else Color.Black,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .verticalScroll(rememberScrollState())
                .padding(vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("chartkit demo", style = MaterialTheme.typography.titleLarge)
                Button(onClick = onToggleTheme) { Text(if (dark) "Light" else "Dark") }
            }

            ChipRow("Timeframe", TIMEFRAMES.map { it.first }, selected = { it == currentTfLabel(timeFrame) }) { label ->
                timeFrame = TIMEFRAMES.first { it.first == label }.second
            }

            KLineChart(
                state = state,
                modifier = Modifier
                    .fillMaxWidth()
                    .height((320 + 70 * subIndicators.size).dp),
                theme = if (dark) ChartTheme.Dark else ChartTheme.Light,
                upDownColor = UpDownColor.GreenUpRedDown,
                mainIndicators = mainIndicators,
                subIndicators = subIndicators,
            )

            ChipRow("Main (overlay)", MAIN_OPTIONS, selected = { it in mainSel }) {
                if (it in mainSel) mainSel.remove(it) else mainSel.add(it)
            }
            ChipRow("Sub-panes", SUB_OPTIONS, selected = { it in subs }) {
                if (it in subs) subs.remove(it) else subs.add(it)
            }
        }
    }
}

private fun currentTfLabel(tf: TimeFrame): String = TIMEFRAMES.first { it.second == tf }.first

@Composable
private fun ChipRow(
    title: String,
    options: List<String>,
    selected: (String) -> Boolean,
    onToggle: (String) -> Unit,
) {
    Text(title, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = 12.dp))
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp)
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { id ->
            FilterChip(
                selected = selected(id),
                onClick = { onToggle(id) },
                label = { Text(id) },
            )
        }
    }
}

/**
 * Deterministic fake market data so the demo needs no network: a random walk with a slowly
 * drifting trend (so there are real up/down legs), irregular bodies and wicks, and volume that
 * scales with volatility. Seeded by [intervalMs] so each timeframe looks different but stable.
 */
private fun sampleCandles(
    n: Int = 240,
    startTime: Long = 1_700_000_000_000L,
    intervalMs: Long = 15 * 60 * 1000L,
): List<Candle> {
    var seed = 88172645463325252L xor intervalMs
    fun rnd(): Double {                       // xorshift64 → [0,1), deterministic
        seed = seed xor (seed shl 13)
        seed = seed xor (seed ushr 7)
        seed = seed xor (seed shl 17)
        return (seed ushr 11).toDouble() / (1L shl 53).toDouble()
    }

    val out = ArrayList<Candle>(n)
    var price = 100.0
    var trend = 0.0
    for (i in 0 until n) {
        trend = trend * 0.90 + (rnd() - 0.5) * 0.6      // 趋势缓慢游走，制造上涨/下跌段
        val open = price
        val move = trend + (rnd() - 0.5) * 2.2          // 单根波动
        var close = open + move
        if (close < 20.0) close = 20.0 + rnd() * 2       // 价格下限保护
        val bodyHi = maxOf(open, close)
        val bodyLo = minOf(open, close)
        val high = bodyHi + rnd() * rnd() * 2.4          // 影线长短不一（rnd² 偏短、偶尔很长）
        val low = bodyLo - rnd() * rnd() * 2.4
        val vol = 300.0 + rnd() * 900.0 + abs(move) * 350.0   // 波动越大量越大
        out.add(Candle(startTime + i * intervalMs, open, high, low, close, vol, vol * close))
        price = close
    }
    return out
}
