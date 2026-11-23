package com.openbitfun.mobile.core.feature.markdown

import kotlin.test.Test
import kotlin.test.assertEquals

class MarkdownClipboardTest {
    @Test
    fun preservesFormattingAndEscapesUntrustedContent() {
        val source = "## **Ready**\n\n<x> [yes](https://example.org/?x=\"a\"&b) [no](javascript:script)"
        assertEquals(
            "<h2><strong>Ready</strong></h2><p>&lt;x&gt; <a href=\"https://example.org/?x=&quot;a&quot;&amp;b\">yes</a> no</p>",
            MarkdownClipboard.html(source),
        )
        assertEquals("Ready", MarkdownClipboard.plainText("**Ready**"))
    }
}
