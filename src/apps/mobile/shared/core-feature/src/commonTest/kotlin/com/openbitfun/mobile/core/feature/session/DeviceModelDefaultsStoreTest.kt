package com.openbitfun.mobile.core.feature.session

import com.openbitfun.mobile.core.protocol.CommandStatus
import com.openbitfun.mobile.core.protocol.ModelCatalogResponse
import com.openbitfun.mobile.core.protocol.RelayJson
import com.openbitfun.mobile.core.protocol.RemoteCommand
import com.openbitfun.mobile.core.protocol.RemoteDefaultModels
import com.openbitfun.mobile.core.protocol.RemoteModelCatalog
import com.openbitfun.mobile.core.protocol.RemoteModelConfig
import com.openbitfun.mobile.core.transport.RemoteCommandTransport
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DeviceModelDefaultsStoreTest {
    @Test
    fun oldAndUnknownHostsNeverReceiveDefaultModelRequests() = runTest {
        val peer = ModelDefaultsPeer()
        val store = DeviceModelDefaultsStore(backgroundScope, peer) {}
        store.setGate(connected = true, supported = null)
        store.open()
        assertEquals(DeviceModelAvailability.CHECKING, store.state.value.availability)
        store.setGate(connected = true, supported = false)
        store.load()
        store.select(DeviceModelRole.FAST, "fast")
        runCurrent()
        assertEquals(DeviceModelAvailability.UNSUPPORTED, store.state.value.availability)
        assertTrue(peer.commands.isEmpty())
    }

    @Test
    fun choiceFiltersByCapabilityAndWritesFreshValuesBeforeShowingReadBack() = runTest {
        val peer = ModelDefaultsPeer()
        var invalidations = 0
        val store = DeviceModelDefaultsStore(backgroundScope, peer) { invalidations++ }
        store.setGate(connected = true, supported = true)
        runCurrent()
        assertTrue(peer.commands.isEmpty())
        store.open()
        runCurrent()
        assertEquals(listOf("primary", "fast"), store.row(DeviceModelRole.PRIMARY).choices.map { it.id })
        assertEquals(listOf("vision"), store.row(DeviceModelRole.IMAGE_UNDERSTANDING).choices.map { it.id })
        store.select(DeviceModelRole.PRIMARY, null)
        store.select(DeviceModelRole.IMAGE_UNDERSTANDING, "fast")
        assertEquals(1, peer.commands.size)

        // The desktop changed another slot while the mobile page was open.
        peer.defaults = peer.defaults.copy(primary = "fast", imageUnderstanding = null)
        peer.writeGate = CompletableDeferred()
        store.select(DeviceModelRole.FAST, null)
        runCurrent()
        assertEquals(DeviceModelOperation.SAVING, store.state.value.operation)
        assertEquals("fast", store.row(DeviceModelRole.FAST).selected?.id)
        val body = RelayJson.parseToJsonElement(RelayJson.encodeToString(peer.commands.last())).jsonObject
        assertEquals(setOf("cmd", "primary", "fast", "image_understanding"), body.keys)
        assertEquals(JsonPrimitive("fast"), body["primary"])
        assertEquals(JsonNull, body["fast"])
        assertEquals(JsonNull, body["image_understanding"])
        peer.writeGate?.complete(Unit)
        runCurrent()

        assertEquals(listOf("get_model_catalog", "get_model_catalog", "set_model_defaults", "get_model_catalog"),
            peer.commands.map { it.cmd })
        assertTrue(peer.commands.all { it.sessionId == null })
        assertEquals(DeviceModelOperation.SAVED, store.state.value.operation)
        assertNull(store.row(DeviceModelRole.FAST).selected)
        assertTrue(store.row(DeviceModelRole.FAST).resolved)
        assertEquals("fast", store.row(DeviceModelRole.PRIMARY).selected?.id)
        assertEquals("unmanaged", peer.defaults.search)
        assertEquals(1, invalidations)
    }

    @Test
    fun latePreflightReadAfterDisconnectCannotWriteOrReplaceTheNewProjection() = runTest {
        val peer = ModelDefaultsPeer()
        val store = DeviceModelDefaultsStore(backgroundScope, peer) {}
        store.setGate(connected = true, supported = true)
        store.open()
        runCurrent()
        peer.deferNextRead = true
        store.select(DeviceModelRole.FAST, null)
        runCurrent()
        val lateRead = checkNotNull(peer.deferredRead)
        store.setGate(connected = false, supported = true)
        store.setGate(connected = true, supported = false)
        lateRead.resume(Unit)
        runCurrent()
        assertEquals(DeviceModelAvailability.UNSUPPORTED, store.state.value.availability)
        assertTrue(store.state.value.roles.isEmpty())
        assertTrue(peer.commands.none { it.cmd == "set_model_defaults" })
    }

    @Test
    fun failedReadBackRequiresAReadBeforeMoreWrites() = runTest {
        val peer = ModelDefaultsPeer()
        val store = DeviceModelDefaultsStore(backgroundScope, peer) {}
        store.setGate(connected = true, supported = true)
        store.open()
        runCurrent()
        peer.failReadBack = true
        store.select(DeviceModelRole.FAST, null)
        runCurrent()
        assertEquals(DeviceModelOperation.LOAD_FAILED, store.state.value.operation)
        assertFalse(store.state.value.canEdit)
        assertEquals("fast", store.row(DeviceModelRole.FAST).selected?.id)
        peer.failReadBack = false
        store.load()
        runCurrent()
        assertEquals(DeviceModelOperation.READY, store.state.value.operation)
        assertNull(store.row(DeviceModelRole.FAST).selected)
        assertEquals(1, peer.commands.count { it.cmd == "set_model_defaults" })
    }

    @Test
    fun retryAfterWriteRejectionUsesTheSameRoleAndAFreshRead() = runTest {
        val peer = ModelDefaultsPeer()
        val store = DeviceModelDefaultsStore(backgroundScope, peer) {}
        store.setGate(connected = true, supported = true)
        store.open()
        runCurrent()
        peer.rejectWrite = true
        store.select(DeviceModelRole.FAST, null)
        runCurrent()
        assertEquals(DeviceModelOperation.WRITE_FAILED, store.state.value.operation)
        assertEquals("fast", store.row(DeviceModelRole.FAST).selected?.id)
        peer.defaults = peer.defaults.copy(primary = "fast")
        peer.rejectWrite = false
        store.retry()
        runCurrent()
        assertEquals(DeviceModelOperation.SAVED, store.state.value.operation)
        assertNull(store.row(DeviceModelRole.FAST).selected)
        assertEquals(listOf("get_model_catalog", "set_model_defaults", "get_model_catalog"), peer.commands.takeLast(3).map { it.cmd })
        assertEquals(JsonPrimitive("fast"), peer.commands.last { it.cmd == "set_model_defaults" }.primaryDefault)
    }

    private fun DeviceModelDefaultsStore.row(role: DeviceModelRole) = state.value.roles.single { it.role == role }
}

