package com.openbitfun.mobile.core.transport

import com.openbitfun.mobile.core.crypto.DeviceIdentity
import com.openbitfun.mobile.core.crypto.LocalImageCipher
import io.ktor.network.selector.SelectorManager
import io.ktor.network.sockets.InetSocketAddress
import io.ktor.network.sockets.Socket
import io.ktor.network.sockets.aSocket
import io.ktor.network.sockets.openReadChannel
import io.ktor.network.sockets.openWriteChannel
import io.ktor.utils.io.ByteReadChannel
import io.ktor.utils.io.ByteWriteChannel
import io.ktor.utils.io.readFully
import io.ktor.utils.io.readInt
import io.ktor.utils.io.writeFully
import io.ktor.utils.io.writeInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** A verified local image exchange on the connection opened by the requester. */
public object GenUiNearbyImageTransfer {
    private const val SHARE_LIFETIME = 180_000L
    private const val CAPTURE_TIMEOUT = 180_000L
    private const val VERIFY_TIMEOUT = 60_000L
    private const val HELLO_TIMEOUT = 5_000L
    private const val RECEIPT_TIMEOUT = 10_000L
    private const val PUBLIC_BYTES = 32
    private const val NONCE_BYTES = 16
    private const val DIGEST_BYTES = 32
    private const val REQUEST: Byte = 1
    private const val CONFIRMATION: Byte = 2
    private const val IMAGE: Byte = 3
    private const val RECEIPT: Byte = 4
    private val protocol = "OpenBitFun nearby image transfer v2".encodeToByteArray()

    public suspend fun receive(
        host: String,
        port: Int,
        kind: Byte,
        confirm: suspend (String) -> Boolean,
        ready: suspend () -> Unit,
        save: suspend (ByteArray) -> Boolean,
    ): Boolean = withContext(Dispatchers.IO) {
        require(kind in 0..2)
        val selector = SelectorManager(coroutineContext)
        try {
            attempt {
                val socket = withTimeoutOrNull(HELLO_TIMEOUT) { aSocket(selector).tcp().connect(host, port) }
                    ?: return@attempt false
                try {
                    val peer = pair(socket, initiating = true) ?: return@attempt false
                    try {
                        val approved = withTimeoutOrNull(VERIFY_TIMEOUT) {
                            peer.write(byteArrayOf(REQUEST, kind))
                            if (!confirm(peer.code)) return@withTimeoutOrNull false
                            peer.write(byteArrayOf(CONFIRMATION))
                            peer.read(1, 1).single() == CONFIRMATION
                        }
                        if (approved != true) return@attempt false
                        ready()
                        val frame = withTimeoutOrNull(CAPTURE_TIMEOUT) {
                            peer.read(5, 1 + GenUiImageTransfer.MAX_IMAGE_BYTES)
                        } ?: return@attempt false
                        if (frame[0] != IMAGE) return@attempt false
                        val bytes = frame.copyOfRange(1, frame.size)
                        if (!GenUiImageTransfer.isJpeg(bytes) || !save(bytes)) return@attempt false
                        withTimeoutOrNull(RECEIPT_TIMEOUT) { attempt { peer.write(byteArrayOf(RECEIPT)) } }
                        true
                    } finally { peer.key.fill(0) }
                } finally { socket.close() }
            } ?: false
        } finally { selector.close() }
    }

    public suspend fun listen(
        host: String,
        opened: suspend (Int) -> Unit,
        confirm: suspend (String, Byte) -> Boolean,
        capture: suspend (Byte) -> ByteArray?,
        delivered: suspend (Boolean) -> Unit,
    ): Boolean = withContext(Dispatchers.IO) {
        val selector = SelectorManager(coroutineContext)
        try {
            val listener = aSocket(selector).tcp().bind(host, 0)
            var approved: ApprovedRequest? = null
            try {
                opened((listener.localAddress as InetSocketAddress).port)
                withTimeoutOrNull(SHARE_LIFETIME) {
                    while (approved == null) {
                        val socket = listener.accept()
                        try {
                            approved = attempt { approve(socket, confirm) }
                        } finally {
                            if (approved == null) socket.close()
                        }
                    }
                }
                val session = approved ?: return@withContext false
                val bytes = withTimeoutOrNull(CAPTURE_TIMEOUT) { capture(session.kind) }
                    ?: return@withContext false
                val sent = GenUiImageTransfer.isJpeg(bytes) &&
                    withTimeoutOrNull(RECEIPT_TIMEOUT) {
                        attempt {
                            session.peer.write(byteArrayOf(IMAGE) + bytes)
                            session.peer.read(1, 1).single() == RECEIPT
                        }
                    } == true
                delivered(sent)
                sent
            } finally {
                approved?.peer?.key?.fill(0)
                approved?.socket?.close()
                listener.close()
            }
        } finally { selector.close() }
    }

