package com.biver.chartkit.compose

/**
 * Local (system-default timezone) calendar fields for an epoch-millis timestamp.
 *
 * chartkit deliberately does NOT depend on kotlinx-datetime: a consumer that pulls
 * kotlinx-datetime 0.7+ (where `kotlinx.datetime.Instant` was removed in favour of
 * `kotlin.time.Instant`) would otherwise version-conflict chartkit's resolved
 * kotlinx-datetime down/up and crash the default formatter at runtime
 * (`NoClassDefFoundError: kotlinx.datetime.Instant`). Using the platform calendar
 * via expect/actual keeps chartkit fully decoupled from any datetime library version.
 */
internal class LocalTimeParts(
    val month: Int,
    val dayOfMonth: Int,
    val hour: Int,
    val minute: Int,
)

internal expect fun localTimeParts(epochMillis: Long): LocalTimeParts
