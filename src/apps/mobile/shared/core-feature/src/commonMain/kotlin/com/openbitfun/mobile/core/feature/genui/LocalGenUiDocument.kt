package com.openbitfun.mobile.core.feature.genui

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import kotlin.math.abs
import kotlin.math.ceil

/** Messages shared with the existing bundled OpenUI document. No native APIs live here. */
public object LocalGenUiDocument {
    public fun mount(manifestJson: String, app: LocalGenUiApp, scheme: String, locale: String, look: String, imageSearchAvailable: Boolean): String {
        val manifest = checkNotNull(LocalGenUiStore.jsonObject(manifestJson))
        return buildJsonObject {
            put("type", "init")
            put("manifest", manifest)
            put("identity", buildJsonObject {
                put("appId", app.id)
                put("title", app.title)
                for (field in listOf("template", "libraryId", "libraryRevision", "designSpec")) {
                    put(field, manifest.getValue(field))
                }
                put("sourceFormat", "openui-lang")
            })
            put("mode", if (app.checking && !app.reopening) "checker" else "live")
            put("source", app.source)
            app.baseSource?.let { put("base", it) }
            put("sourceRevision", app.sourceRevision)
            put("stateRevision", app.stateRevision)
            put("state", LocalGenUiStore.jsonObject(app.stateJson) ?: JsonObject(emptyMap()))
            put("streaming", app.streaming)
            put("scheme", scheme)
            put("locale", locale)
            put("look", look)
            put("imageSearchAvailable", imageSearchAvailable && !app.checking)
        }.toString()
    }

    public fun updateSource(app: LocalGenUiApp): String = buildJsonObject {
        put("type", "source_reset")
        put("appId", app.id)
        put("sourceRevision", app.sourceRevision)
        put("text", app.source)
        put("streaming", app.streaming)
    }.toString()

    public fun state(app: LocalGenUiApp, conflict: Boolean): String = buildJsonObject {
        put("type", "state")
        put("appId", app.id)
        put("sourceRevision", app.sourceRevision)
        put("stateRevision", app.stateRevision)
        put("state", LocalGenUiStore.jsonObject(app.stateJson) ?: JsonObject(emptyMap()))
        put("conflict", conflict)
    }.toString()

    public fun theme(scheme: String, look: String): String = buildJsonObject {
        put("type", "theme")
        put("scheme", scheme)
        put("look", look)
    }.toString()

    public fun insets(top: Int, left: Int, right: Int, bottom: Int): String = buildJsonObject {
        put("type", "insets")
        put("top", top)
        put("left", left)
        put("right", right)
        put("bottom", bottom)
    }.toString()

    public fun probe(app: LocalGenUiApp): String = buildJsonObject {
        put("type", "probe")
        put("requestId", probeId(app))
    }.toString()

    public fun merge(app: LocalGenUiApp): String? = app.baseSource?.let { base ->
        buildJsonObject {
            put("type", "merge")
            put("requestId", mergeId(app))
            put("base", base)
            put("patch", app.source)
        }.toString()
    }

    private fun mergeId(app: LocalGenUiApp): String = "merge:${app.id}:${app.sourceRevision}"

    private fun mergeResult(message: JsonObject, app: LocalGenUiApp): LocalGenUiIntent? {
        if ((message["requestId"] as? JsonPrimitive)?.contentOrNull != mergeId(app)) return null
        val source = (message["source"] as? JsonPrimitive)?.contentOrNull
            ?.takeIf { it.length <= LocalGenUiStore.MAX_JSON && Regex("""(?m)^root\s*=""").containsMatchIn(it) }
        return LocalGenUiIntent.MergeApp(app.id, app.sourceRevision, source)
    }

    private fun probeId(app: LocalGenUiApp): String =
        "${if (app.reopening) "reopen" else "validate"}:${app.id}:${app.sourceRevision}"

    internal fun unavailableProbe(app: LocalGenUiApp): LocalGenUiIntent.VerifyApp {
        val detail = "runtime probe did not report"
        val checks = if (app.reopening) {
            listOf(unverified("save-reopen", "owner readback; reopen $detail"))
        } else {
            listOf(
                unverified("actual-render", detail),
                unverified("declared-interactions", "not executable by the local render probe"),
                unverified("fixed-viewport", detail),
                check("host-shell", true, "native shell"),
                unverified("host-shell-duplication", detail),
                unverified("content-boundary", detail),
                unverified("no-horizontal-overflow", detail),
            )
        }
        return LocalGenUiIntent.VerifyApp(app.id, app.sourceRevision, app.reopening, checks, emptyMap())
    }