private class ModelDefaultsPeer : RemoteCommandTransport {
    var defaults = RemoteDefaultModels(primary = "primary", fast = "fast", imageUnderstanding = "vision", search = "unmanaged")
    val commands = mutableListOf<RemoteCommand>()
    var writeGate: CompletableDeferred<Unit>? = null
    var deferNextRead = false
    var deferredRead: Continuation<Unit>? = null
    var failReadBack = false
    var rejectWrite = false
    private var wrote = false
    private val models = listOf(
        RemoteModelConfig(id = "primary", enabled = true, capabilities = listOf("text_chat")),
        RemoteModelConfig(id = "fast", enabled = true, capabilities = listOf("text_chat")),
        RemoteModelConfig(id = "vision", enabled = true, capabilities = listOf("image_understanding")),
        RemoteModelConfig(id = "disabled", enabled = false, capabilities = listOf("image_understanding", "text_chat")),
    )

    override suspend fun <T : CommandStatus> send(
        deserializer: DeserializationStrategy<T>,
        command: RemoteCommand,
        timeoutMs: Long,
    ): T {
        commands += command
        val reply = when (command.cmd) {
            "get_model_catalog" -> {
                if (deferNextRead) {
                    deferNextRead = false
                    suspendCoroutine { deferredRead = it }
                }
                check(!failReadBack || !wrote)
                RelayJson.encodeToString(ModelCatalogResponse("ok", catalog = RemoteModelCatalog(models = models, defaultModels = defaults)))
            }
            "set_model_defaults" -> {
                writeGate?.await()
                if (rejectWrite) {
                    """{"resp":"error","message":"Fixture rejected the write"}"""
                } else {
                    defaults = defaults.copy(
                        primary = (command.primaryDefault as? JsonPrimitive)?.content?.takeUnless { command.primaryDefault == JsonNull },
                        fast = (command.fastDefault as? JsonPrimitive)?.content?.takeUnless { command.fastDefault == JsonNull },
                        imageUnderstanding = (command.imageUnderstandingDefault as? JsonPrimitive)?.content
                            ?.takeUnless { command.imageUnderstandingDefault == JsonNull },
                    )
                    wrote = true
                    """{"resp":"ok","default_models":{"fast":"an acknowledgement does not decide the UI"}}"""
                }
            }
            else -> error("Unexpected command ${command.cmd}")
        }
        return RelayJson.decodeFromString(deserializer, reply)
    }
}
