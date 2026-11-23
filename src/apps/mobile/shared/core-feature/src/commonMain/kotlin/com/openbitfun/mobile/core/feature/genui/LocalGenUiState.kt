package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.domain.ModelLabelPolicy
import kotlinx.serialization.Serializable

@Serializable
public enum class LocalGenUiFailure {
    STORAGE, INVALID_MODEL, MISSING_MODEL, AUTHENTICATION, RATE_LIMIT, NETWORK, INVALID_RESPONSE, STATE_MIGRATION_REQUIRED,
    APP_MISSING,
}

@Serializable
public enum class LocalGenUiCheckResult { PASSED, FAILED, UNVERIFIED }

@Serializable
@ConsistentCopyVisibility
public data class LocalGenUiCheck internal constructor(
    public val name: String,
    public val result: LocalGenUiCheckResult,
    public val detail: String,
)

public data class LocalGenUiModelUi(
    public val id: String,
    public val name: String,
    public val endpoint: String,
    public val model: String,
    public val hasStoredKey: Boolean,
) {
    public val composerLabel: String
        get() = ModelLabelPolicy.primaryLabel(id, name, model, name)

    public val composerDetails: String
        get() = ModelLabelPolicy.secondaryLabel(id, name, model, provider = "local", fallback = name)
}

@Serializable
@ConsistentCopyVisibility
public data class LocalGenUiMessage internal constructor(
    public val role: String,
    public val text: String,
    public val appId: String? = null,
    public val createdAtMillis: Long? = null,
    public val appGenerationFailed: Boolean = false,
    public val appTitle: String? = null,
    public val automaticRepair: Boolean = false,
    public val failure: LocalGenUiFailure? = null,
    public val preparingApp: Boolean = false,
)

@Serializable
@ConsistentCopyVisibility
public data class LocalGenUiSession internal constructor(
    public val id: String,
    public val title: String,
    public val modelId: String? = null,
    public val messages: List<LocalGenUiMessage> = emptyList(),
    public val createdAtMillis: Long? = null,
    public val updatedAtMillis: Long? = null,
    internal val titleEdited: Boolean = false,
)

@Serializable
@ConsistentCopyVisibility
public data class LocalGenUiApp internal constructor(
    public val id: String,
    public val sessionId: String,
    public val title: String,
    public val source: String,
    public val sourceRevision: Int,
    public val stateRevision: Int = 0,
    public val stateJson: String = "{}",
    public val inGallery: Boolean = false,
    public val streaming: Boolean = false,
    public val checking: Boolean = false,
    public val baseSource: String? = null,
    public val calendarReceipts: List<String> = emptyList(),
    public val reopening: Boolean = false,
    internal val userEdited: Boolean = stateRevision > 0,
    public val failedValidation: Boolean = false,
)

/** Native hosts observe local data and never receive provider credentials. */
@ConsistentCopyVisibility
public data class LocalGenUiState internal constructor(
    public val sessions: List<LocalGenUiSession> = emptyList(),
    public val apps: List<LocalGenUiApp> = emptyList(),
    public val models: List<LocalGenUiModelUi> = emptyList(),
    public val selectedSession: LocalGenUiSession? = null,
    public val activeSessionId: String? = null,
    public val openApp: LocalGenUiApp? = null,
    public val checkingApp: LocalGenUiApp? = null,
    public val streamingText: String = "",
    public val draft: String = "",
    public val busy: Boolean = false,
    public val repairing: Boolean = false,
    public val recovering: Boolean = false,
    public val loading: Boolean = true,
    public val failure: LocalGenUiFailure? = null,
    public val selectedModelId: String? = null,
    public val modelWriteSerial: Int = 0,
    public val writingModel: Boolean = false,
    public val modelWriteFailure: LocalGenUiFailure? = null,
    public val draftAcceptedSerial: Int = 0,
    public val discoveringModels: Boolean = false,
    public val discoveredModels: List<String> = emptyList(),
    public val modelDiscoveryFailure: LocalGenUiFailure? = null,
    public val stateWriteSerial: Int = 0,
    public val stateWriteConflict: Boolean = false,
    public val galleryApps: List<LocalGenUiApp> = emptyList(),
)

public sealed interface LocalGenUiIntent {
    public data object Reload : LocalGenUiIntent
    public data object NewSession : LocalGenUiIntent
    public data object Back : LocalGenUiIntent
    public data object Cancel : LocalGenUiIntent
    public data class Send(
        public val sessionId: String,
        public val draftAcceptedSerial: Int,
        public val text: String,
    ) : LocalGenUiIntent
    public data object Close : LocalGenUiIntent
    public data object CancelModelDiscovery : LocalGenUiIntent
    public data object ResetModelEditor : LocalGenUiIntent
    public data class EditDraft(
        public val sessionId: String,
        public val draftAcceptedSerial: Int,
        public val text: String,
    ) : LocalGenUiIntent
    public data class OpenSession(public val id: String) : LocalGenUiIntent
    public data class DeleteSession(public val id: String) : LocalGenUiIntent
    public data class RenameSession(public val id: String, public val title: String) : LocalGenUiIntent
    public data class SelectModel(public val id: String) : LocalGenUiIntent
    public data class DeleteModel(public val id: String) : LocalGenUiIntent
    public data class UseModelForSetup(public val id: String) : LocalGenUiIntent
    public data class OpenApp(public val id: String) : LocalGenUiIntent
    public data class SetGallery(public val id: String, public val added: Boolean) : LocalGenUiIntent
    public data class ContinueConversation(public val appId: String, public val sourceRevision: Int, public val message: String) : LocalGenUiIntent
    public data class SaveAppState(
        public val id: String,
        public val sourceRevision: Int,
        public val baseStateRevision: Int,
        public val stateJson: String,
    ) : LocalGenUiIntent

    public data class RecordCalendarReceipt(
        public val id: String,
        public val receipt: String,
    ) : LocalGenUiIntent

    public data class VerifyApp(
        public val id: String,
        public val revision: Int,
        public val reopening: Boolean,
        public val checks: List<LocalGenUiCheck>,
        public val stateTypes: Map<String, String>,
    ) : LocalGenUiIntent

    public data class MergeApp(
        public val id: String,
        public val revision: Int,
        public val mergedSource: String?,
    ) : LocalGenUiIntent

    public class DiscoverModels(
        public val id: String?,
        public val endpoint: String,
        public val apiKey: String,
    ) : LocalGenUiIntent {
        override fun toString(): String = "DiscoverModels"
    }

    public class SaveModel(
        public val id: String?,
        public val name: String,
        public val endpoint: String,
        public val model: String,
        public val apiKey: String,
        public val useForSession: Boolean,
    ) : LocalGenUiIntent {
        override fun toString(): String = "SaveModel"
    }
}
