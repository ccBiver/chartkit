package com.biver.chartkit.model

/**
 * K 线周期。[millis] 为该周期对应的毫秒数，用于实时归并（判断 tick 属于当前根还是新根）。
 */
enum class TimeFrame(val millis: Long) {
    M1(60_000L),
    M5(300_000L),
    M15(900_000L),
    M30(1_800_000L),
    H1(3_600_000L),
    H2(7_200_000L),
    H4(14_400_000L),
    H6(21_600_000L),
    H12(43_200_000L),
    D1(86_400_000L),
    W1(604_800_000L),
    MN1(2_592_000_000L); // 近似 30 天，仅用于 tick 归并的粗略判断

    /** 给定时间戳所属周期的起始时间戳（按 UTC 对齐）。 */
    fun openTimeOf(timestamp: Long): Long = timestamp - (timestamp % millis)
}
