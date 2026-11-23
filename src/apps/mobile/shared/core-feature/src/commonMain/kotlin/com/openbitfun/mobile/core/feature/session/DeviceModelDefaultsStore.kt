package com.openbitfun.mobile.core.feature.session

import com.openbitfun.mobile.core.domain.ModelLabelPolicy
import com.openbitfun.mobile.core.protocol.CommandStatusResponse
import com.openbitfun.mobile.core.protocol.ModelCatalogResponse
import com.openbitfun.mobile.core.protocol.RemoteCommand
import com.openbitfun.mobile.core.protocol.RemoteDefaultModels
import com.openbitfun.mobile.core.protocol.RemoteModelCatalog
import com.openbitfun.mobile.core.protocol.RemoteModelConfig
import com.openbitfun.mobile.core.protocol.isError
import com.openbitfun.mobile.core.transport.RemoteCommandTransport
import com.openbitfun.mobile.core.transport.send
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

public enum class DeviceModelRole(public val allowsUnset: Boolean) {
    PRIMARY(false), FAST(true), IMAGE_UNDERSTANDING(true),
}

public enum class DeviceModelAvailability { DISCONNECTED, CHECKING, UNSUPPORTED, AVAILABLE }

public enum class DeviceModelOperation { IDLE, LOADING, READY, SAVING, SAVED, LOAD_FAILED, WRITE_FAILED }

public data class DeviceModelChoiceUi(
    public val id: String,
    public val title: String,
    public val subtitle: String,
)

public data class DeviceModelRoleUi(
    public val role: DeviceModelRole,
    public val selected: DeviceModelChoiceUi?,
    public val resolved: Boolean,
    public val choices: List<DeviceModelChoiceUi>,
)

public data class DeviceModelDefaultsUiState(
    public val availability: DeviceModelAvailability,
    public val operation: DeviceModelOperation,
    public val roles: List<DeviceModelRoleUi>,
    public val activeRole: DeviceModelRole?,
    public val hasModels: Boolean,
) {
    public constructor(availability: DeviceModelAvailability) : this(availability, DeviceModelOperation.IDLE, emptyList(), null, false)
    public constructor() : this(DeviceModelAvailability.DISCONNECTED)

    public val busy: Boolean get() = operation == DeviceModelOperation.LOADING || operation == DeviceModelOperation.SAVING
    public val canEdit: Boolean get() = availability == DeviceModelAvailability.AVAILABLE &&
        !busy && operation != DeviceModelOperation.LOAD_FAILED && roles.isNotEmpty()
}

