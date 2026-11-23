package com.openbitfun.mobile.app.ui.genui

import android.Manifest
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import android.provider.CalendarContract.Reminders
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendarAction
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendarEvent
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendarRequest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal fun interface LocalGenUiCalendarRunner {
    fun run(request: LocalGenUiCalendarRequest, isCurrent: () -> Boolean, reply: (Long?) -> Unit)
}

private data class PendingCalendarRequest(
    val request: LocalGenUiCalendarRequest,
    val isCurrent: () -> Boolean,
    val reply: (Long?) -> Unit,
)

@Composable
internal fun rememberLocalGenUiCalendarRunner(scope: CoroutineScope): LocalGenUiCalendarRunner {
    val context = LocalContext.current
    var pending by remember { mutableStateOf<PendingCalendarRequest?>(null) }
    val permissions = remember { arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR) }

    fun run(action: PendingCalendarRequest) {
        if (!action.isCurrent()) {
            action.reply(null)
            return
        }
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { LocalGenUiAndroidCalendar.execute(context, action.request) }.getOrNull()
            }
            action.reply(result)
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val action = pending
        pending = null
        if (action != null) {
            if (permissions.all { result[it] == true }) run(action)
            else action.reply(null)
        }
    }
    return LocalGenUiCalendarRunner { request, isCurrent, reply ->
        val action = PendingCalendarRequest(request, isCurrent, reply)
        if (pending != null) reply(null)
        else if (permissions.all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }) {
            run(action)
        } else {
            pending = action
            permission.launch(permissions)
        }
    }
}

internal object LocalGenUiAndroidCalendar {
    @Synchronized
    fun execute(context: Context, request: LocalGenUiCalendarRequest): Long? {
        val calendar = localCalendar(context) ?: return null
        val resolver = context.contentResolver
        return when (request.action) {
            LocalGenUiCalendarAction.CREATE -> {
                val event = request.event ?: return null
                val insert = ContentProviderOperation.newInsert(Events.CONTENT_URI)
                    .withValues(eventValues(calendar, event))
                    .build()
                val operations = arrayListOf(insert)
                event.reminders.forEach { minutes ->
                    operations += ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValueBackReference(Reminders.EVENT_ID, 0)
                        .withValue(Reminders.MINUTES, minutes)
                        .withValue(Reminders.METHOD, Reminders.METHOD_ALERT)
                        .build()
                }
                resolver.applyBatch(CalendarContract.AUTHORITY, operations).firstOrNull()?.uri?.let(ContentUris::parseId)
            }
            LocalGenUiCalendarAction.UPDATE -> {
                val id = request.eventId ?: return null
                val event = request.event ?: return null
                val update = ContentProviderOperation.newUpdate(Events.CONTENT_URI)
                    .withSelection(ownedEvent, ownedEventArgs(id, calendar))
                    .withValues(eventValues(calendar, event))
                    .withExpectedCount(1)
                    .build()
                val clearReminders = ContentProviderOperation.newDelete(Reminders.CONTENT_URI)
                    .withSelection("${Reminders.EVENT_ID}=?", arrayOf(id.toString()))
                    .build()
                val operations = arrayListOf(update, clearReminders)
                event.reminders.forEach { minutes ->
                    operations += ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValue(Reminders.EVENT_ID, id)
                        .withValue(Reminders.MINUTES, minutes)
                        .withValue(Reminders.METHOD, Reminders.METHOD_ALERT)
                        .build()
                }
                if (resolver.applyBatch(CalendarContract.AUTHORITY, operations).firstOrNull()?.count == 1) id else null
            }
            LocalGenUiCalendarAction.DELETE -> {
                val id = request.eventId ?: return null
                if (resolver.delete(Events.CONTENT_URI, ownedEvent, ownedEventArgs(id, calendar)) == 1) id else null
            }
            LocalGenUiCalendarAction.LIST -> count(context, calendar, request.filterStart, request.filterEnd)
        }
    }

