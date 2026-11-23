package com.openbitfun.mobile.core.transport

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GenUiImageTransferTest {
    private val jpeg = byteArrayOf(-1, -40, 12, 0, -1, -39)

    @Test
    fun nearbyTransferRequiresBothApprovalsAndSendsOverTheRequestConnection() = runBlocking {
        withTimeout(15_000L) {
            val address = "127.0.0.1"
            val listening = CompletableDeferred<Int>()
            val matchingCodes = mutableListOf<String>()
            val received = CompletableDeferred<ByteArray>()
            val receipt = CompletableDeferred<Boolean>()
            val sender = async {
                GenUiNearbyImageTransfer.listen(address, opened = { listening.complete(it) }, confirm = { code, kind ->
                    if (kind == 0.toByte()) false else {
                        synchronized(matchingCodes) { matchingCodes += code }
                        true
                    }
                }, capture = { kind ->
                    check(kind == 2.toByte())
                    jpeg
                }, delivered = { receipt.complete(it) })
            }
            val port = listening.await()
            assertFalse(GenUiNearbyImageTransfer.receive(address, port, 0, { true }, {}, { error("Unexpected image") }))
            assertFalse(GenUiNearbyImageTransfer.receive(address, port, 2, { false }, {}, { error("Unexpected image") }))
            assertTrue(GenUiNearbyImageTransfer.receive(address, port, 2, { code ->
                synchronized(matchingCodes) { matchingCodes += code }
                true
            }, ready = {}, save = { received.complete(it) }))
            assertTrue(matchingCodes.takeLast(2).distinct().size == 1)
            assertTrue(receipt.await())
            assertContentEquals(jpeg, received.await())
            assertTrue(sender.await())
        }
    }

    @Test
    fun authenticatesBeforeSendingAndAcknowledgesOnlySavedImage() = runBlocking {
        withTimeout(10_000L) {
            val invite = CompletableDeferred<Pair<Int, ByteArray>>()
            val received = CompletableDeferred<ByteArray>()
            var saves = 0
            val listening = async {
                GenUiImageTransfer.receive("127.0.0.1", { port, key -> invite.complete(port to key.copyOf()) }) {
                    if (++saves == 1) false
                    else { received.complete(it); true }
                }
            }
            val (port, key) = invite.await()
            val wrong = key.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
            assertFalse(GenUiImageTransfer.send("127.0.0.1", port, wrong, jpeg))
            assertFalse(GenUiImageTransfer.send("127.0.0.1", port, key, byteArrayOf(1, 2)))
            assertFalse(GenUiImageTransfer.send("127.0.0.1", port, key, jpeg))
            assertTrue(GenUiImageTransfer.send("127.0.0.1", port, key, jpeg))
            assertContentEquals(jpeg, received.await())
            assertTrue(listening.await())
        }
    }

    @Test
    fun persistsOneAppScopedImageAcrossInstances() = runBlocking {
        val directory = Files.createTempDirectory("genui-user-images")
        try {
            val app = "local-genui:a5a162ba-1fdb-438f-b196-a29a9739aa39"
            val another = "local-genui:b5a162ba-1fdb-438f-b196-a29a9739aa39"
            val asset = GenUiUserImages(directory.toString()).write(app, jpeg)
            val path = asset.substringAfter(".invalid")
            val reopened = GenUiUserImages(directory.toString())
            assertContentEquals(jpeg, reopened.read(app, path))
            assertNull(reopened.read(another, path))
            assertNull(reopened.read(app, path + "/../another.jpg"))
            reopened.discard(app, asset)
            assertNull(reopened.read(app, path))
        } finally { directory.toFile().deleteRecursively() }
    }
}
