package com.openbitfun.mobile.core.feature.layout

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class UserMessageTruncationPolicyTest {
    @Test
    fun eighthLineEndsThePreviewWithAnyLineEnding() {
        val firstEight = (1..8).joinToString("\n") { "Line $it" }
        assertEquals("$firstEight...", UserMessageTruncationPolicy.truncatedPreview(firstEight.replace("\n", "\r\n") + "\r\nLast line"))
        assertNull(UserMessageTruncationPolicy.truncatedPreview("$firstEight\n  "))
    }

    @Test
    fun characterLimitPreservesWholeUnicodeCharacters() {
        val prefix = "x".repeat(359)
        assertEquals("$prefix...", UserMessageTruncationPolicy.truncatedPreview("${prefix}😀 tail"))
        assertNull(UserMessageTruncationPolicy.truncatedPreview(prefix + "x"))
        assertNull(UserMessageTruncationPolicy.truncatedPreview(prefix + "x" + " ".repeat(20)))
    }
}
