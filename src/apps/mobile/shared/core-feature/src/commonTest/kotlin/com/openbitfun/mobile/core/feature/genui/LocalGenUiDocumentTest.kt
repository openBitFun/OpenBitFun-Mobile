package com.openbitfun.mobile.core.feature.genui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class LocalGenUiDocumentTest {
    private val app = LocalGenUiApp("local-genui:test", "local-genui:session", "Test", "root = Page([])", 4)
    private val catalog = """{"designSpec":{"shell":{"contentInsets":{"left":16,"right":16}}}}"""

    private fun read(message: String, mounted: LocalGenUiApp = app) = LocalGenUiDocument.readIntent(message, mounted, catalog)

    @Test
    fun aStateWriteBelongsToTheMountedAppAndSource() {
        val message = """{"type":"state","appId":"local-genui:test","sourceRevision":4,"baseStateRevision":2,"state":{"done":true}}"""
        val intent = assertIs<LocalGenUiIntent.SaveAppState>(read(message))
        assertEquals(2, intent.baseStateRevision)
        assertEquals("""{"done":true}""", intent.stateJson)

        assertNull(read(message, app.copy(sourceRevision = 5)))
        assertNull(read(message, app.copy(id = "local-genui:other")))
        assertNull(read(message, app.copy(streaming = true)))
    }

    @Test
    fun genericDocumentMessagesCannotInvokeNativeActions() {
        val message = """{"type":"action","appId":"local-genui:test","sourceRevision":4,"action":"OpenUrl","message":"https://example.org"}"""
        assertNull(read(message))
        val supported = message.replace("\"OpenUrl\"", "\"continue_conversation\"").replace("https://example.org", "Make it blue")
        assertEquals(
            "Make it blue",
            assertIs<LocalGenUiIntent.ContinueConversation>(read(supported)).message,
        )
    }
    @Test
    fun candidateRequiresAVisibleRenderWithoutOverflow() {
        val checking = app.copy(checking = true)
        val probe = """{"type":"probe_result","report":{"requestId":"validate:local-genui:test:4","appId":"local-genui:test","sourceRevision":4,"contractOk":true,"renderErrors":[],"visibleElements":6,"hostPartsInDocument":0,"viewport":{"width":360},"canvasWidth":360,"canvasScale":1,"contentBounds":{"left":16,"right":344},"stateTypes":{"count":"number"},"scrollWidth":360}}"""
        val success = assertIs<LocalGenUiIntent.VerifyApp>(read(probe, checking))
        assertEquals(emptyList(), success.checks.filter { it.result == LocalGenUiCheckResult.FAILED })
        assertEquals(mapOf("count" to "number"), success.stateTypes)
        val overflow = assertIs<LocalGenUiIntent.VerifyApp>(read(probe.replace("\"scrollWidth\":360", "\"scrollWidth\":390"), checking))
        assertEquals("no-horizontal-overflow", overflow.checks.single { it.result == LocalGenUiCheckResult.FAILED }.name)
        val mismatch = assertIs<LocalGenUiIntent.VerifyApp>(read(probe.replace("\"contractOk\":true", "\"contractOk\":false"), checking))
        assertEquals(LocalGenUiCheckResult.FAILED, mismatch.checks.single().result)
        assertNull(read(probe, checking.copy(sourceRevision = 5)))
        assertNull(read(probe, checking.copy(reopening = true)))
        val reopened = assertIs<LocalGenUiIntent.VerifyApp>(read(probe.replace("validate:", "reopen:"), checking.copy(reopening = true)))
        assertEquals("save-reopen", reopened.checks.single().name)
    }
}
