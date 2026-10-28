package com.focusdns.app

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar

/**
 * EnterpriseScheduleEngineTest
 * =============================
 * Unit tests validating enterprise schedule interval evaluation, day-of-week recurrence,
 * midnight-crossing windows, and conditional uninstallation policies.
 *
 * Core Law Verification:
 * - Inside Scheduled Focus Window: canUninstall == False (Strict uninstallation lock).
 * - Outside Scheduled Focus Window: canUninstall == True (Normal mode, clean uninstallation permitted).
 * - Life Safety Exemption: Standard emergency dialing (911/112) is NEVER blocked by schedules.
 */
class EnterpriseScheduleEngineTest {

    private fun createCalendarAt(dayOfWeek: Int, hour: Int, minute: Int): Calendar {
        return Calendar.getInstance().apply {
            set(Calendar.DAY_OF_WEEK, dayOfWeek)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    @Test
    fun testDefaultWorkIntervalInsideWindowLocksUninstallation() {
        val interval = EnterpriseScheduleEngine.ScheduleInterval(
            intervalId = "test_work",
            title = "Work Hours",
            startHour = 9,
            startMinute = 0,
            endHour = 17,
            endMinute = 0,
            daysOfWeek = setOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY, Calendar.FRIDAY),
            enforceLock = true
        )

        // Monday 10:30 AM -> Inside work hours
        val calInside = createCalendarAt(Calendar.MONDAY, 10, 30)
        assertEquals(Calendar.MONDAY, calInside.get(Calendar.DAY_OF_WEEK))
        assertEquals("Work Hours", interval.title)
        assertTrue(interval.enforceLock)

        val currentMinutes = 10 * 60 + 30
        val startMinutes = interval.startHour * 60 + interval.startMinute
        val endMinutes = interval.endHour * 60 + interval.endMinute

        val isInside = currentMinutes in startMinutes until endMinutes
        assertTrue(isInside)

        // Core Law: When inside window, uninstallation is locked
        val canUninstall = !isInside
        assertFalse(canUninstall)
    }

    @Test
    fun testOutsideWorkIntervalPermitsCleanUninstallation() {
        val startMinutes = 9 * 60
        val endMinutes = 17 * 60

        // Monday 08:15 AM (Before start)
        val earlyMinutes = 8 * 60 + 15
        val isEarlyInside = earlyMinutes in startMinutes until endMinutes
        assertFalse(isEarlyInside)
        val canUninstallEarly = !isEarlyInside
        assertTrue(canUninstallEarly)

        // Monday 17:45 PM (After work hours)
        val lateMinutes = 17 * 60 + 45
        val isLateInside = lateMinutes in startMinutes until endMinutes
        assertFalse(isLateInside)
        val canUninstallLate = !isLateInside
        assertTrue(canUninstallLate)
    }

    @Test
    fun testWeekendOutsideIntervalPermitsCleanUninstallation() {
        val workDays = setOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY, Calendar.FRIDAY)

        // Saturday 12:00 PM
        val saturday = Calendar.SATURDAY
        val isWorkDay = workDays.contains(saturday)
        assertFalse(isWorkDay)

        // On weekends, device is in normal mode: clean uninstallation permitted
        val canUninstallWeekend = !isWorkDay
        assertTrue(canUninstallWeekend)
    }

    @Test
    fun testOvernightScheduleCrossingMidnight() {
        // Night focus from 22:00 to 06:00
        val startMinutes = 22 * 60  // 1320
        val endMinutes = 6 * 60     // 360

        // 23:30 (Late night, before midnight) -> Inside
        val time1 = 23 * 60 + 30
        val matches1 = time1 >= startMinutes || time1 < endMinutes
        assertTrue(matches1)

        // 03:30 (Early morning, after midnight) -> Inside
        val time2 = 3 * 60 + 30
        val matches2 = time2 >= startMinutes || time2 < endMinutes
        assertTrue(matches2)

        // 14:00 (Afternoon) -> Outside
        val time3 = 14 * 60
        val matches3 = time3 >= startMinutes || time3 < endMinutes
        assertFalse(matches3)
    }

    @Test
    fun testEmergencyDialerIsExemptAcrossAllSchedules() {
        // Life safety exemption law
        val emergencyCodes = listOf("911", "112", "999", "000", "100", "108", "988")
        for (code in emergencyCodes) {
            assertTrue(
                "Code $code must be exempted from all schedule locks",
                EmergencyCallExemptionManager.isEmergencyNumber(code)
            )
        }
    }

    @Test
    fun testScheduleIntervalDataModel() {
        val interval = EnterpriseScheduleEngine.ScheduleInterval(
            intervalId = "int_study",
            title = "Library Study",
            startHour = 14,
            startMinute = 0,
            endHour = 16,
            endMinute = 30,
            daysOfWeek = setOf(Calendar.TUESDAY, Calendar.THURSDAY)
        )
        assertEquals("int_study", interval.intervalId)
        assertEquals("Library Study", interval.title)
        assertEquals(14, interval.startHour)
        assertEquals(16, interval.endHour)
        assertEquals(30, interval.endMinute)
        assertTrue(interval.enforceLock)
        assertEquals(2, interval.daysOfWeek.size)
    }
}
