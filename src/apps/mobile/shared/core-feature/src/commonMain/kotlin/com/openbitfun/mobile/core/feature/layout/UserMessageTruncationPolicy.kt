package com.openbitfun.mobile.core.feature.layout

/** The content-based preview used by the HarmonyOS conversation bubble. */
public object UserMessageTruncationPolicy {
    private const val MAX_PREVIEW_LINES = 8
    private const val MAX_PREVIEW_CHARS = 360

    /** Returns a shortened preview only when there is non-whitespace text beyond it. */
    public fun truncatedPreview(text: String): String? {
        val normalized = text.replace("\r\n", "\n")
        var lines = 1
        var limit = minOf(normalized.length, MAX_PREVIEW_CHARS)
        for (index in 0 until limit) {
            if (normalized[index] == '\n' && ++lines > MAX_PREVIEW_LINES) {
                limit = index
                break
            }
        }
        if (limit == normalized.length) return null
        if (limit > 0 && normalized[limit - 1].isHighSurrogate() && normalized[limit].isLowSurrogate()) limit--
        if (normalized.substring(limit).all { it.isWhitespace() || it == '\uFEFF' }) return null
        return normalized.substring(0, limit).trimEnd(' ', '\t', '\n') + "..."
    }
}
