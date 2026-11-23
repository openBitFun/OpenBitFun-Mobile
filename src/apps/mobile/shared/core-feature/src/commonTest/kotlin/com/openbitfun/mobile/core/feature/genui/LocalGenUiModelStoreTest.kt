package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.persistence.DraftStore
import com.openbitfun.mobile.core.persistence.SecureStore
import com.openbitfun.mobile.core.transport.GenUiProviderStream
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LocalGenUiModelStoreTest {
    @Test
    fun savingNewModelsChangesOnlyTheActiveBindingAndKeepsItsDraft() = runTest {
        val store = store()
        store.state.first { !it.loading }
        store.dispatch(LocalGenUiIntent.NewSession)
        val active = assertNotNull(store.state.first { it.selectedSession != null }.selectedSession).id
        store.dispatch(LocalGenUiIntent.EditDraft(active, 0, "Keep this draft"))
        store.dispatch(profile("Original"))
        val original = store.state.first { it.modelWriteSerial == 1 }.models.single().id
        store.dispatch(profile("Second"))
        val second = store.state.first { it.modelWriteSerial == 2 }
        val selected = second.models.last().id
        assertEquals(selected, second.selectedModelId)

        store.dispatch(profile("Renamed", original, ""))
        assertEquals(selected, store.state.first { it.modelWriteSerial == 3 }.selectedModelId)
        store.dispatch(LocalGenUiIntent.DeleteModel(selected))
        val removed = store.state.first { it.modelWriteSerial == 4 }
        assertFalse(removed.models.any { it.id == removed.selectedModelId })
        store.dispatch(LocalGenUiIntent.UseModelForSetup(original))
        val restored = store.state.first { it.modelWriteSerial == 5 }
        assertEquals(original, restored.selectedModelId)
        assertEquals(active, restored.selectedSession?.id)
        assertEquals("Keep this draft", restored.draft)
    }

    @Test
    fun blankKeyCanOnlyReuseCredentialsForTheSameEndpoint() = runTest {
        val store = store()
        store.state.first { !it.loading }
        store.dispatch(profile("Original"))
        val original = store.state.first { it.modelWriteSerial == 1 }.models.single()
        assertTrue(original.hasStoredKey)
        store.dispatch(LocalGenUiIntent.SaveModel(original.id, "Different host", "https://other.invalid", "test-model", "", false))
        val refused = store.state.first { it.modelWriteFailure != null }
        assertEquals(LocalGenUiFailure.INVALID_MODEL, refused.modelWriteFailure)
        assertEquals(URL, refused.models.single().endpoint)
        store.dispatch(LocalGenUiIntent.SaveModel(original.id, "Renamed", "$URL/", "test-model", "", false))
        val updated = store.state.first { it.modelWriteSerial == 2 }
        assertEquals("Renamed", updated.models.single().name)
        assertEquals(original.id, updated.models.single().id)
    }

    @Test
    fun unsuccessfulPinRollsBackTheNewProfileAndKeepsTheDraft() = runTest {
        val drafts = MemoryDrafts()
        val store = store(drafts)
        store.state.first { !it.loading }
        store.dispatch(LocalGenUiIntent.NewSession)
        val active = assertNotNull(store.state.first { it.selectedSession != null }.selectedSession).id
        store.dispatch(LocalGenUiIntent.EditDraft(active, 0, "Draft kept on disk"))
        store.state.first { it.draft.isNotBlank() }
        drafts.refuseWrites = true
        store.dispatch(profile("Unavailable"))
        val failed = store.state.first { it.modelWriteFailure != null }
        assertEquals(LocalGenUiFailure.STORAGE, failed.modelWriteFailure)
        assertEquals(0, failed.modelWriteSerial)
        assertTrue(failed.models.isEmpty())
        assertEquals("Draft kept on disk", failed.draft)
    }

    @Test
    fun historySortsByActivityWhilePreservingOlderUntimedRecordsAndWorkingDrafts() = runTest {
        val drafts = MemoryDrafts("""
            {"sessions":[
                {"id":"old","title":"Older creation"},
                {"id":"newer","title":"Newer creation","createdAtMillis":300,"updatedAtMillis":300},
                {"id":"revisited","title":"Revisited creation","createdAtMillis":100,"updatedAtMillis":400},
                {"id":"empty","title":""}, {"id":"old-draft","title":""}
            ],"drafts":{"old-draft":"Previous version draft"}}
        """.trimIndent())
        val expected = listOf("revisited", "newer", "old", "old-draft")
        val store = store(drafts)
        assertEquals(expected, store.state.first { !it.loading }.sessions.map { it.id })
        store.dispatch(LocalGenUiIntent.NewSession)
        val pending = assertNotNull(store.state.first { it.selectedSession != null }.selectedSession).id
        store.dispatch(LocalGenUiIntent.EditDraft(pending, 0, "New working draft"))
        store.state.first { it.draft == "New working draft" }
        store.dispatch(LocalGenUiIntent.Back)
        assertEquals(expected, store.state.first { it.selectedSession == null }.sessions.map { it.id })

        val reopened = store(drafts)
        reopened.state.first { !it.loading }
        reopened.dispatch(LocalGenUiIntent.NewSession)
        val resumed = reopened.state.first { it.selectedSession != null }
        assertEquals(pending, resumed.selectedSession?.id)
        assertEquals("New working draft", resumed.draft)
        reopened.dispatch(LocalGenUiIntent.OpenSession("older-missing"))
        reopened.dispatch(LocalGenUiIntent.OpenSession("old-draft"))
        assertEquals("Previous version draft", reopened.state.first { it.selectedSession?.id == "old-draft" }.draft)
        reopened.dispatch(LocalGenUiIntent.Back)
        assertEquals("old-draft", reopened.state.first { it.selectedSession == null }.activeSessionId)
        reopened.dispatch(LocalGenUiIntent.DeleteSession("revisited"))
        val remaining = reopened.state.first { it.sessions.none { session -> session.id == "revisited" } }
        assertEquals(expected.drop(1), remaining.sessions.map { it.id })
        assertEquals(null, remaining.sessions.first { it.id == "old" }.updatedAtMillis)
    }

    private fun TestScope.store(drafts: DraftStore = MemoryDrafts()): LocalGenUiStore {
        return LocalGenUiStore(backgroundScope, drafts, MemorySecrets(), "", "{}", GenUiProviderStream.create())
    }

    private fun profile(name: String, id: String? = null, key: String = "test-key") =
        LocalGenUiIntent.SaveModel(id, name, URL, "test-model", key, false)

    private class MemoryDrafts(private var record: String? = null) : DraftStore {
        var refuseWrites = false
        override fun load(draftId: String) = record
        override fun save(draftId: String, text: String) {
            check(!refuseWrites)
            record = text
        }
        override fun delete(draftId: String) { record = null }
    }

    private class MemorySecrets : SecureStore {
        private var record: ByteArray? = null
        override fun read(key: String) = record?.copyOf()
        override fun write(key: String, value: ByteArray) { record = value.copyOf() }
        override fun delete(key: String) { record = null }
    }

    private companion object { const val URL = "https://fixture.invalid/v1" }
}
