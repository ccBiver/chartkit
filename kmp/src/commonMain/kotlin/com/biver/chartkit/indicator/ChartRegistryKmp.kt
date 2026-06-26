package com.biver.chartkit.indicator

/**
 * 指标注册表（KMP 版）。与 :core 的实现相同，仅去掉 JVM 专有的 `@Synchronized`
 * （注册在初始化阶段完成，并发读取前已登记完毕，故无需同步）。
 *
 * 文件名与 :core 的 ChartRegistry.kt 不同，以便在 commonMain 的 srcDir 共享中被精确排除而不误伤本副本。
 */
object ChartRegistry {
    private val indicators = LinkedHashMap<String, Indicator>()

    fun register(indicator: Indicator) {
        indicators[indicator.id] = indicator
    }

    fun get(id: String): Indicator? = indicators[id]

    fun all(): List<Indicator> = indicators.values.toList()

    fun unregister(id: String) {
        indicators.remove(id)
    }

    fun clear() = indicators.clear()
}