    private fun probeResult(message: JsonObject, app: LocalGenUiApp, catalog: String): LocalGenUiIntent? {
        val report = message["report"] as? JsonObject ?: return null
        if (report.string("requestId") != probeId(app) || report.string("appId") != app.id ||
            (report["sourceRevision"] as? JsonPrimitive)?.intOrNull != app.sourceRevision
        ) return null
        val errors = report["renderErrors"] as? JsonArray ?: return null
        val contractOk = (report["contractOk"] as? JsonPrimitive)?.booleanOrNull ?: return null
        val visible = (report["visibleElements"] as? JsonPrimitive)?.intOrNull ?: return null
        val render = when {
            !contractOk -> check("actual-render", false, "runtime contract mismatch")
            errors.isNotEmpty() -> check("actual-render", false, errors.take(3).joinToString("; ") {
                (it as? JsonPrimitive)?.contentOrNull.orEmpty().take(300)
            })
            else -> check("actual-render", visible > 0, "$visible visible elements")
        }
        if (app.reopening) {
            return LocalGenUiIntent.VerifyApp(app.id, app.sourceRevision, true,
                listOf(render.copy(name = "save-reopen", detail = "owner readback; reopen ${render.detail}")), emptyMap())
        }
        if (!contractOk) return LocalGenUiIntent.VerifyApp(app.id, app.sourceRevision, false, listOf(render), emptyMap())

        val viewportWidth = (report["viewport"] as? JsonObject)?.number("width")?.takeIf { it > 0 } ?: return null
        val scrollWidth = report.number("scrollWidth") ?: return null
        val canvasWidth = report.number("canvasWidth") ?: return null
        val canvasScale = report.number("canvasScale") ?: return null
        val content = report["contentBounds"] as? JsonObject ?: return null
        val left = content.number("left") ?: return null
        val right = content.number("right") ?: return null
        val hostParts = (report["hostPartsInDocument"] as? JsonPrimitive)?.intOrNull ?: return null
        val specification = LocalGenUiStore.jsonObject(catalog)?.get("designSpec") as? JsonObject
        val shell = specification?.get("shell") as? JsonObject
        val insets = shell?.get("contentInsets") as? JsonObject
        val gutterStart = insets?.number("left")
        val gutterEnd = insets?.number("right")?.let { canvasWidth - it }
        val boundary = if (gutterStart != null && gutterEnd != null) {
            val widest = report.string("widestElement").orEmpty().take(160)
            check("content-boundary", visible > 0 && left >= gutterStart - 1 && right <= gutterEnd + 1,
                "content $left..$right, allowed $gutterStart..$gutterEnd, widest $widest")
        } else unverified("content-boundary", "design specification insets are missing")
        val checks = listOf(
            render,
            unverified("declared-interactions", "not executable by the local render probe"),
            check("fixed-viewport", abs(canvasWidth - viewportWidth) <= 1 && canvasScale == 1.0,
                "canvas ${canvasWidth}px x $canvasScale in viewport ${viewportWidth}px"),
            check("host-shell", true, "native shell"),
            check("host-shell-duplication", hostParts == 0, "$hostParts emulated host parts in document"),
            boundary,
            check("no-horizontal-overflow", scrollWidth <= ceil(viewportWidth) + 1,
                "document ${scrollWidth}px, viewport ${viewportWidth}px"),
        )
        val types = (report["stateTypes"] as? JsonObject).orEmpty().mapNotNull { (key, value) ->
            (value as? JsonPrimitive)?.contentOrNull?.let { key to it }
        }.toMap()
        return LocalGenUiIntent.VerifyApp(app.id, app.sourceRevision, false, checks, types)
    }

    private fun check(name: String, passed: Boolean, detail: String) =
        LocalGenUiCheck(name, if (passed) LocalGenUiCheckResult.PASSED else LocalGenUiCheckResult.FAILED, detail)

    private fun unverified(name: String, detail: String) = LocalGenUiCheck(name, LocalGenUiCheckResult.UNVERIFIED, detail)

    private fun JsonObject.string(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.number(key: String) = (get(key) as? JsonPrimitive)?.doubleOrNull?.takeIf(Double::isFinite)

    public fun readIntent(raw: String, mounted: LocalGenUiApp, catalog: String): LocalGenUiIntent? {
        if (raw.length > LocalGenUiStore.MAX_JSON || mounted.streaming) return null
        val message = LocalGenUiStore.jsonObject(raw) ?: return null
        val type = (message["type"] as? JsonPrimitive)?.contentOrNull
        if (mounted.checking) return when (type) {
            "probe_result" -> probeResult(message, mounted, catalog)
            "merge_result" -> mergeResult(message, mounted)
            else -> null
        }
        val app = (message["appId"] as? JsonPrimitive)?.contentOrNull
        val revision = (message["sourceRevision"] as? JsonPrimitive)?.intOrNull
        if (app != mounted.id || revision != mounted.sourceRevision) return null
        return when (type) {
            "state" -> {
                val base = (message["baseStateRevision"] as? JsonPrimitive)?.intOrNull ?: return null
                val state = message["state"] as? JsonObject ?: return null
                LocalGenUiIntent.SaveAppState(mounted.id, mounted.sourceRevision, base, state.toString())
            }
            "action" -> {
                if ((message["action"] as? JsonPrimitive)?.contentOrNull != "continue_conversation") return null
                val prompt = (message["message"] as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
                if (prompt.isEmpty() || prompt.length > 2000) return null
                LocalGenUiIntent.ContinueConversation(mounted.id, mounted.sourceRevision, prompt)
            }
            else -> null
        }
    }
}
