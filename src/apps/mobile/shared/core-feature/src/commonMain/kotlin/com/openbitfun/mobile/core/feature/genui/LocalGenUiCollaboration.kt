package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.transport.GenUiImageTransfer
import com.openbitfun.mobile.core.transport.GenUiNearbyImageTransfer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put

public enum class LocalGenUiImageKind(internal val wire: String) {
    PHOTO("photo"), SCAN("scan"), GALLERY("gallery"),
}

public enum class LocalGenUiCollaborationResult(internal val wire: String) {
    PENDING("pending"), COMPLETED("completed"), CANCELLED("cancelled"), UNAVAILABLE("unavailable"), FAILED("failed"),
}

public class LocalGenUiCollaborationRequest internal constructor(
    internal val appId: String,
    internal val sourceRevision: Int,
    public val id: String,
    public val kind: LocalGenUiImageKind?,
)

public class LocalGenUiImageInvite internal constructor(
    public val kind: LocalGenUiImageKind,
    internal val host: String,
    internal val port: Int,
    internal val key: ByteArray,
)

public class LocalGenUiNearbyApproval internal constructor(
    public val code: String,
    public val kind: LocalGenUiImageKind,
) {
    private val decision = CompletableDeferred<Boolean>()
    public fun decide(approve: Boolean) { decision.complete(approve) }
    internal suspend fun awaitDecision(): Boolean = decision.await()
}

public class LocalGenUiNearbyUpload internal constructor(public val kind: LocalGenUiImageKind) {
    private val image = CompletableDeferred<ByteArray?>()
    private val receipt = CompletableDeferred<Boolean>()

    public suspend fun submit(bytes: ByteArray): Boolean =
        GenUiImageTransfer.isJpeg(bytes) && image.complete(bytes) && receipt.await()

    public fun cancel() { image.complete(null) }
    internal suspend fun awaitImage(): ByteArray? = image.await()
    internal fun finish(delivered: Boolean) { receipt.complete(delivered) }
}

public object LocalGenUiCollaboration {
    private const val SCHEME = "openbitfun-image-v1:"
    private val REQUEST_ID = Regex("[a-zA-Z0-9_-]{1,64}")
    public const val MAX_IMAGE_BYTES: Int = GenUiImageTransfer.MAX_IMAGE_BYTES
    public const val NEARBY_SERVICE_TYPE: String = "_obf-img-v2._tcp"

    public fun availability(app: LocalGenUiApp, enabled: Boolean): String = buildJsonObject {
        put("type", "collaboration_availability")
        put("appId", app.id)
        put("sourceRevision", app.sourceRevision)
        put("available", enabled)
        put("reason", if (enabled) "" else "missingSyscap")
    }.toString()

