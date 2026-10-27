package org.pictalk.plugin.alarm.services

import java.util.Calendar
import java.util.TimeZone

object WallClock {
    /** The instant showing, in [to], the wall clock [instant] showed in [from]: an alarm set for 9:00 rings at 9:00 wherever the phone is. */
    fun shift(instant: Long, from: TimeZone, to: TimeZone): Long {
        val wall = Calendar.getInstance(from).apply { timeInMillis = instant }
        // Lenient by default: a time in the spring-forward gap rolls to the hour after, as the app does.
        return Calendar.getInstance(to).apply {
            clear()
            set(wall.get(Calendar.YEAR), wall.get(Calendar.MONTH), wall.get(Calendar.DAY_OF_MONTH), wall.get(Calendar.HOUR_OF_DAY), wall.get(Calendar.MINUTE), wall.get(Calendar.SECOND))
            set(Calendar.MILLISECOND, wall.get(Calendar.MILLISECOND))
        }.timeInMillis
    }
}
