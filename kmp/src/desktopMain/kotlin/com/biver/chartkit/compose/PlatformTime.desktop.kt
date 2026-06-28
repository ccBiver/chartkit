package com.biver.chartkit.compose

import java.util.Calendar

internal actual fun localTimeParts(epochMillis: Long): LocalTimeParts {
    val c = Calendar.getInstance()
    c.timeInMillis = epochMillis
    return LocalTimeParts(
        month = c.get(Calendar.MONTH) + 1,
        dayOfMonth = c.get(Calendar.DAY_OF_MONTH),
        hour = c.get(Calendar.HOUR_OF_DAY),
        minute = c.get(Calendar.MINUTE),
    )
}
