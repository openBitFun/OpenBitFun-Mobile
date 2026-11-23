package com.openbitfun.mobile.core.transport

import kotlin.test.Test
import kotlin.test.assertEquals

class GenUiProviderStreamTest {
    @Test
    fun openAiKeepsToolArgumentsAndFinishReasonAcrossFrames() {
        val parser = GenUiProviderParser(ModelProviderProtocol.OPEN_AI)
        val start = """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"GenerativeUI","arguments":"{\"title\":"}}]}}]}"""
        assertEquals(emptyList(), parser.feed(start.take(42)))
        assertEquals(listOf(GenUiProviderFrame.Tool(0, "GenerativeUI", "{\"title\":")), parser.feed(start.drop(42) + "\n\n"))
        val end = """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"\u6d4b\u8bd5\"}"}}]},"finish_reason":"tool_calls"}]}"""
        assertEquals(emptyList(), parser.feed(end))
        assertEquals(
            listOf(GenUiProviderFrame.Tool(0, null, "\"\u6d4b\u8bd5\"}"), GenUiProviderFrame.Stop("tool_calls")),
            parser.finish(),
        )
    }

    @Test
    fun anthropicKeepsTextAndToolBlocksSeparate() {
        val parser = GenUiProviderParser(ModelProviderProtocol.ANTHROPIC)
        val lines = listOf(
            """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\u51c6\u5907\u597d\u4e86"}}""",
            """data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"GenerativeUI"}}""",
            """data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}""",
            """data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}""",
        )
        assertEquals(
            listOf(
                GenUiProviderFrame.Text("\u51c6\u5907\u597d\u4e86"),
                GenUiProviderFrame.Tool(1, "GenerativeUI", ""),
                GenUiProviderFrame.Tool(1, null, "{}"),
                GenUiProviderFrame.Stop("tool_use"),
            ),
            parser.feed(lines.joinToString("\n\n", postfix = "\n\n")),
        )
    }
}
