package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.feature.generalchat.GeneralChatConfigValidator
import com.openbitfun.mobile.core.persistence.DraftStore
import com.openbitfun.mobile.core.persistence.SecureStore
import com.openbitfun.mobile.core.transport.GenUiProviderFrame
import com.openbitfun.mobile.core.transport.GenUiProviderStream
import com.openbitfun.mobile.core.transport.ModelProviderException
import com.openbitfun.mobile.core.transport.ModelProviderFailure
import com.openbitfun.mobile.core.transport.ModelProviderMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlin.time.Clock
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

@Serializable
private data class LocalGenUiLibrary(
    val sessions: List<LocalGenUiSession> = emptyList(),
    val apps: List<LocalGenUiApp> = emptyList(),
    val drafts: Map<String, String> = emptyMap(),
    val lastModelId: String? = null,
    val unsentSessionId: String? = null,
    val reviews: Map<String, LocalGenUiReview> = emptyMap(),
    val galleryOrder: List<String> = emptyList(),
) {
    fun withGalleryOrder(): LocalGenUiLibrary {
        val members = apps.filter { it.inGallery }.map { it.id }.toSet()
        val order = (galleryOrder + members).distinct().filter { it in members }
        // Libraries written before the order was saved keep their existing visible sequence.
        return if (order == galleryOrder) this else copy(galleryOrder = order)
    }
}

@Serializable
private class LocalGenUiModel(
    val id: String,
    val name: String,
    val endpoint: String,
    val model: String,
    val key: String,
) {
    fun ui() = LocalGenUiModelUi(id, name, endpoint, model, key.isNotBlank())
}