    private val ownedEvent = "${Events._ID}=? AND ${Events.CALENDAR_ID}=? AND ${Events.DELETED}=0"
    private fun ownedEventArgs(id: Long, calendar: Long) = arrayOf(id.toString(), calendar.toString())

    private fun count(context: Context, calendar: Long, start: Long?, end: Long?): Long? {
        val resolver = context.contentResolver
        val args = arrayOf(calendar.toString())
        if (start == null || end == null) {
            return resolver.query(Events.CONTENT_URI, arrayOf(Events._ID),
                "${Events.CALENDAR_ID}=? AND ${Events.DELETED}=0", args, null)?.use { it.count.toLong() }
        }
        val builder = Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)
        return resolver.query(builder.build(), arrayOf(Instances.EVENT_ID),
            "${Instances.CALENDAR_ID}=? AND ${Instances.END}>? AND ${Instances.BEGIN}<?",
            arrayOf(calendar.toString(), start.toString(), end.toString()), null)?.use { cursor ->
            val events = mutableSetOf<Long>()
            while (cursor.moveToNext()) events.add(cursor.getLong(0))
            events.size.toLong()
        }
    }

    private fun eventValues(calendar: Long, request: LocalGenUiCalendarEvent) = ContentValues().apply {
        put(Events.CALENDAR_ID, calendar)
        put(Events.TITLE, request.title)
        put(Events.DTSTART, request.startMillis)
        put(Events.EVENT_TIMEZONE, "UTC")
        put(Events.DESCRIPTION, request.eventDescription)
        put(Events.EVENT_LOCATION, request.location)
        put(Events.HAS_ALARM, if (request.reminders.isEmpty()) 0 else 1)
        val frequency = request.repeatFrequency
        if (frequency == null) {
            put(Events.DTEND, request.endMillis)
            putNull(Events.DURATION)
            putNull(Events.RRULE)
        } else {
            val seconds = ((request.endMillis - request.startMillis) / 1000).coerceAtLeast(1)
            val rule = buildString {
                append("FREQ=").append(frequency.uppercase(Locale.ROOT))
                append(";INTERVAL=").append(request.repeatInterval)
                val count = request.repeatCount
                if (count != null) append(";COUNT=").append(count)
                else request.repeatUntil?.let { append(";UNTIL=").append(recurrenceEnd.format(Instant.ofEpochMilli(it))) }
            }
            putNull(Events.DTEND)
            put(Events.DURATION, "PT${seconds}S")
            put(Events.RRULE, rule)
        }
    }

    private fun localCalendar(context: Context): Long? {
        val resolver = context.contentResolver
        val account = context.packageName
        val type = CalendarContract.ACCOUNT_TYPE_LOCAL
        resolver.query(
            Calendars.CONTENT_URI, arrayOf(Calendars._ID),
            "${Calendars.ACCOUNT_NAME}=? AND ${Calendars.ACCOUNT_TYPE}=? AND ${Calendars.NAME}=?",
            arrayOf(account, type, "OpenBitFun"), null,
        )?.use { if (it.moveToFirst()) return it.getLong(0) }

        val uri = Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(Calendars.ACCOUNT_NAME, account)
            .appendQueryParameter(Calendars.ACCOUNT_TYPE, type)
            .build()
        val calendar = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, account)
            put(Calendars.ACCOUNT_TYPE, type)
            put(Calendars.NAME, "OpenBitFun")
            put(Calendars.CALENDAR_DISPLAY_NAME, "OpenBitFun")
            put(Calendars.OWNER_ACCOUNT, account)
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.CALENDAR_TIME_ZONE, "UTC")
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
            put(Calendars.MAX_REMINDERS, 5)
        }
        return resolver.insert(uri, calendar)?.let(ContentUris::parseId)
    }

    private val recurrenceEnd = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'", Locale.ROOT).withZone(ZoneOffset.UTC)
}
