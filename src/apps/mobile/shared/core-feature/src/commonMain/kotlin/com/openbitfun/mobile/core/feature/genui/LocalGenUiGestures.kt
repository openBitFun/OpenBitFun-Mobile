package com.openbitfun.mobile.core.feature.genui

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.hypot

public enum class LocalGenUiPoseJoint {
    NOSE, LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_WRIST, RIGHT_WRIST, LEFT_HIP, RIGHT_HIP,
}

public data class LocalGenUiPosePoint(
    public val joint: LocalGenUiPoseJoint,
    public val x: Double,
    public val y: Double,
    public val confidence: Double,
)

public enum class LocalGenUiCameraStatus(internal val wire: String) {
    STARTING("starting"), ACTIVE("active"), PAUSED("paused"), DENIED("denied"),
    UNAVAILABLE("unavailable"), FAILED("failed"),
}

private enum class Gesture(val wire: String) {
    LEFT("raise_left_hand"), RIGHT("raise_right_hand"), BOTH("raise_both_hands"),
}

/** Accepts anatomically labeled joints from the native detector, in pixel coordinates. */
private class GestureClassifier {
    private data class Point(val x: Double, val y: Double) {
        operator fun minus(other: Point) = Point(x - other.x, y - other.y)
        fun midpoint(other: Point) = Point((x + other.x) / 2, (y + other.y) / 2)
        fun length() = hypot(x, y)
        fun dot(other: Point) = x * other.x + y * other.y
    }

    private var pending: Gesture? = null
    private var armed = true

    fun accept(points: List<LocalGenUiPosePoint>): Gesture? {
        val (left, right) = measure(points) ?: run {
            reset()
            return null
        }
        if (left < 0.1 && right < 0.1) armed = true
        val gesture = when {
            left > 0.35 && right > 0.35 -> Gesture.BOTH
            left > 0.35 -> Gesture.LEFT
            right > 0.35 -> Gesture.RIGHT
            else -> null
        }
        val stable = gesture != null && pending == gesture
        pending = gesture
        if (!stable || !armed) return null
        armed = false
        return gesture
    }

    fun reset() {
        pending = null
        armed = true
    }

    private fun measure(points: List<LocalGenUiPosePoint>): Pair<Double, Double>? {
        fun at(joint: LocalGenUiPoseJoint) = points.firstOrNull {
            it.joint == joint && it.confidence >= 0.3 && it.x.isFinite() && it.y.isFinite()
        }?.let { Point(it.x, it.y) }

        val left = at(LocalGenUiPoseJoint.LEFT_SHOULDER) ?: return null
        val right = at(LocalGenUiPoseJoint.RIGHT_SHOULDER) ?: return null
        val width = (left - right).length()
        if (width <= 0) return null
        val shoulders = left.midpoint(right)
        val leftHip = at(LocalGenUiPoseJoint.LEFT_HIP)
        val rightHip = at(LocalGenUiPoseJoint.RIGHT_HIP)
        val up = if (leftHip != null && rightHip != null) shoulders - leftHip.midpoint(rightHip)
        else (at(LocalGenUiPoseJoint.NOSE) ?: return null) - shoulders
        val scale = up.length() * width
        if (scale <= 0 || !scale.isFinite()) return null

        fun lift(joint: LocalGenUiPoseJoint, shoulder: Point) =
            at(joint)?.let { (it - shoulder).dot(up) / scale } ?: -1.0
        return lift(LocalGenUiPoseJoint.LEFT_WRIST, left) to lift(LocalGenUiPoseJoint.RIGHT_WRIST, right)
    }
}

/** Device-capability session for one live document. Call from the native UI thread. */
public class LocalGenUiGestures {
    private val subscriptions = linkedMapOf<String, Gesture>()
    private val classifier = GestureClassifier()
    private var appId: String? = null
    private var revision = 0
    private var visible = false
    private var status = LocalGenUiCameraStatus.STARTING

    public val hasSubscriptions: Boolean get() = subscriptions.isNotEmpty()
    public val cameraWanted: Boolean get() = visible && hasSubscriptions

    public fun mount(app: LocalGenUiApp?) {
        val live = app?.takeUnless { it.checking || it.streaming }
        appId = live?.id
        revision = live?.sourceRevision ?: 0
        subscriptions.clear()
        resetCamera()
    }

    public fun setVisible(value: Boolean): List<String> {
        if (visible == value) return emptyList()
        visible = value
        resetCamera()
        val next = if (visible) status else LocalGenUiCameraStatus.PAUSED
        return subscriptions.keys.map { status(it, next) }
    }

    public fun receive(raw: String): List<String> {
        if (appId == null) return emptyList()
        val message = LocalGenUiStore.jsonObject(raw) ?: return emptyList()
        fun string(key: String) = (message[key] as? JsonPrimitive)
            ?.takeIf { it.isString }?.content
        val id = string("subscriptionId")?.takeIf { it.isNotBlank() && it.length <= 64 } ?: return emptyList()
        if (string("type") != "capability" || string("capability") != "gesture" || string("appId") != appId ||
            (message["sourceRevision"] as? JsonPrimitive)?.intOrNull != revision
        ) return emptyList()
        return when (string("op")) {
            "subscribe" -> {
                val gesture = Gesture.entries.find { it.wire == string("gesture") }
                if (gesture == null || (id !in subscriptions && subscriptions.size >= 4)) {
                    listOf(status(id, LocalGenUiCameraStatus.UNAVAILABLE))
                } else {
                    subscriptions[id] = gesture
                    listOf(status(id, if (visible) status else LocalGenUiCameraStatus.PAUSED))
                }
            }
            "unsubscribe" -> {
                if (subscriptions.remove(id) != null && subscriptions.isEmpty()) resetCamera()
                emptyList()
            }
            else -> emptyList()
        }
    }

    public fun cameraStatus(value: LocalGenUiCameraStatus): List<String> {
        if (!cameraWanted || status == value || value == LocalGenUiCameraStatus.PAUSED) return emptyList()
        status = value
        if (value != LocalGenUiCameraStatus.ACTIVE) classifier.reset()
        return subscriptions.keys.map { status(it, value) }
    }

    public fun frame(points: List<LocalGenUiPosePoint>): List<String> {
        if (!cameraWanted || status != LocalGenUiCameraStatus.ACTIVE) return emptyList()
        val gesture = classifier.accept(points) ?: return emptyList()
        return subscriptions.filterValues { it == gesture }.keys.map { id ->
            buildJsonObject {
                put("type", "capability_event")
                put("subscriptionId", id)
                put("gesture", gesture.wire)
            }.toString()
        }
    }

    private fun resetCamera() {
        classifier.reset()
        status = LocalGenUiCameraStatus.STARTING
    }

    private fun status(id: String, value: LocalGenUiCameraStatus) = buildJsonObject {
        put("type", "capability_status")
        put("subscriptionId", id)
        put("status", value.wire)
    }.toString()
}
