package com.biver.chartkit.model

/**
 * 一根 K 线（不可变）。只承载行情数据，**不含任何屏幕坐标或指标值**
 * —— 坐标由渲染层的 Transform 实时计算，指标由 indicator 层独立产出并缓存。
 *
 * @param time     开盘时间戳（毫秒）
 * @param open     开盘价
 * @param high     最高价
 * @param low      最低价
 * @param close    收盘价
 * @param volume   成交量
 * @param turnover 成交额（计价币），可选
 */
data class Candle(
    val time: Long,
    val open: Double,
    val high: Double,
    val low: Double,
    val close: Double,
    val volume: Double = 0.0,
    val turnover: Double = 0.0,
) {
    /** 是否上涨（收 >= 开） */
    val isBullish: Boolean get() = close >= open

    /** 涨跌额 */
    val change: Double get() = close - open

    /** 涨跌幅（比例，0.05 = 5%）；开盘价为 0 时返回 0 */
    val changeRate: Double get() = if (open == 0.0) 0.0 else (close - open) / open
}
