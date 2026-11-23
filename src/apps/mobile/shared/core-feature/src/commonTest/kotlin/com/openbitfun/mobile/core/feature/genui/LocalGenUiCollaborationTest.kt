package com.openbitfun.mobile.core.feature.genui

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class LocalGenUiCollaborationTest {
    private val app = LocalGenUiApp("app", "session", "Image", "", sourceRevision = 2)
    private val secret = "ab".repeat(32)

    @Test
    fun inviteAcceptsPrivateLiteralOnly() {
        assertEquals(LocalGenUiImageKind.SCAN, assertNotNull(parse("192.168.2.129")).kind)
        for (host in listOf("127.0.0.1", "192.168.999.2", "google.com", "100.64.0.1", "192.168.01.12", "8.8.8.8")) {
            assertNull(parse(host))
        }
        assertNull(parse("172.16.1.2", port = 80))
        assertNull(parse("10.1.1.3", key = "ab"))
    }

    @Test
    fun bridgeOnlyAcceptsCurrentLiveRequest() {
        val raw = """{"type":"collaboration","appId":"app","sourceRevision":2,"requestId":"image-1","op":"start","kind":"gallery"}"""
        val accepted = assertNotNull(LocalGenUiCollaboration.request(raw, app))
        assertEquals(LocalGenUiImageKind.GALLERY, accepted.kind)
        assertContains(LocalGenUiCollaboration.reply(accepted, LocalGenUiCollaborationResult.PENDING, "", ""), """"requestId":"image-1"""")
        assertNull(LocalGenUiCollaboration.request(raw, app.copy(streaming = true)))
        assertNull(LocalGenUiCollaboration.request(raw, app.copy(sourceRevision = 3)))
        assertNull(LocalGenUiCollaboration.request(raw.replace("\"gallery\"", "\"invalid\""), app))
    }

    private fun parse(host: String, port: Int = 54321, key: String = secret) =
        LocalGenUiCollaboration.parse("openbitfun-image-v1:scan:$host:$port:$key")
}
