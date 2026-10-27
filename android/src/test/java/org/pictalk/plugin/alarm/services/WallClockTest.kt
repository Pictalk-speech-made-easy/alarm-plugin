package org.pictalk.plugin.alarm.services

import org.junit.Assert.assertEquals
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class WallClockTest {
    private val paris = TimeZone.getTimeZone("Europe/Paris")
    private val newYork = TimeZone.getTimeZone("America/New_York")
    private val tokyo = TimeZone.getTimeZone("Asia/Tokyo")

    private fun at(wall: String, zone: TimeZone): Long =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.US).apply { timeZone = zone }.parse(wall)!!.time

    @Test
    fun `an alarm set for 9_00 in Paris rings at 9_00 in New York`() {
        assertEquals(at("2026-10-28T09:00", newYork), WallClock.shift(at("2026-10-28T09:00", paris), paris, newYork))
    }

    @Test
    fun `an alarm set for 9_00 in Paris rings at 9_00 in Tokyo`() {
        assertEquals(at("2026-10-28T09:00", tokyo), WallClock.shift(at("2026-10-28T09:00", paris), paris, tokyo))
    }

    // Paris has left summer time on 25/10, New York only does on 1/11: the offset between them changes in between.
    @Test
    fun `keeps the wall clock on both sides of New York's DST change`() {
        assertEquals(at("2026-10-31T08:50", newYork), WallClock.shift(at("2026-10-31T08:50", paris), paris, newYork))
        assertEquals(at("2026-11-02T08:50", newYork), WallClock.shift(at("2026-11-02T08:50", paris), paris, newYork))
    }

    @Test
    fun `a time in the spring-forward gap rolls to the hour after`() {
        // 14/3/2027 02:30 does not exist in New York.
        assertEquals(at("2027-03-14T03:30", newYork), WallClock.shift(at("2027-03-14T02:30", tokyo), tokyo, newYork))
    }

    @Test
    fun `the same zone changes nothing`() {
        val instant = at("2026-10-28T09:00", paris)
        assertEquals(instant, WallClock.shift(instant, paris, paris))
    }
}
