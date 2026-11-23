package com.openbitfun.mobile.core.feature.genui

import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toInstant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import kotlin.time.Instant

public enum class LocalGenUiCalendarAction(internal val wireName: String) {
    CREATE("CreateCalendarEvent"),
    UPDATE("UpdateCalendarEvent"),
    DELETE("DeleteCalendarEvent"),
    LIST("ListCalendarEvents"),
}

@ConsistentCopyVisibility
public data class LocalGenUiCalendarEvent internal constructor(
    public val title: String,
    public val startMillis: Long,
    public val endMillis: Long,
    public val eventDescription: String,
    public val location: String,
    public val reminders: List<Int>,
    public val repeatFrequency: String?,
    public val repeatInterval: Int,
    public val repeatCount: Int?,
    public val repeatUntil: Long?,
)

@ConsistentCopyVisibility
public data class LocalGenUiCalendarRequest internal constructor(
    public val action: LocalGenUiCalendarAction,
    public val event: LocalGenUiCalendarEvent? = null,
    public val eventId: Long? = null,
    public val filterStart: Long? = null,
    public val filterEnd: Long? = null,
    public val receipt: String? = null,
)

/** Only native app-owned calendars can receive these validated document actions. */
public object LocalGenUiCalendar {
    public fun read(raw: String, app: LocalGenUiApp): LocalGenUiCalendarRequest? {
        if (raw.length > 16_000 || app.streaming || app.checking) return null
        val body = LocalGenUiStore.jsonObject(raw) ?: return null
        if (body.string("type") != "action" || body.string("appId") != app.id ||
            (body["sourceRevision"] as? JsonPrimitive)?.intOrNull != app.sourceRevision
        ) return null
        val action = LocalGenUiCalendarAction.entries.firstOrNull { it.wireName == body.string("action") } ?: return null
        val params = body["params"] as? JsonObject ?: return null
        return when (action) {
            LocalGenUiCalendarAction.CREATE -> {
                val requestId = body.string("requestId")
                if (requestId.isNullOrBlank() || requestId.length > 64) return null
                val event = readEvent(params.fields("event")) ?: return null
                LocalGenUiCalendarRequest(action, event = event, receipt = params.toString())
            }
            LocalGenUiCalendarAction.UPDATE -> {
                val fields = params.fields("event")
                val id = fields.eventId() ?: return null
                val event = readEvent(fields) ?: return null
                LocalGenUiCalendarRequest(action, event = event, eventId = id)
            }
            LocalGenUiCalendarAction.DELETE -> {
                val id = params.eventId() ?: return null
                LocalGenUiCalendarRequest(action, eventId = id)
            }
            LocalGenUiCalendarAction.LIST -> {
                val fields = params.fields("filter")
                val start = epoch(fields["startTime"])
                val end = epoch(fields["endTime"])
                if (fields.hasValue("startTime") && start == null || fields.hasValue("endTime") && end == null ||
                    start != null && end != null && end <= start
                ) return null
                LocalGenUiCalendarRequest(action, filterStart = start, filterEnd = end)
            }
        }
    }

    public fun isCalendarAction(name: String): Boolean = LocalGenUiCalendarAction.entries.any { it.wireName == name }

    private fun readEvent(event: JsonObject): LocalGenUiCalendarEvent? {
        val title = event.string("title")?.trim()?.takeIf { it.isNotBlank() && it.length <= 256 } ?: return null
        val starts = epoch(event["startTime"]) ?: return null
        val ends = epoch(event["endTime"])?.takeIf { it > starts } ?: return null
        val description = event.string("description").orEmpty().trim()
        val location = event.string("location").orEmpty().trim()
        if (description.length > 4000 || location.length > 4000) return null
        val reminderValues = when (val value = event["reminderMinutes"]) {
            is JsonArray -> value
            null, JsonNull -> emptyList()
            is JsonPrimitive -> if (value.content.isBlank()) emptyList() else listOf(value)
            else -> return null
        }
        if (reminderValues.size > 5) return null
        val reminders = reminderValues.map {
            (it as? JsonPrimitive)?.intOrNull?.takeIf { minutes -> minutes in 0..10080 } ?: return null
        }
        val recurrence = event["recurrence"] as? JsonObject
        val frequency = recurrence?.string("frequency")?.lowercase()
        if (recurrence != null && frequency !in setOf("daily", "weekly", "monthly", "yearly")) return null
        val interval = recurrence?.positiveInt("interval") ?: 1
        val count = recurrence?.positiveInt("count")
        val until = epoch(recurrence?.get("expire"))
        if (recurrence?.hasValue("interval") == true && recurrence.positiveInt("interval") == null ||
            recurrence?.hasValue("count") == true && count == null ||
            recurrence?.hasValue("expire") == true && (until == null || until < starts)
        ) return null
        return LocalGenUiCalendarEvent(title, starts, ends, description, location, reminders, frequency, interval, count, until)
    }

    public fun result(app: LocalGenUiApp, requestId: String, succeeded: Boolean): String = buildJsonObject {
        put("type", "calendar_result")
        put("appId", app.id)
        put("sourceRevision", app.sourceRevision)
        put("requestId", requestId)
        put("ok", succeeded)
    }.toString()

    public fun receipts(app: LocalGenUiApp): String = buildJsonObject {
        put("type", "calendar_receipts")
        put("appId", app.id)
        put("sourceRevision", app.sourceRevision)
        put("params", JsonArray(app.calendarReceipts.mapNotNull { LocalGenUiStore.jsonObject(it) }))
    }.toString()

    private fun JsonObject.fields(key: String): JsonObject = get(key) as? JsonObject ?: this
    private fun JsonObject.string(key: String): String? = (get(key) as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.hasValue(key: String): Boolean = get(key)?.let { it != JsonNull } ?: false
    private fun JsonObject.eventId(): Long? =
        (get("id") as? JsonPrimitive)?.longOrNull?.takeIf { it in 1..9_007_199_254_740_991 }
    private fun JsonObject.positiveInt(key: String): Int? =
        (get(key) as? JsonPrimitive)?.intOrNull?.takeIf { it > 0 }

    private fun epoch(element: JsonElement?): Long? {
        val primitive = element as? JsonPrimitive ?: return null
        val value = primitive.contentOrNull ?: return null
        return (primitive.longOrNull ?: runCatching { Instant.parse(value).toEpochMilliseconds() }.getOrNull()
            ?: runCatching { LocalDate.parse(value).atStartOfDayIn(TimeZone.UTC).toEpochMilliseconds() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(value).toInstant(TimeZone.currentSystemDefault()).toEpochMilliseconds() }.getOrNull())
            ?.takeIf { it in 1..253_402_300_799_999 }
    }
}
