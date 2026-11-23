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

/**
 * Foreground-only image exchange over a local socket. A high-entropy secret is
 * handed to the sender out of band with the invite, never written to the socket.
 * The receiver proves possession before the sender releases bytes. A fresh
 * challenge binds the upload and receipt to this particular connection.
 */
public object GenUiImageTransfer {
    public const val MAX_IMAGE_BYTES: Int = 2 * 1024 * 1024
    private const val CHALLENGE_BYTES = 16
    private const val OFFER_LIFETIME_MS = 180_000L
    private const val CONNECTION_TIMEOUT_MS = 12_000L
    private const val GREETING: Byte = 1
    private const val UPLOAD: Byte = 2
    private const val ACCEPTED: Byte = 3

    public fun isJpeg(bytes: ByteArray): Boolean =
        bytes.size in 4..MAX_IMAGE_BYTES &&
            bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() &&
            bytes[bytes.lastIndex - 1] == 0xff.toByte() && bytes.last() == 0xd9.toByte()

    public suspend fun receive(
        host: String,
        opened: suspend (port: Int, key: ByteArray) -> Unit,
        save: suspend (ByteArray) -> Boolean,
    ): Boolean = withContext(Dispatchers.IO) {
        val key = LocalImageCipher.newKey()
        val selector = SelectorManager(coroutineContext)
        try {
            val listener = aSocket(selector).tcp().bind(host, 0)
            try {
                opened((listener.localAddress as InetSocketAddress).port, key)
                withTimeoutOrNull(OFFER_LIFETIME_MS) {
                    var saved = false
                    while (!saved) {
                        val socket = listener.accept()
                        saved = try {
                            receiveOne(socket, key, save)
                        } finally { socket.close() }
                    }
                    true
                } ?: false
            } finally { listener.close() }
        } finally {
            selector.close()
            key.fill(0)
        }
    }

    private suspend fun receiveOne(socket: Socket, key: ByteArray, save: suspend (ByteArray) -> Boolean): Boolean {
        val challenge = DeviceIdentity.randomBytes(CHALLENGE_BYTES)
        val output = socket.openWriteChannel(autoFlush = true)
        val input = socket.openReadChannel()
        val header = byteArrayOf(UPLOAD) + challenge
        val bytes = withTimeoutOrNull(CONNECTION_TIMEOUT_MS) {
            attempt {
                output.writeRecord(key, byteArrayOf(GREETING) + challenge)
                val upload = input.readRecord(key, header.size + 4, header.size + MAX_IMAGE_BYTES)
                require(upload.copyOfRange(0, header.size).contentEquals(header))
                upload.copyOfRange(header.size, upload.size).takeIf(::isJpeg)
            }
        } ?: return false
        if (!save(bytes)) return false
        withTimeoutOrNull(CONNECTION_TIMEOUT_MS) {
            attempt { output.writeRecord(key, byteArrayOf(ACCEPTED) + challenge) }
        }
        return true
    }

    public suspend fun send(host: String, port: Int, key: ByteArray, bytes: ByteArray): Boolean =
        withContext(Dispatchers.IO) {
            if (!isJpeg(bytes)) return@withContext false
            val selector = SelectorManager(coroutineContext)
            try {
                withTimeoutOrNull(CONNECTION_TIMEOUT_MS) {
                    attempt {
                        val socket = aSocket(selector).tcp().connect(host, port)
                        try {
                            val input = socket.openReadChannel()
                            val output = socket.openWriteChannel(autoFlush = true)
                            val greeting = input.readRecord(key, CHALLENGE_BYTES + 1)
                            require(greeting[0] == GREETING)
                            val challenge = greeting.copyOfRange(1, greeting.size)
                            output.writeRecord(key, byteArrayOf(UPLOAD) + challenge + bytes)
                            val receipt = input.readRecord(key, CHALLENGE_BYTES + 1)
                            receipt.contentEquals(byteArrayOf(ACCEPTED) + challenge)
                        } finally { socket.close() }
                    }
                } ?: false
            } finally { selector.close() }
        }

    private suspend fun ByteWriteChannel.writeRecord(key: ByteArray, bytes: ByteArray) {
        val frame = LocalImageCipher.seal(key, bytes)
        writeInt(frame.size)
        writeFully(frame)
    }

    private suspend fun ByteReadChannel.readRecord(key: ByteArray, minimum: Int, maximum: Int = minimum): ByteArray {
        val size = readInt()
        require(size in (minimum + LocalImageCipher.OVERHEAD)..(maximum + LocalImageCipher.OVERHEAD))
        return LocalImageCipher.open(key, ByteArray(size).also { readFully(it) })
    }

    private suspend fun <T> attempt(body: suspend () -> T): T? = try {
        body()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}
