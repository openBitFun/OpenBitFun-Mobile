package com.openbitfun.mobile.core.feature.genui

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LocalGenUiReviewTest {
    @Test
    fun repairsOnlySourceDefectsWithDistinctDiagnosticsAndAPersistedBudget() {
        val render = LocalGenUiCheck("actual-render", LocalGenUiCheckResult.FAILED, "missing component")
        val boundary = LocalGenUiCheck("content-boundary", LocalGenUiCheckResult.FAILED, "right edge")
        val waiting = LocalGenUiCheck("actual-render", LocalGenUiCheckResult.UNVERIFIED, "timeout")
        val storage = LocalGenUiCheck("save-reopen", LocalGenUiCheckResult.FAILED, "owner readback failed")
        val review = LocalGenUiReview("session", checks = listOf(render, boundary, storage))
        val repair = assertNotNull(review.nextRepair("root = Page([])", "{}"))
        assertTrue(repair.prompt.contains("Failed OpenUI Lang source:\nroot = Page([])"))
        assertTrue(!repair.prompt.contains("owner readback failed"))
        val saved = Json.decodeFromString<LocalGenUiReview>(Json.encodeToString(review.copy(repairs = listOf(repair.key))))
        assertNull(saved.copy(checks = listOf(boundary, render)).nextRepair("root = Page([])", "{}"))
        assertNotNull(saved.copy(checks = listOf(render)).nextRepair("root = Page([])", "{}"))
        assertNull(saved.copy(repairs = saved.repairs + "another failure").nextRepair("root = Page([])", "{}"))
        assertNull(review.copy(checks = listOf(waiting, storage)).nextRepair("root = Page([])", "{}"))
    }

    @Test
    fun aRevisionPreservesEditedValuesAndRejectsRemovedOrRetypedKeys() {
        val app = LocalGenUiApp("app", "session", "Timer", "root = Page([])", 3, stateRevision = 2,
            stateJson = """{"count":12}""")
        val initial = assertNotNull(LocalGenUiStore.jsonObject("""{"count":0,"label":"Focus"}"""))
        val accepted = assertNotNull(migrateLocalGenUiState(app, initial, emptyMap()))
        assertEquals("12", accepted["count"].toString())
        assertEquals("\"Focus\"", accepted["label"].toString())
        val empty = assertNotNull(LocalGenUiStore.jsonObject("{}"))
        assertNull(migrateLocalGenUiState(app, empty, emptyMap()))
        assertNull(migrateLocalGenUiState(app, empty, mapOf("count" to "string")))
        assertEquals(initial, migrateLocalGenUiState(app.copy(userEdited = false), initial, emptyMap()))
    }
}
