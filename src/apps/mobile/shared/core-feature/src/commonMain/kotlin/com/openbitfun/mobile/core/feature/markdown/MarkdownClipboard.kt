package com.openbitfun.mobile.core.feature.markdown

/** Clipboard flavors derived from the same parse tree as the native transcript. */
public object MarkdownClipboard {
    public fun plainText(source: String): String = MarkdownParser.formatInlineText(source)

    public fun html(source: String): String =
        MarkdownParser.parse(source).joinToString("") { block ->
            when (block.type) {
                "heading" -> element("h${block.level.coerceIn(1, 6)}", inline(block.inlines))
                "quote" -> element("blockquote", inline(block.inlines))
                "code" -> element("pre", element("code", escape(block.text)))
                "divider" -> "<hr>"
                "list" -> list(block.items)
                "table" -> table(block.text)
                else -> element("p", inline(block.inlines))
            }
        }

    private fun list(items: List<MarkdownListItem>): String = buildString {
        var listTag: String? = null
        for (item in items) {
            val index = item.marker.removeSuffix(".").toIntOrNull()
            val tag = if (index != null) "ol" else "ul"
            if (tag != listTag) {
                if (listTag != null) append("</$listTag>")
                append("<$tag>")
                listTag = tag
            }
            if (index == null) append("<li>") else append("<li value=\"$index\">")
            append(inline(item.inlines)).append("</li>")
        }
        if (listTag != null) append("</$listTag>")
    }

    private fun table(source: String): String {
        val rows = source.lines()
        return element("table", rows.filterIndexed { index, _ -> index != 1 }
            .mapIndexed { index, row ->
                val tag = if (index == 0) "th" else "td"
                element("tr", row.removePrefix("|").removeSuffix("|").split('|').joinToString("") { cell ->
                    element(tag, inline(MarkdownParser.parseInlineText(cell.trim())))
                })
            }.joinToString(""))
    }

    private fun inline(values: List<MarkdownInline>): String = values.joinToString("") { value ->
        val text = escape(value.text).replace("\n", "<br>")
        when (value.type) {
            "strong" -> element("strong", text)
            "emphasis" -> element("em", text)
            "delete" -> element("del", text)
            "code" -> element("code", text)
            "link" -> {
                val url = value.url.trim()
                if (url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)) {
                    "<a href=\"${escape(url)}\">$text</a>"
                } else text
            }
            else -> text
        }
    }

    private fun element(tag: String, text: String): String = "<$tag>$text</$tag>"

    private fun escape(text: String): String =
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("\"", "&quot;").replace("'", "&#39;")
}
