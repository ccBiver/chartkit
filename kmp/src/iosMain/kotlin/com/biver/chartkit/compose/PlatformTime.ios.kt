package com.biver.chartkit.compose

import platform.Foundation.NSCalendar
import platform.Foundation.NSCalendarUnitDay
import platform.Foundation.NSCalendarUnitHour
import platform.Foundation.NSCalendarUnitMinute
import platform.Foundation.NSCalendarUnitMonth
import platform.Foundation.NSDate

// Seconds between the Unix epoch (1970-01-01) and NSDate's reference date (2001-01-01).
private const val UNIX_TO_NSDATE_REFERENCE = 978_307_200.0

internal actual fun localTimeParts(epochMillis: Long): LocalTimeParts {
    val date = NSDate(timeIntervalSinceReferenceDate = epochMillis / 1000.0 - UNIX_TO_NSDATE_REFERENCE)
    val cal = NSCalendar.currentCalendar
    val units = NSCalendarUnitMonth or NSCalendarUnitDay or NSCalendarUnitHour or NSCalendarUnitMinute
    val c = cal.components(units, fromDate = date)
    return LocalTimeParts(
        month = c.month.toInt(),
        dayOfMonth = c.day.toInt(),
        hour = c.hour.toInt(),
        minute = c.minute.toInt(),
    )
}
