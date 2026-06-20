package com.biver.chartkit.compose

import com.biver.chartkit.indicator.Indicator
import com.biver.chartkit.indicator.IndicatorSeries
import com.biver.chartkit.model.Candle

/** 指标增量计算的缓存：保存上一次输入与输出，供 [incrementalCompute] 复用。 */
internal class IndicatorCache {
    var data: List<Candle> = emptyList()
    var series: List<IndicatorSeries> = emptyList()
}

/**
 * 指标计算：仅「更新末根」或「追加一根」时走增量——只对最后 [Indicator.lookback] 根重算并取末值，
 * 拼接到上次结果上，省去全量重算；其余情况（首屏 / 切周期 / 头部加载更多 / 指标变更）全量重算。
 *
 * 计算在调用方的后台线程执行（本函数纯计算、无副作用，[cache] 由调用方更新）。
 */
internal fun incrementalCompute(
    indicators: List<Indicator>,
    data: List<Candle>,
    prevData: List<Candle>,
    prevSeries: List<IndicatorSeries>,
): List<IndicatorSeries> {
    if (data.isEmpty()) return emptyList()

    val pLast = prevData.lastIndex
    val canInc = prevData.isNotEmpty() &&
        prevSeries.size == indicators.size &&
        indicators.indices.all { indicators[it].id == prevSeries[it].id } &&
        data.size >= prevData.size && data.size - prevData.size <= 1 &&     // 仅末根更新 / 追加一根
        data.first().time == prevData.first().time &&                       // 非头部插入 / 非重置
        data.getOrNull(pLast)?.time == prevData[pLast].time &&              // 上次末根仍在原位
        (pLast < 1 || data.getOrNull(pLast - 1)?.time == prevData[pLast - 1].time)

    if (!canInc) return indicators.map { it.compute(data) }

    val sameSize = data.size == prevData.size
    return indicators.mapIndexed { i, ind ->
        val prev = prevSeries[i]
        val lb = ind.lookback
        if (lb <= 0 || lb >= data.size) return@mapIndexed ind.compute(data)
        // 用最后 lb 根重算，取每条线的末值（lb 足够大时末值即为精确值）
        val win = ind.compute(data.subList(data.size - lb, data.size))
        if (win.lines.size != prev.lines.size) return@mapIndexed ind.compute(data)
        val newLines = prev.lines.mapIndexed { li, line ->
            val base = if (sameSize) line.values.dropLast(1) else line.values
            line.copy(values = base + win.lines[li].values.last())
        }
        prev.copy(lines = newLines)
    }
}
