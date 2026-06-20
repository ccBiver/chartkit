package com.biver.chartkit.indicator

/**
 * 指标注册表。内置指标与接入方自定义指标统一登记，按 id 查找。
 * 线程安全（简单同步），注册通常在初始化阶段完成。
 */
object ChartRegistry {
    private val indicators = LinkedHashMap<String, Indicator>()

    @Synchronized
    fun register(indicator: Indicator) {
        indicators[indicator.id] = indicator
    }

    @Synchronized
    fun get(id: String): Indicator? = indicators[id]

    @Synchronized
    fun all(): List<Indicator> = indicators.values.toList()

    @Synchronized
    fun unregister(id: String) {
        indicators.remove(id)
    }

    @Synchronized
    fun clear() = indicators.clear()
}
