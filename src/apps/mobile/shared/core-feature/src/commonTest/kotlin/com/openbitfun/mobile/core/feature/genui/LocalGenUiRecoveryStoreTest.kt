package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.persistence.DraftStore
import com.openbitfun.mobile.core.persistence.SecureStore
import com.openbitfun.mobile.core.transport.GenUiProviderStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LocalGenUiRecoveryStoreTest {
    private val previous = LocalGenUiApp(
        "app", "session", "Counter", """root = Page([Text("Before")])""", sourceRevision = 1,
        stateRevision = 2, stateJson = """{"count":1}""",
    )
    private val staged = previous.copy(source = """root = Page([Text("After")])""", sourceRevision = 2, checking = true)
    private val session = LocalGenUiSession(
        "session", "Counter", messages = listOf(LocalGenUiMessage("assistant", "Created", "app")),
    )

    @Test
    fun reportsAMissingAppWithoutCreatingALibraryEntry() = runTest {
        val store = open(backgroundScope, CheckpointDrafts("{}"), LocalGenUiIntent.OpenApp("missing"))
        val unavailable = store.state.first { it.failure == LocalGenUiFailure.APP_MISSING }
        assertNull(unavailable.openApp)
        assertNull(unavailable.checkingApp)
        assertTrue(unavailable.apps.isEmpty())
    }

    @Test
    fun galleryUsesAdditionOrderAcrossEditsAndRestarts() = runTest {
        val first = previous.copy(inGallery = true)
        val second = previous.copy(id = "second", sessionId = "other", inGallery = true)
        val unlisted = previous.copy(id = "new", sessionId = "other")
        val drafts = checkpoint(first, staged, additionalApps = listOf(second, unlisted))
        val store = open(backgroundScope, drafts, LocalGenUiIntent.Reload)
        assertEquals(listOf(first, second), store.state.value.galleryApps)

        store.dispatch(LocalGenUiIntent.SetGallery("new", true))
        val added = store.state.first { it.galleryApps.size == 3 }
        assertEquals(listOf("new", "app", "second"), added.galleryApps.map { it.id })
        store.dispatch(LocalGenUiIntent.SetGallery("second", true))
        store.dispatch(LocalGenUiIntent.OpenApp("app"))
        store.state.first { it.recovering }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, false, listOf(passed("actual-render")), mapOf("count" to "number")))
        store.state.first { it.checkingApp?.reopening == true }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, true, listOf(passed("save-reopen")), emptyMap()))
        val edited = store.state.first { !it.busy && it.apps.lastOrNull()?.sourceRevision == 2 }
        assertEquals(listOf("new", "app", "second"), edited.galleryApps.map { it.id })
        assertEquals(2, edited.galleryApps[1].sourceRevision)

        store.dispatch(LocalGenUiIntent.SetGallery("app", false))
        assertEquals(listOf("new", "second"), store.state.first { it.galleryApps.size == 2 }.galleryApps.map { it.id })
        store.dispatch(LocalGenUiIntent.SetGallery("app", true))
        store.state.first { it.galleryApps.firstOrNull()?.id == "app" }
        val restarted = open(backgroundScope, drafts, LocalGenUiIntent.Reload)
        assertEquals(listOf("app", "new", "second"), restarted.state.value.galleryApps.map { it.id })

        restarted.dispatch(LocalGenUiIntent.DeleteSession("session"))
        assertEquals(listOf("new", "second"), restarted.state.first { it.galleryApps.size == 2 }.galleryApps.map { it.id })
    }

    @Test
    fun resumesBothStagesAndPublishesExactlyOneReply() = runTest {
        val drafts = checkpoint(previous, staged)
        val first = open(backgroundScope, drafts)
        assertEquals(previous, first.state.first { it.recovering }.openApp)
        first.dispatch(LocalGenUiIntent.VerifyApp("app", 2, false, listOf(passed("actual-render")), mapOf("count" to "number")))
        val reopening = assertNotNull(first.state.first { it.checkingApp?.reopening == true }.checkingApp)
        assertEquals(previous.stateJson, reopening.stateJson)

        val second = open(backgroundScope, drafts)
        assertEquals(reopening, second.state.first { it.recovering }.checkingApp)
        second.dispatch(LocalGenUiIntent.VerifyApp("app", 2, true, listOf(passed("save-reopen")), emptyMap()))
        val committed = second.state.first { !it.busy && it.apps.singleOrNull()?.sourceRevision == 2 }
        assertEquals(previous.stateJson, committed.apps.single().stateJson)
        assertEquals(listOf("Created", "Updated"), committed.sessions.single().messages.map { it.text })
        assertEquals(listOf("used repair"), drafts.review().repairs)
        assertNull(drafts.review().staged)
        assertNull(drafts.review().resume)

        val third = open(backgroundScope, drafts)
        assertEquals(2, third.state.first { it.openApp != null }.sessions.single().messages.size)
        assertNull(third.state.value.checkingApp)
    }

    @Test
    fun rejectsAStagedStateWhenItsAcceptedOwnerChanged() = runTest {
        val edited = previous.copy(stateRevision = 3, stateJson = """{"count":2}""")
        val drafts = checkpoint(edited, staged.copy(reopening = true, stateRevision = 3))
        val store = open(backgroundScope, drafts)
        val result = store.state.first { it.failure == LocalGenUiFailure.STATE_MIGRATION_REQUIRED }
        assertEquals(edited, result.openApp)
        assertEquals(listOf(edited), result.apps)
        assertEquals(session.messages, result.sessions.single().messages)
        assertNull(drafts.review().staged)
        assertTrue(drafts.review().checks.any { it.name == "state-migration" && it.result == LocalGenUiCheckResult.FAILED })
    }

    @Test
    fun explicitCancellationRemovesTheCheckpoint() = runTest {
        val drafts = checkpoint(previous, staged, recordOutcome = true)
        val store = open(backgroundScope, drafts)
        val pending = store.state.first { it.recovering }
        assertTrue(pending.sessions.single().messages.last().preparingApp)
        store.dispatch(LocalGenUiIntent.Cancel)
        val cancelled = store.state.first { !it.busy }
        assertEquals(listOf(previous), cancelled.apps)
        assertEquals(session.messages, cancelled.sessions.single().messages)
        assertNull(drafts.review().staged)
        assertNull(drafts.review().resume)
    }

    @Test
    fun candidateCardOpensActiveVerificationAndUpdatesInPlace() = runTest {
        val reopening = staged.copy(reopening = true, stateRevision = 3)
        val drafts = checkpoint(previous, reopening, checks = listOf(passed("actual-render")),
            recordOutcome = true, replyAtMillis = 1234L)
        val store = open(backgroundScope, drafts, LocalGenUiIntent.OpenSession("session"))
        val checking = store.state.first { it.checkingApp?.reopening == true }
        val card = assertNotNull(checking.selectedSession).messages.last()
        assertEquals("Updated", card.text)
        assertEquals("app", card.appId)
        assertEquals(1234L, card.createdAtMillis)
        assertTrue(card.preparingApp)
        assertEquals(previous, checking.apps.single())
        assertNull(checking.openApp)

        store.dispatch(LocalGenUiIntent.OpenApp("app"))
        assertEquals(reopening, store.state.first { it.openApp?.reopening == true }.openApp)
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, true, listOf(passed("save-reopen")), emptyMap()))
        val ready = store.state.first { !it.busy && it.apps.singleOrNull()?.sourceRevision == 2 }
        assertEquals(session.messages + card.copy(preparingApp = false), ready.selectedSession?.messages)
        assertNull(drafts.review().staged)
    }

    @Test
    fun renamedSessionKeepsItsTitleWhenTheFirstAppIsRecovered() = runTest {
        val drafts = checkpoint(null, staged.copy(reopening = true, stateRevision = 0),
            session.copy(messages = listOf(LocalGenUiMessage("user", "Create a counter"))))
        val store = open(backgroundScope, drafts)
        val recovering = store.state.first { it.recovering || it.failure != null }
        assertNull(recovering.failure)
        store.dispatch(LocalGenUiIntent.RenameSession("session", "  My counter  "))
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, true, listOf(passed("save-reopen")), emptyMap()))
        val committed = store.state.first { !it.busy }
        assertNull(committed.failure)
        assertEquals(2, committed.apps.single().sourceRevision)
        assertEquals("My counter", committed.sessions.single().title)
    }

    @Test
    fun probeTimeoutsLeaveANewAppDisplayableWithoutConsumingRepairBudget() = runTest {
        val drafts = checkpoint(null, staged, session.copy(messages = emptyList()))
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        val committed = store.state.first { !it.busy }
        assertNull(committed.failure)
        assertEquals(staged.source, committed.apps.single().source)
        assertTrue(!committed.sessions.single().messages.single().appGenerationFailed)
        assertEquals(mapOf(
            "actual-render" to LocalGenUiCheckResult.UNVERIFIED,
            "host-shell" to LocalGenUiCheckResult.PASSED,
            "save-reopen" to LocalGenUiCheckResult.UNVERIFIED,
        ), drafts.review().checks.filter { it.name in setOf("actual-render", "host-shell", "save-reopen") }
            .associate { it.name to it.result })
        assertEquals(listOf("used repair"), drafts.review().repairs)
        assertNull(drafts.review().staged)

        val restarted = open(backgroundScope, drafts)
        assertEquals(committed.apps.single(), restarted.state.first { it.openApp != null }.openApp)
    }

    @Test
    fun missingReopenProbeKeepsMigratedUserData() = runTest {
        val edited = previous.copy(userEdited = true)
        val drafts = checkpoint(edited, staged)
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, false, listOf(passed("actual-render")), mapOf("count" to "number")))
        val committed = store.state.first { !it.busy }
        val updated = committed.apps.single()
        assertNull(committed.failure)
        assertEquals(staged.source, updated.source)
        assertEquals(edited.stateJson, updated.stateJson)
        assertTrue(updated.userEdited)
        assertEquals(LocalGenUiCheckResult.UNVERIFIED, drafts.review().checks.single { it.name == "save-reopen" }.result)
        assertEquals(listOf("used repair"), drafts.review().repairs)
    }

    @Test
    fun checkerTimeoutStillRequiresAKnownSchemaForSavedUserData() = runTest {
        val edited = previous.copy(userEdited = true)
        val drafts = checkpoint(edited, staged)
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        val result = store.state.first { !it.busy }
        assertEquals(LocalGenUiFailure.STATE_MIGRATION_REQUIRED, result.failure)
        assertEquals(edited, result.apps.single())
        assertEquals(session.messages, result.sessions.single().messages)
    }

    @Test
    fun aFailedReopenProbeKeepsThePreviousRevisionEvenWithUnverifiedChecks() = runTest {
        val drafts = checkpoint(previous, staged.copy(reopening = true, stateRevision = 3), checks = listOf(
            passed("actual-render"), LocalGenUiCheck("declared-interactions", LocalGenUiCheckResult.UNVERIFIED, "not executable"),
        ))
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, true,
            listOf(LocalGenUiCheck("save-reopen", LocalGenUiCheckResult.FAILED, "no visible content")), emptyMap()))
        val result = store.state.first { !it.busy }
        assertEquals(LocalGenUiFailure.INVALID_RESPONSE, result.failure)
        assertEquals(previous, result.apps.single())
        assertEquals(session.messages, result.sessions.single().messages)
    }

    @Test
    fun failedFirstVerificationLeavesAReopenableCardWithNoGalleryEntry() = runTest {
        val draftSession = session.copy(messages = listOf(LocalGenUiMessage("user", "Create a counter")))
        val drafts = checkpoint(null, staged.copy(reopening = false), draftSession)
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, false,
            listOf(LocalGenUiCheck("actual-render", LocalGenUiCheckResult.FAILED, "no visible content")), emptyMap()))
        val failed = store.state.first { !it.busy && it.openApp?.failedValidation == true }
        val app = assertNotNull(failed.openApp)
        assertEquals("app", app.id)
        assertTrue(!app.inGallery && !app.checking && !app.streaming)
        assertEquals("Updated", failed.sessions.single().messages.last().text)
        assertEquals("app", failed.sessions.single().messages.last().appId)
        assertTrue(failed.sessions.single().messages.last().appGenerationFailed)
        assertNull(drafts.review().staged)
        assertEquals(LocalGenUiCheckResult.FAILED, drafts.review().checks.single().result)

        val restarted = open(backgroundScope, drafts)
        val reopened = restarted.state.first { it.openApp?.failedValidation == true }
        assertEquals(app, reopened.openApp)
        assertEquals(2, reopened.sessions.single().messages.size)
        assertNull(reopened.checkingApp)
    }

    @Test
    fun recoveredRepairKeepsBothFailedCardsAndOneRepairNotice() = runTest {
        val firstFailure = previous.copy(failedValidation = true)
        val messages = listOf(
            LocalGenUiMessage("user", "Create a counter"),
            LocalGenUiMessage("assistant", "Initial attempt", "app", appGenerationFailed = true, appTitle = "Counter"),
            LocalGenUiMessage("user", "", automaticRepair = true),
        )
        val drafts = checkpoint(firstFailure, staged, session.copy(messages = messages), recordOutcome = true)
        val store = open(backgroundScope, drafts)
        store.state.first { it.recovering }
        store.dispatch(LocalGenUiIntent.VerifyApp("app", 2, false,
            listOf(LocalGenUiCheck("actual-render", LocalGenUiCheckResult.FAILED, "no visible content")), emptyMap()))
        val failed = store.state.first { !it.busy && it.apps.singleOrNull()?.sourceRevision == 2 }
        val transcript = failed.sessions.single().messages
        assertEquals(messages, transcript.dropLast(1))
        assertEquals(listOf("app", "app"), transcript.filter { it.appGenerationFailed }.map { it.appId })
        assertEquals("Counter", transcript.last().appTitle)
        assertEquals(listOf("used repair"), drafts.review().repairs)
        assertNull(drafts.review().staged)

        val restarted = open(backgroundScope, drafts)
        assertEquals(transcript, restarted.state.first { it.openApp != null }.sessions.single().messages)
    }

    private suspend fun open(
        scope: CoroutineScope, drafts: CheckpointDrafts, intent: LocalGenUiIntent = LocalGenUiIntent.OpenApp("app"),
    ): LocalGenUiStore {
        val store = LocalGenUiStore(scope, drafts, NoProfiles, "", "{}", GenUiProviderStream.create())
        store.state.first { !it.loading }
        store.dispatch(intent)
        return store
    }

    private fun checkpoint(
        app: LocalGenUiApp?, candidate: LocalGenUiApp, conversation: LocalGenUiSession = session,
        checks: List<LocalGenUiCheck> = emptyList(),
        recordOutcome: Boolean = false,
        replyAtMillis: Long? = null,
        additionalApps: List<LocalGenUiApp> = emptyList(),
    ): CheckpointDrafts {
        val review = LocalGenUiReview(
            "session", revision = candidate.sourceRevision, checks = checks, repairs = listOf("used repair"), staged = candidate,
            resume = LocalGenUiReviewResume("Updated", buildJsonObject {}, app?.let { previous.sourceRevision },
                app?.let { previous.stateRevision }, recordOutcome, replyAtMillis),
        )
        return CheckpointDrafts(buildJsonObject {
            put("apps", Json.encodeToJsonElement(listOfNotNull(app) + additionalApps))
            put("sessions", Json.encodeToJsonElement(listOf(conversation)))
            put("reviews", Json.encodeToJsonElement(mapOf("app" to review)))
        }.toString())
    }

    private fun passed(name: String) = LocalGenUiCheck(name, LocalGenUiCheckResult.PASSED, "verified")

    private class CheckpointDrafts(private var text: String) : DraftStore {
        override fun load(draftId: String): String? = text.takeIf { draftId == "local-genui:library" }
        override fun save(draftId: String, text: String) { this.text = text }
        override fun delete(draftId: String) = error("Unexpected deletion")

        fun review(): LocalGenUiReview {
            val reviews = Json.parseToJsonElement(text).jsonObject.getValue("reviews").jsonObject
            return Json.decodeFromJsonElement(reviews.getValue("app"))
        }
    }

    private object NoProfiles : SecureStore {
        override fun read(key: String): ByteArray? = null
        override fun write(key: String, value: ByteArray) = error("Unexpected profile write")
        override fun delete(key: String) = error("Unexpected profile deletion")
    }
}
