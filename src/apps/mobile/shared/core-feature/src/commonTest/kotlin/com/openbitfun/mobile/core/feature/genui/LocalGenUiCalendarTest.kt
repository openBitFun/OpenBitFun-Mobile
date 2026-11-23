package com.openbitfun.mobile.core.feature.genui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class LocalGenUiCalendarTest {
    private val app = LocalGenUiApp("local-genui:app", "local-genui:session", "Test", "root = Page([])", 4)
    private val event = """{"title":"Example","startTime":"2040-06-19T09:00:00Z","endTime":"2040-06-19T10:00:00Z","reminderMinutes":[10,30]}"""

    @Test
    fun createReceiptsKeepTheExistingDocumentFormat() {
        val params = """{"event":$event}"""
        val request = assertNotNull(LocalGenUiCalendar.read(message("CreateCalendarEvent", params, ",\"requestId\":\"calendar-1\""), app))
        assertEquals(LocalGenUiCalendarAction.CREATE, request.action)
        assertEquals(params, request.receipt)
        assertEquals(listOf(10, 30), request.event?.reminders)
        assertNull(LocalGenUiCalendar.read(message("CreateCalendarEvent", params), app))
    }

    @Test
    fun revisionsAndCalendarIdsAreValidatedBeforeNativeMutations() {
        val params = """{"event":{"id":42,${event.substring(1)}}"""
        val raw = message("UpdateCalendarEvent", params)
        val update = assertNotNull(LocalGenUiCalendar.read(raw, app))
        assertEquals(42L, update.eventId)
        assertEquals("Example", update.event?.title)
        assertNull(update.receipt)
        assertNull(LocalGenUiCalendar.read(raw, app.copy(sourceRevision = 5)))
        assertNull(LocalGenUiCalendar.read(raw, app.copy(id = "local-genui:foreign")))
        assertNull(LocalGenUiCalendar.read(raw, app.copy(checking = true)))
        assertNull(LocalGenUiCalendar.read(message("DeleteCalendarEvent", """{"id":9007199254740992}"""), app))
        assertEquals(LocalGenUiCalendarAction.DELETE,
            LocalGenUiCalendar.read(message("DeleteCalendarEvent", """{"id":42}"""), app)?.action)
    }

    @Test
    fun listSupportsAnOptionalValidDateRange() {
        val list = assertNotNull(LocalGenUiCalendar.read(message("ListCalendarEvents",
            """{"filter":{"startTime":"2040-06-19","endTime":"2040-06-20"}}"""), app))
        assertEquals(LocalGenUiCalendarAction.LIST, list.action)
        assertEquals(86_400_000L, assertNotNull(list.filterEnd) - assertNotNull(list.filterStart))
        assertNotNull(LocalGenUiCalendar.read(message("ListCalendarEvents", """{"filter":{}}"""), app))
        assertNull(LocalGenUiCalendar.read(message("ListCalendarEvents",
            """{"filter":{"startTime":"2040-06-20","endTime":"2040-06-19"}}"""), app))
    }

    private fun message(action: String, params: String, extra: String = "") =
        """{"type":"action","appId":"${app.id}","sourceRevision":4,"action":"$action","params":$params$extra}"""
}