    private class ApprovedRequest(val socket: Socket, val peer: PairedSocket, val kind: Byte)

    private suspend fun approve(
        socket: Socket,
        confirm: suspend (String, Byte) -> Boolean,
    ): ApprovedRequest? {
        val peer = pair(socket, initiating = false) ?: return null
        var approved = false
        try {
            val operation = withTimeoutOrNull(VERIFY_TIMEOUT) {
                val request = withTimeoutOrNull(HELLO_TIMEOUT) { peer.read(2, 2) }
                    ?: return@withTimeoutOrNull null
                val kind = request[1]
                if (request[0] != REQUEST || kind !in 0..2 || !confirm(peer.code, kind)) {
                    return@withTimeoutOrNull null
                }
                if (peer.read(1, 1).single() != CONFIRMATION) return@withTimeoutOrNull null
                peer.write(byteArrayOf(CONFIRMATION))
                kind
            } ?: return null
            approved = true
            return ApprovedRequest(socket, peer, operation)
        } finally {
            if (!approved) peer.key.fill(0)
        }
    }

    private class PairedSocket(
        val key: ByteArray,
        val code: String,
        val input: ByteReadChannel,
        val output: ByteWriteChannel,
    ) {
        suspend fun write(bytes: ByteArray) {
            val record = LocalImageCipher.seal(key, bytes)
            output.writeInt(record.size)
            output.writeFully(record)
        }

        suspend fun read(minimum: Int, maximum: Int): ByteArray {
            val size = input.readInt()
            require(size in (minimum + LocalImageCipher.OVERHEAD)..(maximum + LocalImageCipher.OVERHEAD))
            return LocalImageCipher.open(key, ByteArray(size).also { input.readFully(it) })
        }
    }

    private suspend fun pair(socket: Socket, initiating: Boolean): PairedSocket? =
        withTimeoutOrNull(HELLO_TIMEOUT) {
            val input = socket.openReadChannel()
            val output = socket.openWriteChannel(autoFlush = true)
            val secret = DeviceIdentity.generateSecret()
            try {
                val hello = DeviceIdentity.publicKey(secret) + DeviceIdentity.randomBytes(NONCE_BYTES)
                // Both peers commit before revealing their keys and random challenges.
                val commitment = LocalImageCipher.pairingDigest(protocol + hello)
                output.writeFully(commitment)
                val peerCommitment = ByteArray(DIGEST_BYTES).also { input.readFully(it) }
                output.writeFully(hello)
                val peerHello = ByteArray(PUBLIC_BYTES + NONCE_BYTES).also { input.readFully(it) }
                require(LocalImageCipher.pairingDigest(protocol + peerHello).contentEquals(peerCommitment))
                val transcript = if (initiating) hello + peerHello else peerHello + hello
                val shared = DeviceIdentity.messageKey(secret, peerHello.copyOf(PUBLIC_BYTES))
                try {
                    val key = LocalImageCipher.pairingDigest(protocol + byteArrayOf(1) + transcript + shared)
                    val check = LocalImageCipher.pairingDigest(protocol + byteArrayOf(2) + transcript + shared)
                    val code = check.take(4).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
                        .uppercase().chunked(4).joinToString(" ")
                    PairedSocket(key, code, input, output)
                } finally { shared.fill(0) }
            } finally { secret.fill(0) }
        }

    private suspend fun <T> attempt(body: suspend () -> T): T? = try {
        body()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}