public class LocalGenUiStore internal constructor(
    private val scope: CoroutineScope,
    private val storage: DraftStore,
    private val secure: SecureStore,
    private val prompt: String,
    private val schema: String,
    private val provider: GenUiProviderStream,
    private val nowMillis: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) {
    private val events = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private val stateFlow = MutableStateFlow(LocalGenUiState())
    public val state: StateFlow<LocalGenUiState> = stateFlow.asStateFlow()
    private var library = LocalGenUiLibrary()
    private var models = emptyList<LocalGenUiModel>()
    private var loaded = false
    private var turn: Job? = null
    private var modelDiscovery: Job? = null
    private data class TurnRequest(
        val sessionId: String,
        val appId: String,
        val revision: Int,
        val profile: LocalGenUiModel,
        val messages: List<ModelProviderMessage>,
        val editBase: String?,
        val repairing: Boolean = false,
    )

    private data class Candidate(
        val text: String,
        val app: LocalGenUiApp,
        val initialValues: JsonObject,
        val ownerSourceRevision: Int?,
        val request: TurnRequest? = null,
        var mergedSource: String? = if (app.baseSource == null) app.source else null,
        var probe: LocalGenUiIntent.VerifyApp? = null,
        val ownerStateRevision: Int? = null,
        val recordOutcome: Boolean = request != null,
        var replyAtMillis: Long? = null,
    )

    private var candidate: Candidate? = null
    private var checkTimeout: Job? = null
    private var generation = 0
    private var showGeneratedApp = true
    private var activeSessionId: String? = null
    private var showConversation = false
    private val json = Json { ignoreUnknownKeys = true }

    init {
        scope.launch {
            load()
            for (event in events) {
                try {
                    event()
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    failure(LocalGenUiFailure.STORAGE)
                }
            }
        }
    }

    public fun dispatch(intent: LocalGenUiIntent) {
        events.trySend { handle(intent) }
    }

    private suspend fun load() {
        try {
            val (stored, profiles) = withContext(Dispatchers.Default) {
                val document = storage.load(LIBRARY)?.let { json.decodeFromString<LocalGenUiLibrary>(it) } ?: LocalGenUiLibrary()
                val entries = secure.read(MODELS)?.let { json.decodeFromString<List<LocalGenUiModel>>(it.decodeToString()) }.orEmpty()
                document to entries
            }
            library = stored.withGalleryOrder()
            models = profiles
            loaded = true
            publish(stateFlow.value.copy(loading = false, failure = null))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            publish(stateFlow.value.copy(loading = false, failure = LocalGenUiFailure.STORAGE))
        }
    }

    private suspend fun handle(intent: LocalGenUiIntent) {
        if (!loaded) {
            if (intent == LocalGenUiIntent.Reload) load()
            return
        }
        when (intent) {
            LocalGenUiIntent.Reload -> publish(stateFlow.value.copy(failure = null))
            LocalGenUiIntent.NewSession -> newSession()
            LocalGenUiIntent.Back -> {
                val previous = stateFlow.value
                if (previous.openApp != null) {
                    showGeneratedApp = false
                    publish(previous.copy(openApp = null, failure = null))
                } else {
                    showConversation = false
                    showGeneratedApp = false
                    publish(previous.copy(failure = null))
                }
            }
            LocalGenUiIntent.Cancel -> discardVerification()
            LocalGenUiIntent.Close -> {
                cancelModelDiscovery()
                cancel()
                showConversation = false
                publish(stateFlow.value.copy(openApp = null, failure = null))
            }
            is LocalGenUiIntent.Send -> {
                val current = stateFlow.value
                if (current.selectedSession?.id == intent.sessionId && current.draftAcceptedSerial == intent.draftAcceptedSerial) {
                    send(intent.text)
                }
            }
            is LocalGenUiIntent.EditDraft -> {
                val current = stateFlow.value
                if (current.selectedSession?.id != intent.sessionId || current.draftAcceptedSerial != intent.draftAcceptedSerial ||
                    current.draft == intent.text) return
                val drafts = if (intent.text.isEmpty()) library.drafts - intent.sessionId else library.drafts + (intent.sessionId to intent.text)
                save(library.copy(drafts = drafts))
                publish(current)
            }
            is LocalGenUiIntent.OpenSession -> {
                openSession(intent.id)
                if (stateFlow.value.selectedSession?.id == intent.id && candidate == null && turn == null) {
                    val review = library.reviews.values.lastOrNull { it.sessionId == intent.id && it.staged != null }
                    if (review != null) resumeVerification(review, showAfter = false)
                }
            }
            is LocalGenUiIntent.RenameSession -> {
                val session = library.sessions.firstOrNull { it.id == intent.id && it.id != library.unsentSessionId } ?: return
                val title = intent.title.trim().take(60).trimEnd { it.isHighSurrogate() }
                if (title.isEmpty() || (session.titleEdited && session.title == title)) return
                save(library.copy(sessions = library.sessions.map {
                    if (it.id == session.id) it.copy(title = title, titleEdited = true) else it
                }))
                publish(stateFlow.value)
            }
            is LocalGenUiIntent.DeleteSession -> {
                if (turn != null || candidate != null) return
                save(library.copy(
                    sessions = library.sessions.filterNot { it.id == intent.id },
                    apps = library.apps.filterNot { it.sessionId == intent.id },
                    drafts = library.drafts - intent.id,
                    unsentSessionId = library.unsentSessionId?.takeUnless { it == intent.id },
                    reviews = library.reviews.filterValues { it.sessionId != intent.id },
                ))
                if (activeSessionId == intent.id) {
                    activeSessionId = null
                    showConversation = false
                }
                publish(stateFlow.value.copy(openApp = stateFlow.value.openApp?.takeUnless { it.sessionId == intent.id }))
            }
            is LocalGenUiIntent.SelectModel -> selectModel(intent.id)
            LocalGenUiIntent.CancelModelDiscovery -> cancelModelDiscovery()
            LocalGenUiIntent.ResetModelEditor -> {
                cancelModelDiscovery()
                publish(stateFlow.value.copy(modelWriteFailure = null))
            }
            is LocalGenUiIntent.DiscoverModels -> discoverModels(intent)
            is LocalGenUiIntent.SaveModel -> modelWrite { saveModel(intent) }
            is LocalGenUiIntent.DeleteModel -> modelWrite {
                saveModels(models.filterNot { it.id == intent.id })
                null
            }
            is LocalGenUiIntent.UseModelForSetup -> modelWrite {
                if (models.none { it.id == intent.id && it.key.isNotBlank() }) LocalGenUiFailure.MISSING_MODEL
                else { pinModel(intent.id); null }
            }
            is LocalGenUiIntent.OpenApp -> openApp(intent.id)
            is LocalGenUiIntent.SetGallery -> updateApp(intent.id) { it.copy(inGallery = intent.added) }
            is LocalGenUiIntent.RecordCalendarReceipt -> updateApp(intent.id) { current ->
                current.copy(calendarReceipts = (current.calendarReceipts + intent.receipt).distinct())
            }
            is LocalGenUiIntent.VerifyApp -> acceptCandidate(intent)
            is LocalGenUiIntent.MergeApp -> mergeCandidate(intent)
            is LocalGenUiIntent.SaveAppState -> saveAppState(intent)
            is LocalGenUiIntent.ContinueConversation -> {
                val app = stateFlow.value.openApp ?: return
                if (app.id != intent.appId || app.sourceRevision != intent.sourceRevision || app.streaming || app.checking ||
                    app.failedValidation || turn != null || candidate != null) return
                openSession(app.sessionId)
                send(intent.message, app)
            }
        }
    }

    private suspend fun modelWrite(operation: suspend () -> LocalGenUiFailure?) {
        if (turn != null || candidate != null) return
        publish(stateFlow.value.copy(writingModel = true, modelWriteFailure = null))
        val failure = try {
            operation()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            LocalGenUiFailure.STORAGE
        }
        val current = stateFlow.value
        publish(current.copy(
            writingModel = false,
            modelWriteFailure = failure,
            modelWriteSerial = if (failure == null) current.modelWriteSerial + 1 else current.modelWriteSerial,
            failure = if (failure == null && current.failure == LocalGenUiFailure.MISSING_MODEL &&
                models.any { it.id == currentSessionModelId() }) null else current.failure,
        ))
    }

    private fun currentSessionModelId() = stateFlow.value.selectedSession?.let { session ->
        library.sessions.firstOrNull { it.id == session.id }?.modelId
    }

    private suspend fun saveModel(intent: LocalGenUiIntent.SaveModel): LocalGenUiFailure? {
        // An editor left open for a deleted model must not recreate it.
        val old = models.firstOrNull { it.id == intent.id }
        if (intent.id != null && old == null) return LocalGenUiFailure.MISSING_MODEL
        val endpoint = intent.endpoint.trim().trimEnd('/')
        val key = intent.apiKey.trim().ifEmpty { old?.takeIf { it.endpoint == endpoint }?.key.orEmpty() }
        if (!validModelInput(endpoint, intent.model, key)) return LocalGenUiFailure.INVALID_MODEL

        val profile = LocalGenUiModel(old?.id ?: id(), intent.name.trim().ifEmpty { intent.model.trim() }, endpoint, intent.model.trim(), key)
        val previous = models
        val next = if (old == null) previous + profile else previous.map { if (it.id == profile.id) profile else it }
        saveModels(next)
        if (old == null || intent.useForSession) {
            try {
                pinModel(profile.id)
            } catch (error: Exception) {
                // Profiles and the library have different storage owners. If
                // pinning fails, restore the prior profiles before reporting it.
                withContext(NonCancellable) { runCatching { saveModels(previous) } }
                throw error
            }
        }
        return null
    }

    private fun validModelInput(endpoint: String, model: String, key: String): Boolean =
        GeneralChatConfigValidator.validate(endpoint, model, key, false, false) == null &&
            endpoint.none { it == '@' || it == '?' || it == '\\' || it.isWhitespace() } &&
            GenUiProviderStream.isValidEndpoint(endpoint)

    private fun discoverModels(intent: LocalGenUiIntent.DiscoverModels) {
        cancelModelDiscovery()
        val endpoint = intent.endpoint.trim().trimEnd('/')
        val old = models.firstOrNull { it.id == intent.id && it.endpoint == endpoint }
        val key = intent.apiKey.trim().ifEmpty { old?.key.orEmpty() }
        if (!validModelInput(endpoint, "discovery", key)) {
            publish(stateFlow.value.copy(modelDiscoveryFailure = LocalGenUiFailure.INVALID_MODEL))
            return
        }
        publish(stateFlow.value.copy(discoveringModels = true, discoveredModels = emptyList(), modelDiscoveryFailure = null))
        modelDiscovery = scope.launch {
            val job = coroutineContext[Job]
            try {
                val options = provider.discoverModels(endpoint, key)
                events.send {
                    if (job == modelDiscovery) {
                        modelDiscovery = null
                        publish(stateFlow.value.copy(discoveringModels = false, discoveredModels = options))
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                events.send {
                    if (job == modelDiscovery) {
                        modelDiscovery = null
                        publish(stateFlow.value.copy(discoveringModels = false, modelDiscoveryFailure = error.failure()))
                    }
                }
            }
        }
    }

    private fun cancelModelDiscovery() {
        modelDiscovery?.cancel()
        modelDiscovery = null
        publish(stateFlow.value.copy(discoveringModels = false, discoveredModels = emptyList(), modelDiscoveryFailure = null))
    }

    private suspend fun selectModel(id: String) {
        if (turn != null || candidate != null || models.none { it.id == id && it.key.isNotBlank() }) return
        pinModel(id)
        publish(stateFlow.value.copy(failure = null))
    }

    private suspend fun pinModel(id: String) {
        val current = stateFlow.value.selectedSession?.id
        save(library.copy(
            sessions = library.sessions.map { if (it.id == current) it.copy(modelId = id) else it },
            lastModelId = id,
        ))
    }

    private suspend fun saveModels(next: List<LocalGenUiModel>) {
        withContext(Dispatchers.Default) { secure.write(MODELS, json.encodeToString(next).encodeToByteArray()) }
        models = next
    }

    private suspend fun newSession() {
        if (turn != null || candidate != null) return
        val draft = library.sessions.firstOrNull { it.id == library.unsentSessionId && it.messages.isEmpty() }
        if (draft != null) {
            openSession(draft.id)
            return
        }
        val id = id()
        val model = models.firstOrNull { it.id == library.lastModelId }?.id ?: models.firstOrNull()?.id
        save(library.copy(sessions = listOf(LocalGenUiSession(id, "", model)) + library.sessions, unsentSessionId = id))
        openSession(id)
    }

    private fun openSession(id: String) {
        val busy = turn != null || candidate != null
        if ((busy && activeSessionId != id) || library.sessions.none { it.id == id }) return
        activeSessionId = id
        showConversation = true
        if (busy) showGeneratedApp = true
        val current = stateFlow.value
        publish(current.copy(openApp = null, failure = null, streamingText = if (busy) current.streamingText else ""))
    }

    private suspend fun openApp(id: String) {
        val checking = candidate?.app
        if (checking?.id == id) {
            showGeneratedApp = true
            publish(stateFlow.value.copy(openApp = checking, failure = null))
            return
        }
        val app = library.apps.firstOrNull { it.id == id }
        val review = library.reviews[id]
        if (app == null && review?.staged == null) {
            publish(stateFlow.value.copy(openApp = null, failure = LocalGenUiFailure.APP_MISSING))
            return
        }
        val migrationRequired = review?.checks?.any {
            it.name == "state-migration" && it.result == LocalGenUiCheckResult.FAILED
        } == true
        if (app != null) publish(stateFlow.value.copy(openApp = app,
            failure = LocalGenUiFailure.STATE_MIGRATION_REQUIRED.takeIf { migrationRequired }))
        if (review?.staged != null && candidate == null && turn == null) {
            resumeVerification(review, showAfter = app == null)
        }
    }

    private suspend fun resumeVerification(review: LocalGenUiReview, showAfter: Boolean) {
        val staged = review.staged ?: return
        val previous = library.apps.firstOrNull { it.id == staged.id }
        // Older builds journaled only the reopened revision. Its state revision
        // was always the previous owner's revision plus one.
        val resume = review.resume ?: LocalGenUiReviewResume(
            "", JsonObject(emptyMap()), previous?.sourceRevision, previous?.let { staged.stateRevision - 1 },
        )
        val pending = Candidate(resume.text, staged, resume.initialValues, resume.ownerSourceRevision,
            ownerStateRevision = resume.ownerStateRevision, recordOutcome = resume.recordOutcome, replyAtMillis = resume.replyAtMillis)
        showGeneratedApp = showAfter
        if (staged.sessionId != review.sessionId || staged.sourceRevision != review.revision ||
            previous?.sourceRevision != resume.ownerSourceRevision ||
            (staged.reopening && previous?.stateRevision != resume.ownerStateRevision)) {
            rejectCandidate(pending, review.checks + LocalGenUiCheck("state-migration", LocalGenUiCheckResult.FAILED,
                "the owner changed after the candidate was staged"), LocalGenUiFailure.STATE_MIGRATION_REQUIRED)
            return
        }
        publish(stateFlow.value.copy(recovering = true, failure = null))
        awaitVerification(pending)
    }

    private suspend fun send(text: String, editing: LocalGenUiApp? = null) {
        val selected = stateFlow.value.selectedSession?.id ?: return
        val current = library.sessions.firstOrNull { it.id == selected } ?: return
        if (text.isBlank() || turn != null || candidate != null) return
        val profile = models.firstOrNull { it.id == current.modelId && it.key.isNotBlank() }
        if (profile == null) {
            failure(LocalGenUiFailure.MISSING_MODEL)
            return
        }
        val target = editing ?: library.apps.lastOrNull { it.sessionId == current.id }
        val runnable = target?.takeUnless { it.failedValidation }
        val now = maxOf(nowMillis(), current.updatedAtMillis ?: current.createdAtMillis ?: Long.MIN_VALUE)
        val user = LocalGenUiMessage("user", text.trim(), createdAtMillis = now)
        val history = current.messages + user
        val title = current.title.ifBlank { user.text.replace(Whitespace, " ").take(24) }
        val updated = current.copy(title = title, messages = history,
            createdAtMillis = current.createdAtMillis ?: now.takeIf { current.messages.isEmpty() }, updatedAtMillis = now)
        save(library.copy(
            sessions = library.sessions.map { if (it.id == current.id) updated else it },
            drafts = if (editing == null) library.drafts - current.id else library.drafts,
            unsentSessionId = library.unsentSessionId?.takeUnless { it == current.id },
        ))
        val appId = target?.id ?: id()
        val sourceRevision = maxOf(target?.sourceRevision ?: 0, library.reviews[appId]?.revision ?: 0) + 1
        val messages = history.filterNot { it.appGenerationFailed || it.automaticRepair || it.failure != null }.takeLast(32)
            .map { ModelProviderMessage(it.role, it.text) }.toMutableList()
        if (runnable != null) {
            val latest = messages.removeAt(messages.lastIndex)
            messages.add(latest.copy(content = "${latest.content}\n\nCurrent app source:\n${runnable.source}\n\nReturn the changed OpenUI statements as an edit patch or the complete updated app source."))
        }
        showGeneratedApp = true
        val previous = stateFlow.value
        publish(previous.copy(
            busy = true, repairing = false, streamingText = "", failure = null,
            draftAcceptedSerial = previous.draftAcceptedSerial + if (editing == null) 1 else 0,
        ))
        streamTurn(TurnRequest(current.id, appId, sourceRevision, profile, messages, runnable?.source))
    }

    private fun streamTurn(request: TurnRequest) {
        val serial = ++generation
        turn = scope.launch {
            val response = LocalGenUiTurn()
            try {
                val profile = request.profile
                val system = prompt + HOST_CAPABILITIES + if (request.repairing) REPAIR_EDIT_MODE else ""
                provider.stream(profile.endpoint, profile.key, profile.model, request.messages, system, schema) { frame ->
                    response.accept(frame)
                    val visibleText = response.text
                    val partial = if (frame is GenUiProviderFrame.Tool) response.preview(request.editBase != null) else null
                    if (frame is GenUiProviderFrame.Text || partial != null) events.trySend {
                        if (serial == generation) {
                            val before = stateFlow.value
                            val preview = if (partial != null && showGeneratedApp) {
                                LocalGenUiApp(request.appId, request.sessionId, partial.title, partial.source,
                                    request.revision, streaming = true, baseSource = request.editBase)
                            } else before.openApp
                            publish(before.copy(streamingText = visibleText, openApp = preview))
                        }
                    }
                }
                val generated = response.result(request.editBase != null)
                events.send {
                    if (serial != generation) return@send
                    turn = null
                    if (generated == null) {
                        if (request.repairing) generationFailed(request, LocalGenUiFailure.INVALID_RESPONSE, response.text)
                        else try { finishTurn(request.sessionId, response.text, null) } finally { finishBusy() }
                    } else {
                        checkCandidate(request, response.text, generated)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                events.send {
                    if (serial == generation) generationFailed(request, error.failure(), response.text)
                }
            }
        }
    }

    private fun finishBusy() {
        turn = null
        val current = stateFlow.value
        val app = current.openApp?.let { open ->
            if (!open.streaming && (!open.checking || candidate != null)) open
            else library.apps.firstOrNull { it.id == open.id }
        }
        publish(current.copy(busy = candidate != null, repairing = false, recovering = false, streamingText = "", openApp = app))
    }

    private fun restoreApp(id: String, reason: LocalGenUiFailure?) {
        val previous = library.apps.firstOrNull { it.id == id }
        val current = stateFlow.value
        val visibleApp = if (showGeneratedApp || current.openApp?.id == id) previous else current.openApp
        val failure = if (current.openApp == null || current.openApp.id == id) reason else current.failure
        publish(current.copy(failure = failure, openApp = visibleApp))
        finishBusy()
    }

    private suspend fun generationFailed(request: TurnRequest, reason: LocalGenUiFailure, text: String) {
        try {
            if (request.repairing) persistReply(request.sessionId, LocalGenUiMessage("assistant", text, failure = reason))
            restoreApp(request.appId, reason.takeUnless { request.repairing })
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            restoreApp(request.appId, LocalGenUiFailure.STORAGE)
        }
    }

    private suspend fun checkCandidate(request: TurnRequest, text: String, generated: LocalGenUiTurn.App) {
        val previous = library.apps.firstOrNull { it.id == request.appId }
        val saved = previous?.takeIf { it.userEdited }?.let { jsonObject(it.stateJson) }.orEmpty()
        val app = LocalGenUiApp(request.appId, request.sessionId, generated.title, generated.source, request.revision,
            stateJson = JsonObject(generated.values + saved).toString(), inGallery = previous?.inGallery == true,
            checking = true, baseSource = request.editBase, calendarReceipts = previous?.calendarReceipts.orEmpty())
        val pending = Candidate(text, app, generated.values, previous?.sourceRevision, request,
            ownerStateRevision = previous?.stateRevision)
        try {
            stageCandidate(pending, app)
            awaitVerification(pending)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            restoreApp(app.id, LocalGenUiFailure.STORAGE)
        }
    }

    private fun awaitVerification(pending: Candidate) {
        val app = pending.app
        checkTimeout?.cancel()
        candidate = pending
        val previous = stateFlow.value
        val visible = if (showGeneratedApp) app else previous.openApp?.takeUnless { it.checking || it.streaming }
        publish(previous.copy(busy = true, streamingText = "", openApp = visible))
        checkTimeout = scope.launch {
            delay(8_000)
            events.send {
                if (candidate === pending) {
                    val result = pending.probe ?: LocalGenUiDocument.unavailableProbe(app)
                    if (pending.mergedSource == null) {
                        rejectCandidate(pending, result.checks + LocalGenUiCheck("merge", LocalGenUiCheckResult.UNVERIFIED,
                            "the runtime did not return merged source"), LocalGenUiFailure.INVALID_RESPONSE)
                    } else {
                        acceptCandidate(result)
                    }
                }
            }
        }
    }

    private suspend fun acceptCandidate(result: LocalGenUiIntent.VerifyApp) {
        val pending = candidate ?: return
        if (pending.app.id != result.id || pending.app.sourceRevision != result.revision || pending.app.reopening != result.reopening) return
        if (!result.reopening) {
            pending.probe = result
            reviewChecker(pending)
            return
        }
        val review = reviewOf(pending)
        val checks = review.checks + result.checks
        val app = pending.app
        val previous = library.apps.firstOrNull { it.id == app.id }
        if (checks.any { it.result == LocalGenUiCheckResult.FAILED } || result.checks.count { it.name == "save-reopen" } != 1) {
            rejectCandidate(pending, checks, LocalGenUiFailure.INVALID_RESPONSE)
        } else if (previous?.sourceRevision != pending.ownerSourceRevision || previous?.stateRevision != pending.ownerStateRevision) {
            rejectCandidate(pending, checks + LocalGenUiCheck("state-migration", LocalGenUiCheckResult.FAILED,
                "user state changed during verification"), LocalGenUiFailure.STATE_MIGRATION_REQUIRED)
        } else {
            endVerification()
            try {
                finishTurn(app.sessionId, pending.text, app.copy(checking = false, reopening = false,
                    inGallery = previous?.inGallery == true, calendarReceipts = previous?.calendarReceipts.orEmpty()),
                    review.copy(checks = checks, staged = null, resume = null), pending.replyAtMillis)
            } finally { finishBusy() }
        }
    }

    private suspend fun mergeCandidate(result: LocalGenUiIntent.MergeApp) {
        val pending = candidate ?: return
        if (pending.app.id != result.id || pending.app.sourceRevision != result.revision ||
            pending.app.baseSource == null || pending.app.reopening || pending.mergedSource != null) return
        if (result.mergedSource == null) {
            rejectCandidate(pending, listOf(LocalGenUiCheck("merge", LocalGenUiCheckResult.FAILED,
                "the edit patch did not produce a runnable program")), LocalGenUiFailure.INVALID_RESPONSE)
            return
        }
        pending.mergedSource = result.mergedSource
        try {
            stageCandidate(pending, pending.app.copy(source = result.mergedSource, baseSource = null))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            endVerification()
            restoreApp(pending.app.id, LocalGenUiFailure.STORAGE)
            return
        }
        publish(stateFlow.value)
        reviewChecker(pending)
    }

    private suspend fun reviewChecker(pending: Candidate) {
        val probe = pending.probe ?: return
        val source = pending.mergedSource ?: return
        if (probe.checks.any { it.result == LocalGenUiCheckResult.FAILED } || probe.checks.count { it.name == "actual-render" } != 1) {
            rejectCandidate(pending, probe.checks, LocalGenUiFailure.INVALID_RESPONSE)
            return
        }
        val previous = library.apps.firstOrNull { it.id == pending.app.id }
        val state = migrateLocalGenUiState(previous, pending.initialValues, probe.stateTypes)
        if (state == null || previous?.sourceRevision != pending.ownerSourceRevision) {
            rejectCandidate(pending, probe.checks + LocalGenUiCheck("state-migration", LocalGenUiCheckResult.FAILED,
                "the candidate changes the schema of saved user state"), LocalGenUiFailure.STATE_MIGRATION_REQUIRED)
            return
        }
        val staged = pending.app.copy(source = source, stateJson = state.toString(), baseSource = null,
            stateRevision = previous?.let { it.stateRevision + 1 } ?: 0, userEdited = previous?.userEdited == true, reopening = true)
        val reopening = pending.copy(app = staged, probe = null, ownerStateRevision = previous?.stateRevision)
        endVerification()
        try {
            saveReview(staged.id, reviewOf(pending).copy(checks = probe.checks, staged = staged, resume = reopening.resumeData()))
            val readback = withContext(Dispatchers.Default) {
                storage.load(LIBRARY)?.let { json.decodeFromString<LocalGenUiLibrary>(it) }?.reviews?.get(staged.id)?.staged
            }
            if (readback != staged) {
                rejectCandidate(pending, probe.checks + LocalGenUiCheck("save-reopen", LocalGenUiCheckResult.FAILED,
                    "owner readback differs from the staged candidate"), LocalGenUiFailure.STORAGE)
                return
            }
            awaitVerification(reopening.copy(app = readback))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            restoreApp(staged.id, LocalGenUiFailure.STORAGE)
        }
    }

    private fun reviewOf(pending: Candidate): LocalGenUiReview {
        val app = pending.app
        val previous = library.reviews[app.id] ?: LocalGenUiReview(app.sessionId)
        return previous.copy(revision = app.sourceRevision)
    }

    private fun Candidate.resumeData() =
        LocalGenUiReviewResume(text, initialValues, ownerSourceRevision, ownerStateRevision, recordOutcome, replyAtMillis)

    private suspend fun stageCandidate(pending: Candidate, staged: LocalGenUiApp) {
        if (pending.recordOutcome && staged.baseSource == null) {
            val session = library.sessions.firstOrNull { it.id == staged.sessionId }
            pending.replyAtMillis = pending.replyAtMillis ?: maxOf(nowMillis(), session?.updatedAtMillis ?: Long.MIN_VALUE)
        }
        saveReview(staged.id, reviewOf(pending).copy(checks = emptyList(), staged = staged, resume = pending.resumeData()))
    }

    private suspend fun saveReview(id: String, review: LocalGenUiReview) {
        save(library.copy(reviews = library.reviews + (id to review)))
    }

    private suspend fun rejectCandidate(pending: Candidate, checks: List<LocalGenUiCheck>, reason: LocalGenUiFailure) {
        val app = pending.app
        val previous = library.apps.firstOrNull { it.id == app.id && !it.failedValidation }
        val review = reviewOf(pending).copy(checks = checks, staged = null, resume = null)
        val source = pending.mergedSource
        val original = pending.request
        val repair = if (original != null && reason == LocalGenUiFailure.INVALID_RESPONSE && !app.reopening && source != null) {
            review.nextRepair(source, app.stateJson)
        } else null
        val failed = if (source != null && previous == null && reason == LocalGenUiFailure.INVALID_RESPONSE) {
            app.copy(source = source, streaming = false, checking = false, reopening = false,
                baseSource = null, failedValidation = true, inGallery = false)
        } else null
        val card = (previous ?: failed)?.takeIf { source != null && reason != LocalGenUiFailure.STORAGE }
        val messageFailure = reason.takeIf { card == null || it == LocalGenUiFailure.STATE_MIGRATION_REQUIRED }
        val reply = LocalGenUiMessage("assistant", pending.text, card?.id, pending.replyAtMillis,
            appGenerationFailed = failed != null, appTitle = app.title.takeIf { card != null }, failure = messageFailure)
        endVerification()
        try {
            if (repair == null || source == null || original == null) {
                if (failed != null || pending.recordOutcome) {
                    persistReply(app.sessionId, reply, failed, app.id to review)
                    restoreApp(app.id, messageFailure)
                } else {
                    saveReview(app.id, review)
                    restoreApp(app.id, reason)
                }
            } else {
                val repairRevision = app.sourceRevision + 1
                val reserved = review.copy(revision = repairRevision, repairs = review.repairs + repair.key)
                // The failed attempt, repair notice and budget are saved together before calling the model.
                persistReply(app.sessionId, reply, failed, app.id to reserved, scheduleRepair = true)
                publish(stateFlow.value.copy(busy = true, repairing = true, streamingText = "", failure = null,
                    openApp = if (showGeneratedApp) previous ?: app.copy(streaming = true, checking = false) else null))
                val history = if (original.repairing) original.messages.dropLast(1) else original.messages
                streamTurn(original.copy(revision = repairRevision,
                    messages = history + ModelProviderMessage("user", repair.prompt), editBase = source,
                    repairing = true))
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            restoreApp(app.id, LocalGenUiFailure.STORAGE)
        }
    }

    private fun endVerification() {
        candidate = null
        checkTimeout?.cancel()
        checkTimeout = null
    }

    private suspend fun finishTurn(
        session: String, text: String, app: LocalGenUiApp?, review: LocalGenUiReview? = null, replyAtMillis: Long? = null,
    ) {
        if (text.isBlank() && app == null) {
            failure(LocalGenUiFailure.INVALID_RESPONSE)
            return
        }
        persistReply(session, LocalGenUiMessage("assistant", text, app?.id, replyAtMillis, appTitle = app?.title),
            app, if (app != null && review != null) app.id to review else null)
        val current = stateFlow.value
        val visibleApp = if (showGeneratedApp || (app != null && current.openApp?.id == app.id)) app else current.openApp
        publish(current.copy(openApp = visibleApp))
    }

    private suspend fun persistReply(
        session: String, reply: LocalGenUiMessage, app: LocalGenUiApp? = null,
        review: Pair<String, LocalGenUiReview>? = null, scheduleRepair: Boolean = false,
    ) {
        val now = nowMillis()
        save(library.copy(
            apps = if (app == null) library.apps else library.apps.filterNot { it.id == app.id } + app,
            reviews = if (review == null) library.reviews else library.reviews + review,
            sessions = library.sessions.map { conversation ->
                if (conversation.id != session) conversation else {
                    val timestamp = maxOf(now, conversation.updatedAtMillis ?: conversation.createdAtMillis ?: Long.MIN_VALUE)
                    val messages = conversation.messages + reply.copy(createdAtMillis = reply.createdAtMillis ?: timestamp)
                    conversation.copy(
                        title = conversation.titleAfterApp(reply.appTitle),
                        messages = if (scheduleRepair) {
                            messages + LocalGenUiMessage("user", "", createdAtMillis = timestamp, automaticRepair = true)
                        } else messages,
                        updatedAtMillis = timestamp,
                    )
                }
            },
        ))
    }

    private fun cancel() {
        generation++
        turn?.cancel()
        endVerification()
        finishBusy()
    }

    private suspend fun discardVerification() {
        val pending = candidate?.app
        if (pending != null) {
            val review = library.reviews[pending.id]
            if (review?.staged?.sourceRevision == pending.sourceRevision) {
                saveReview(pending.id, review.copy(staged = null, resume = null))
            }
        }
        cancel()
    }

    private suspend fun saveAppState(intent: LocalGenUiIntent.SaveAppState) {
        val app = stateFlow.value.openApp ?: return
        if (app.id != intent.id || app.sourceRevision != intent.sourceRevision || app.streaming || app.checking || app.failedValidation) return
        val conflict = app.stateRevision != intent.baseStateRevision
        if (!conflict && intent.stateJson.length <= MAX_JSON && jsonObject(intent.stateJson) != null) {
            updateApp(app.id) { it.copy(stateRevision = it.stateRevision + 1, stateJson = intent.stateJson, userEdited = true) }
        }
        val current = stateFlow.value
        publish(current.copy(stateWriteSerial = current.stateWriteSerial + 1, stateWriteConflict = conflict))
    }

    private suspend fun updateApp(id: String, update: (LocalGenUiApp) -> LocalGenUiApp) {
        val app = library.apps.firstOrNull { it.id == id && !it.failedValidation } ?: return
        val revised = update(app)
        if (app != revised) {
            val order = if (!app.inGallery && revised.inGallery) listOf(id) + library.galleryOrder else library.galleryOrder
            save(library.copy(apps = library.apps.map { if (it.id == id) revised else it }, galleryOrder = order))
        }
        // Always acknowledge a CAS, including conflicts and idempotent writes.
        val current = stateFlow.value
        publish(current.copy(openApp = current.openApp?.let { if (it.id == id) revised else it }))
    }

    private fun publish(state: LocalGenUiState) {
        val pendingReviews = library.reviews.values.filter { it.staged != null }.associateBy { it.sessionId }
        val session = library.sessions.firstOrNull { showConversation && it.id == activeSessionId }
            ?.let { sessionWithCandidateCard(it, pendingReviews[it.id]) }
        val history = library.sessions.filter {
            it.id != library.unsentSessionId &&
                (it.title.isNotBlank() || it.messages.isNotEmpty() || !library.drafts[it.id].isNullOrBlank())
        }.sortedByDescending { it.updatedAtMillis ?: it.createdAtMillis ?: Long.MIN_VALUE }
            .map { sessionWithCandidateCard(it, pendingReviews[it.id]) }
        val appsById = library.apps.associateBy { it.id }
        stateFlow.value = state.copy(
            sessions = history, apps = library.apps, models = models.map(LocalGenUiModel::ui),
            checkingApp = candidate?.app,
            selectedSession = session, activeSessionId = activeSessionId, selectedModelId = session?.modelId,
            draft = session?.id?.let(library.drafts::get).orEmpty(),
            galleryApps = library.galleryOrder.mapNotNull(appsById::get),
        )
    }

    private fun sessionWithCandidateCard(session: LocalGenUiSession, review: LocalGenUiReview?): LocalGenUiSession {
        // The staged review owns the in-progress reply until its outcome is committed to the transcript.
        val staged = review?.staged ?: return session
        val resume = review.resume ?: return session
        if (!resume.recordOutcome || staged.baseSource != null) return session
        val pending = LocalGenUiMessage("assistant", resume.text, staged.id, resume.replyAtMillis ?: session.updatedAtMillis,
            appTitle = staged.title, preparingApp = true)
        return session.copy(title = session.titleAfterApp(staged.title), messages = session.messages + pending)
    }

    private fun LocalGenUiSession.titleAfterApp(appTitle: String?): String =
        appTitle?.takeIf { !titleEdited && messages.none { it.appId != null } } ?: title

    private suspend fun save(next: LocalGenUiLibrary) {
        val normalized = next.withGalleryOrder()
        withContext(Dispatchers.Default) { storage.save(LIBRARY, json.encodeToString(normalized)) }
        library = normalized
    }

    private fun failure(reason: LocalGenUiFailure) = publish(stateFlow.value.copy(failure = reason))

    private fun Exception.failure(): LocalGenUiFailure = when ((this as? ModelProviderException)?.failure) {
        ModelProviderFailure.Authentication -> LocalGenUiFailure.AUTHENTICATION
        ModelProviderFailure.RateLimited -> LocalGenUiFailure.RATE_LIMIT
        ModelProviderFailure.InvalidResponse -> LocalGenUiFailure.INVALID_RESPONSE
        else -> LocalGenUiFailure.NETWORK
    }

    public companion object {
        private const val LIBRARY = "local-genui:library"
        private const val MODELS = "local-genui:models"
        private const val REPAIR_EDIT_MODE = "\nFor this automatic repair, the GenerativeUI source string contains only the changed statements. Preserve unchanged statements and reuse existing names; the host merges the patch with the failed source."
        private val Whitespace = Regex("\\s+")
        private const val HOST_CAPABILITIES =
            "\nThis host supports local document state, assistant follow-up, managing events in the OpenBitFun calendar, haptics and orientation. " +
                "Photo search, pinned Fluent Emoji and front-camera gestures are available. CrossDeviceImage supports photo, scan and gallery by a one-time code between OpenBitFun phones on the same local network. " +
                "Use components that work with the available capabilities."
        internal const val MAX_JSON = 512 * 1024
        @OptIn(ExperimentalUuidApi::class)
        internal fun id(): String = "local-genui:${Uuid.random()}"
        internal fun jsonObject(value: String): JsonObject? = runCatching { Json.parseToJsonElement(value) as? JsonObject }.getOrNull()
    }
}

private class LocalGenUiTurn {
    private data class Tool(var name: String? = null, val arguments: StringBuilder = StringBuilder())
    data class App(val title: String, val source: String, val values: JsonObject)

    private val assistant = StringBuilder()
    private val tools = mutableMapOf<Int, Tool>()
    private var complete = false
    val text: String get() = assistant.toString()

    fun accept(frame: GenUiProviderFrame) {
        when (frame) {
            is GenUiProviderFrame.Text -> {
                if (assistant.length + frame.delta.length > LocalGenUiStore.MAX_JSON) invalid()
                assistant.append(frame.delta)
            }
            is GenUiProviderFrame.Tool -> {
                if (frame.index !in 0..31) invalid()
                val tool = tools.getOrPut(frame.index) { Tool() }
                if (tool.arguments.length + frame.arguments.length > LocalGenUiStore.MAX_JSON) invalid()
                frame.name?.takeIf(String::isNotBlank)?.let { tool.name = it }
                tool.arguments.append(frame.arguments)
            }
            is GenUiProviderFrame.Stop -> {
                if (frame.reason in setOf("length", "max_tokens", "content_filter")) invalid()
                complete = true
            }
        }
    }

    fun preview(editing: Boolean): App? {
        val tool = tools.values.singleOrNull { it.name == "GenerativeUI" } ?: return null
        val args = tool.arguments.toString()
        val source = partialString(args, "source") ?: return null
        if (!source.contains('=') || (!editing && !ROOT_STATEMENT.containsMatchIn(source))) return null
        return App(partialString(args, "title").orEmpty(), source, JsonObject(emptyMap()))
    }

    fun result(editing: Boolean): App? {
        if (!complete) invalid()
        val tool = tools.values.singleOrNull { it.name == "GenerativeUI" }
        if (tool == null) {
            if (tools.isNotEmpty()) invalid()
            return null
        }
        val parsed = LocalGenUiStore.jsonObject(tool.arguments.toString()) ?: invalid()
        val title = (parsed["title"] as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
        val source = (parsed["source"] as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
        if (title.isEmpty() || source.isEmpty() || (!editing && !ROOT_STATEMENT.containsMatchIn(source))) invalid()
        return App(title.take(120), source, parsed["values"] as? JsonObject ?: JsonObject(emptyMap()))
    }

    private companion object {
        val ROOT_STATEMENT = Regex("""(?m)^root\s*=""")
    }

    private fun invalid(): Nothing = throw ModelProviderException(ModelProviderFailure.InvalidResponse)
}

/** Reads a top-level string without consuming an incomplete escape or a nested value. */
private fun partialString(input: String, field: String): String? {
    var depth = 0
    var cursor = 0
    while (cursor < input.length) {
        when (input[cursor]) {
            '{', '[' -> depth++
            '}', ']' -> depth--
            '"' -> {
                val start = cursor
                cursor = stringEnd(input, cursor + 1)
                if (cursor == input.length) return null
                if (depth == 1 && input.substring(start + 1, cursor) == field) {
                    val separator = input.indexOfFirstAfter(cursor + 1) { !it.isWhitespace() }
                    if (separator < 0) return null
                    if (input[separator] == ':') {
                        val value = input.indexOfFirstAfter(separator + 1) { !it.isWhitespace() }
                        if (value < 0 || input[value] != '"') return null
                        val end = stringEnd(input, value + 1)
                        val prefix = input.substring(value, end)
                        return safeStringPrefix(prefix)
                    }
                }
            }
        }
        cursor++
    }
    return null
}

private fun stringEnd(input: String, start: Int): Int {
    var index = start
    while (index < input.length) {
        if (input[index] == '"') return index
        index += if (input[index] == '\\' && index + 1 < input.length) 2 else 1
    }
    return index
}

private fun String.indexOfFirstAfter(start: Int, predicate: (Char) -> Boolean): Int {
    for (index in start until length) if (predicate(this[index])) return index
    return -1
}

private fun safeStringPrefix(prefix: String): String? {
    // A Unicode escape plus a high/low surrogate pair can span provider frames.
    // Trim at most that incomplete tail and wait for the next frame.
    for (tail in 0..minOf(12, prefix.length - 1)) {
        val decoded = runCatching { Json.decodeFromString<String>(prefix.dropLast(tail) + '"') }.getOrNull()
        if (decoded != null && decoded.lastOrNull()?.isHighSurrogate() != true) return decoded
    }
    return null
}