/** All work uses the session store's transport, which is bound to one device. */
internal class DeviceModelDefaultsStore(
    private val scope: CoroutineScope,
    private val transport: RemoteCommandTransport,
    private val onSaved: () -> Unit,
) {
    private val mutableState = MutableStateFlow(DeviceModelDefaultsUiState())
    val state = mutableState.asStateFlow()
    private var open = false
    private var generation = 0L
    private var work: Job? = null
    private var requestedModelId: String? = null

    fun setGate(connected: Boolean, supported: Boolean?) {
        val availability = when {
            !connected -> DeviceModelAvailability.DISCONNECTED
            supported == null -> DeviceModelAvailability.CHECKING
            supported -> DeviceModelAvailability.AVAILABLE
            else -> DeviceModelAvailability.UNSUPPORTED
        }
        if (state.value.availability == availability) return
        invalidate(availability)
        load()
    }

    fun open() {
        open = true
        if (state.value.operation == DeviceModelOperation.IDLE) load()
    }

    fun close() {
        open = false
        invalidate(state.value.availability)
    }

    private fun invalidate(availability: DeviceModelAvailability) {
        generation += 1
        work?.cancel()
        requestedModelId = null
        mutableState.value = DeviceModelDefaultsUiState(availability)
    }

    fun retry() {
        val snapshot = state.value
        val role = snapshot.activeRole
        if (snapshot.operation == DeviceModelOperation.WRITE_FAILED && role != null) {
            val id = requestedModelId
            if (id == null || snapshot.roles.firstOrNull { it.role == role }?.choices?.any { it.id == id } == true) {
                select(role, id)
                return
            }
        }
        load()
    }

    fun load() {
        val snapshot = state.value
        if (!open || snapshot.availability != DeviceModelAvailability.AVAILABLE || snapshot.busy) return
        val token = ++generation
        mutableState.value = snapshot.copy(operation = DeviceModelOperation.LOADING, activeRole = null)
        work = scope.launch {
            try {
                val catalog = readCatalog()
                if (generation == token) publish(catalog, DeviceModelOperation.READY)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                fail(token, DeviceModelOperation.LOAD_FAILED)
            }
        }
    }

    fun select(role: DeviceModelRole, modelId: String?) {
        val snapshot = state.value
        val row = snapshot.roles.firstOrNull { it.role == role } ?: return
        if (!open || !snapshot.canEdit || modelId == row.selected?.id) return
        if (modelId == null && !role.allowsUnset || modelId != null && row.choices.none { it.id == modelId }) return

        val token = ++generation
        requestedModelId = modelId
        mutableState.value = snapshot.copy(operation = DeviceModelOperation.SAVING, activeRole = role)
        work = scope.launch {
            var failure = DeviceModelOperation.WRITE_FAILED
            try {
                // Another controller may have edited different slots since the page opened.
                val latest = readCatalog()
                if (generation != token) return@launch
                if (modelId != null && latest.candidates(role).none { it.id == modelId }) {
                    publish(latest, DeviceModelOperation.WRITE_FAILED)
                    return@launch
                }
                val old = latest.defaultModels
                if (old.idFor(role) == modelId) {
                    publish(latest, DeviceModelOperation.READY)
                    return@launch
                }
                val response = transport.send<CommandStatusResponse>(RemoteCommand(
                    cmd = "set_model_defaults",
                    primaryDefault = slot(if (role == DeviceModelRole.PRIMARY) modelId else old.primary),
                    fastDefault = slot(if (role == DeviceModelRole.FAST) modelId else old.fast),
                    imageUnderstandingDefault = slot(
                        if (role == DeviceModelRole.IMAGE_UNDERSTANDING) modelId else old.imageUnderstanding,
                    ),
                ))
                check(response.resp == "ok")
                if (generation != token) return@launch

                failure = DeviceModelOperation.LOAD_FAILED
                val stored = readCatalog()
                if (generation != token) return@launch
                publish(stored, DeviceModelOperation.SAVED)
                onSaved()
                delay(2_000)
                if (generation == token) {
                    mutableState.value = state.value.copy(operation = DeviceModelOperation.READY, activeRole = null)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                fail(token, failure)
            }
        }
    }

    private suspend fun readCatalog(): RemoteModelCatalog {
        val result = transport.send<ModelCatalogResponse>(RemoteCommand(cmd = "get_model_catalog"))
        check(!result.isError)
        return checkNotNull(result.catalog)
    }

    private fun fail(token: Long, operation: DeviceModelOperation) {
        if (generation == token) mutableState.value = state.value.copy(operation = operation)
    }

    private fun publish(catalog: RemoteModelCatalog, operation: DeviceModelOperation) {
        val roles = DeviceModelRole.entries.map { role ->
            val id = catalog.defaultModels.idFor(role)
            val candidates = catalog.candidates(role)
            val selected = id?.let {
                catalog.models.firstOrNull { it.id == id }?.choice() ?: DeviceModelChoiceUi(id, id, "")
            }
            val resolved = if (role == DeviceModelRole.FAST && id == null) catalog.defaultModels.primary else id
            DeviceModelRoleUi(role, selected, candidates.any { it.id == resolved }, candidates.map { it.choice() })
        }
        mutableState.value = state.value.copy(operation = operation, roles = roles, hasModels = catalog.models.isNotEmpty())
    }

    private fun slot(value: String?) = value?.let(::JsonPrimitive) ?: JsonNull

    private fun RemoteDefaultModels.idFor(role: DeviceModelRole): String? = when (role) {
        DeviceModelRole.PRIMARY -> primary
        DeviceModelRole.FAST -> fast
        DeviceModelRole.IMAGE_UNDERSTANDING -> imageUnderstanding
    }?.takeIf(String::isNotBlank)

    private fun RemoteModelCatalog.candidates(role: DeviceModelRole): List<RemoteModelConfig> {
        val capability = if (role == DeviceModelRole.IMAGE_UNDERSTANDING) "image_understanding" else "text_chat"
        return models.filter { it.id.isNotBlank() && it.enabled && capability in it.capabilities }.distinctBy { it.id }
    }

    private fun RemoteModelConfig.choice(): DeviceModelChoiceUi = DeviceModelChoiceUi(
        id,
        ModelLabelPolicy.primaryLabel(id, name, modelName, id),
        listOfNotNull(
            ModelLabelPolicy.cleanLabel(provider).takeIf(String::isNotEmpty),
            contextWindow?.takeIf { it > 0 }?.let { "${(it / 1000.0).roundToInt()}k" },
        ).joinToString(" · "),
    )
}
