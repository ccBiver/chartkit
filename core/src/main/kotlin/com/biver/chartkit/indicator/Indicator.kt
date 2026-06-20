package com.biver.chartkit.indicator

import com.biver.chartkit.model.Candle

/** 指标所在窗格：主图叠加 或 独立副图。 */
enum class Pane { Main, Sub }

/** 单条输出的绘制风格：折线 / 柱状 / 散点（如 SAR）。 */
enum class LineStyle { Line, Histogram, Points }

/**
 * 指标的一条输出序列，与 K 线列表**等长、按索引对齐**。
 * [values] 中的 `null` 表示该位置无值（如均线前置窗口）；渲染层应**跨 null 不连线**，
 * 而不是画到 0 —— 这样均线/EMA 不会再出现「断断续续」或掉到底部的伪影。
 */
data class IndicatorLine(
    val name: String,
    val values: List<Double?>,
    val style: LineStyle = LineStyle.Line,
)

/**
 * 一个指标的完整计算结果：可包含多条线/柱（如 MACD = DIF + DEA + 柱）。
 */
data class IndicatorSeries(
    val id: String,
    val pane: Pane,
    val lines: List<IndicatorLine>,
) {
    init {
        // 所有线必须等长，保证渲染层按索引对齐时不越界
        val n = lines.firstOrNull()?.values?.size ?: 0
        require(lines.all { it.values.size == n }) {
            "IndicatorSeries[$id]: all lines must have the same length ($n)"
        }
    }

    val size: Int get() = lines.firstOrNull()?.values?.size ?: 0
}

/**
 * 指标计算单元。无副作用：输入 K 线，输出独立的 [IndicatorSeries]，**不写回 Candle**。
 *
 * 扩展方式：实现本接口并 [ChartRegistry.register]，或用 [indicator] DSL 直接由一个公式创建。
 */
interface Indicator {
    /** 唯一标识，用于注册/查找/选择副图。 */
    val id: String

    /** 主图叠加还是独立副图。 */
    val pane: Pane

    /**
     * 末根增量重算窗口：计算「最新一根」的指标值所需的回看根数。
     * 渲染层在「仅更新末根 / 追加一根」时，只对最后 [lookback] 根重算并取末值拼接，省去全量重算。
     *  - 有限回看（MA/BOLL）：= 周期数，结果精确；
     *  - 递归型（EMA/MACD/KDJ/RSI）：取周期的若干倍，使种子影响衰减到浮点精度内；
     *  - 默认 [Int.MAX_VALUE]：每次全量重算（适合依赖全历史、无法局部化的指标）。
     */
    val lookback: Int get() = Int.MAX_VALUE

    /** 全量计算：输入 K 线，输出与之等长、按索引对齐的 [IndicatorSeries]。 */
    fun compute(candles: List<Candle>): IndicatorSeries
}

/**
 * 用一个公式快速创建指标（开源库核心卖点：接入方给个 lambda 就能加主/副图）。
 *
 * 示例：
 * ```
 * val vwap = indicator("VWAP", Pane.Sub) { candles ->
 *     listOf(IndicatorLine("VWAP", candles.runningVwap()))
 * }
 * ```
 */
fun indicator(
    id: String,
    pane: Pane = Pane.Sub,
    lookback: Int = Int.MAX_VALUE,
    block: (List<Candle>) -> List<IndicatorLine>,
): Indicator = object : Indicator {
    override val id: String = id
    override val pane: Pane = pane
    override val lookback: Int = lookback
    override fun compute(candles: List<Candle>): IndicatorSeries =
        IndicatorSeries(id, pane, block(candles))
}