    public fun request(raw: String, app: LocalGenUiApp): LocalGenUiCollaborationRequest? {
        if (app.streaming || app.checking || raw.length > 2048) return null
        val message = LocalGenUiStore.jsonObject(raw) ?: return null
        fun string(key: String) = (message[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        val revision = (message["sourceRevision"] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
        if (string("type") != "collaboration" || string("appId") != app.id || revision != app.sourceRevision) return null
        val id = string("requestId")?.takeIf(REQUEST_ID::matches) ?: return null
        val kind = when (string("op")) {
            "start" -> LocalGenUiImageKind.entries.firstOrNull { it.wire == string("kind") } ?: return null
            "cancel" -> null
            else -> return null
        }
        return LocalGenUiCollaborationRequest(app.id, app.sourceRevision, id, kind)
    }

    public fun reply(
        request: LocalGenUiCollaborationRequest,
        status: LocalGenUiCollaborationResult,
        reason: String,
        asset: String,
    ): String = buildJsonObject {
        put("type", "collaboration_result")
        put("appId", request.appId)
        put("sourceRevision", request.sourceRevision)
        put("requestId", request.id)
        put("status", status.wire)
        put("reason", reason)
        put("asset", asset)
    }.toString()

    public fun localAddress(address: String): Boolean {
        val fields = address.split('.', limit = 5)
        if (fields.size != 4) return false
        val octets = fields.map { field ->
            field.toIntOrNull()?.takeIf { it in 0..255 && it.toString() == field } ?: return false
        }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1] in 16..31) || (octets[0] == 169 && octets[1] == 254)
    }

    public fun parse(invite: String): LocalGenUiImageInvite? {
        if (invite.length > 160) return null
        val code = invite.trim()
        if (!code.startsWith(SCHEME)) return null
        val fields = code.removePrefix(SCHEME).split(':', limit = 5)
        if (fields.size != 4) return null
        val kind = LocalGenUiImageKind.entries.firstOrNull { it.wire == fields[0] } ?: return null
        val host = fields[1].takeIf(::localAddress) ?: return null
        val port = fields[2].toIntOrNull()?.takeIf { it in 1024..65535 && it.toString() == fields[2] } ?: return null
        val hex = fields[3].takeIf { it.length == 64 && it.all { c -> c in 'a'..'f' || c in '0'..'9' } } ?: return null
        return LocalGenUiImageInvite(kind, host, port, hex.hexToByteArray())
    }

    public suspend fun receive(
        media: LocalGenUiMedia,
        request: LocalGenUiCollaborationRequest,
        address: String,
        onInvite: (String) -> Unit,
    ): String? {
        if (!localAddress(address)) return null
        val kind = request.kind ?: return null
        return receiveAsset(media, request) { save ->
            GenUiImageTransfer.receive(address, opened = { port, key ->
                val code = "$SCHEME${kind.wire}:$address:$port:${key.toHexString()}"
                withContext(Dispatchers.Main) { onInvite(code) }
            }, save = save)
        }
    }

    private suspend fun receiveAsset(
        media: LocalGenUiMedia,
        request: LocalGenUiCollaborationRequest,
        receive: suspend (suspend (ByteArray) -> Boolean) -> Boolean,
    ): String? {
        var asset: String? = null
        var keep = false
        return try {
            keep = receive { bytes ->
                asset = media.userImages.write(request.appId, bytes)
                true
            }
            asset.takeIf { keep }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        } finally {
            if (!keep) asset?.let { discard(media, request, it) }
        }
    }

    public suspend fun discard(media: LocalGenUiMedia, request: LocalGenUiCollaborationRequest, asset: String) {
        withContext(Dispatchers.IO + NonCancellable) {
            runCatching { media.userImages.discard(request.appId, asset) }
        }
    }

    public suspend fun send(invite: LocalGenUiImageInvite, bytes: ByteArray): Boolean =
        GenUiImageTransfer.send(invite.host, invite.port, invite.key, bytes)

    public suspend fun receiveNearby(
        media: LocalGenUiMedia,
        request: LocalGenUiCollaborationRequest,
        address: String,
        port: Int,
        onApproval: (LocalGenUiNearbyApproval?) -> Unit,
        onReady: () -> Unit,
    ): String? {
        if (!localAddress(address) || port !in 1024..65535) return null
        val kind = request.kind ?: return null
        return receiveAsset(media, request) { save ->
            GenUiNearbyImageTransfer.receive(
                address, port, kind.ordinal.toByte(),
                confirm = { approve(it, kind, onApproval) },
                ready = { withContext(Dispatchers.Main) { onReady() } },
                save = save,
            )
        }
    }

    public suspend fun awaitNearbyUpload(
        address: String,
        onListening: (Int) -> Unit,
        onApproval: (LocalGenUiNearbyApproval?) -> Unit,
        onUpload: (LocalGenUiNearbyUpload?) -> Unit,
    ): Boolean {
        if (!localAddress(address)) return false
        var capture: LocalGenUiNearbyUpload? = null
        return try {
            GenUiNearbyImageTransfer.listen(address, opened = { port ->
                withContext(Dispatchers.Main) { onListening(port) }
            }, confirm = { verification, kind ->
                approve(verification, LocalGenUiImageKind.entries[kind.toInt()], onApproval)
            }, capture = { kind ->
                val upload = LocalGenUiNearbyUpload(LocalGenUiImageKind.entries[kind.toInt()])
                capture = upload
                withContext(Dispatchers.Main) { onUpload(upload) }
                upload.awaitImage()
            }, delivered = { capture?.finish(it) })
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            false
        } finally {
            capture?.finish(false)
            withContext(Dispatchers.Main + NonCancellable) { onUpload(null) }
        }
    }

    private suspend fun approve(
        verification: String,
        kind: LocalGenUiImageKind,
        onApproval: (LocalGenUiNearbyApproval?) -> Unit,
    ): Boolean {
        val approval = LocalGenUiNearbyApproval(verification, kind)
        return try {
            withContext(Dispatchers.Main) { onApproval(approval) }
            approval.awaitDecision()
        } finally {
            withContext(Dispatchers.Main + NonCancellable) { onApproval(null) }
        }
    }
}
