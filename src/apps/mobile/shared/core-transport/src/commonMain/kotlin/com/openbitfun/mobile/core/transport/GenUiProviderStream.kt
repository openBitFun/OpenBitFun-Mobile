package com.openbitfun.mobile.core.transport

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.accept
import io.ktor.client.request.header
import io.ktor.client.request.prepareGet
import io.ktor.client.request.preparePost
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.URLProtocol
import io.ktor.http.Url
import io.ktor.http.contentType
import io.ktor.utils.io.readUTF8Line
import io.ktor.utils.io.readRemaining
import kotlinx.io.readString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/** A frame is transport data. The feature owns the only tool it can execute. */
public sealed interface GenUiProviderFrame {
    public data class Text(public val delta: String) : GenUiProviderFrame
    public data class Tool(public val index: Int, public val name: String?, public val arguments: String) : GenUiProviderFrame
    public data class Stop(public val reason: String) : GenUiProviderFrame
}

public class GenUiProviderStream internal constructor(private val client: HttpClient) {
    public suspend fun stream(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: List<ModelProviderMessage>,
        system: String,
        toolSchema: String,
        onFrame: (GenUiProviderFrame) -> Unit,
    ) {
        val protocol = ModelProviderRequest.resolveProtocol(baseUrl)
        val body = Json.parseToJsonElement(ModelProviderRequest.body(model, messages, protocol, 32768, system)).jsonObject
        val tool = Json.parseToJsonElement(toolSchema).jsonObject
        val parser = GenUiProviderParser(protocol)
        val statement = client.preparePost(ModelProviderRequest.resolveUrl(baseUrl, protocol)) {
            contentType(ContentType.Application.Json)
            accept(ContentType.Text.EventStream)
            if (protocol == ModelProviderProtocol.ANTHROPIC) {
                header("x-api-key", apiKey)
                header("anthropic-version", "2023-06-01")
                if (url.host.equals("openbitfun.com", ignoreCase = true) || url.host.endsWith(".openbitfun.com", ignoreCase = true)) {
                    header("X-Verification-Code", "from_openbitfun")
                }
            } else {
                header(HttpHeaders.Authorization, "Bearer $apiKey")
            }
            setBody(buildJsonObject {
                body.forEach { (key, value) -> put(key, value) }
                put("tools", JsonArray(listOf(if (protocol == ModelProviderProtocol.ANTHROPIC) tool else openAiTool(tool))))
            }.toString())
        }
        statement.execute { response ->
            val status = response.status.value
            if (status !in 200..299) throw ModelProviderException(modelProviderStatusFailure(status))
            val channel = response.bodyAsChannel()
            var received = 0
            while (!channel.isClosedForRead) {
                val line = channel.readUTF8Line(512 * 1024) ?: break
                received += line.length + 1
                if (received > 2 * 1024 * 1024) throw ModelProviderException(ModelProviderFailure.InvalidResponse)
                parser.feed("$line\n").forEach(onFrame)
            }
            parser.finish().forEach(onFrame)
        }
    }

    public suspend fun discoverModels(baseUrl: String, apiKey: String): List<String> {
        if (ModelProviderRequest.resolveProtocol(baseUrl) == ModelProviderProtocol.ANTHROPIC) return emptyList()
        val root = baseUrl.trimEnd('/').removeSuffix("/chat/completions").removeSuffix("/v1")
        return client.prepareGet("$root/v1/models") {
            accept(ContentType.Application.Json)
            header(HttpHeaders.Authorization, "Bearer $apiKey")
        }.execute { response ->
            val status = response.status.value
            if (status !in 200..299) throw ModelProviderException(modelProviderStatusFailure(status))
            val body = response.bodyAsChannel().readRemaining(1024L * 1024).readString()
            val envelope = Json.parseToJsonElement(body).jsonObject
            envelope["data"]?.jsonArray.orEmpty().mapNotNull {
                ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
            }.distinct()
        }
    }

    private fun openAiTool(tool: JsonObject): JsonObject = buildJsonObject {
        put("type", "function")
        put("function", buildJsonObject {
            put("name", tool.getValue("name"))
            put("description", tool.getValue("description"))
            put("parameters", tool.getValue("input_schema"))
        })
    }

    public companion object {
        public fun isValidEndpoint(endpoint: String): Boolean = runCatching {
            val url = Url(endpoint)
            url.protocol in setOf(URLProtocol.HTTP, URLProtocol.HTTPS) &&
                url.host.isNotBlank() && url.port in 1..65535 && url.user == null && url.password == null
        }.getOrDefault(false)

        public fun create(): GenUiProviderStream = GenUiProviderStream(HttpClient {
            expectSuccess = false
            followRedirects = false
            install(HttpTimeout) {
                connectTimeoutMillis = 15_000
                requestTimeoutMillis = 180_000
            }
        })
    }
}

internal class GenUiProviderParser(private val protocol: ModelProviderProtocol) {
    private val decoder = SseFrameDecoder()

    fun feed(chunk: String): List<GenUiProviderFrame> = decoder.feed(chunk).flatMap(::parse)
    fun finish(): List<GenUiProviderFrame> = decoder.finish().flatMap(::parse)

    private fun parse(data: String): List<GenUiProviderFrame> {
        val event = runCatching { Json.parseToJsonElement(data).jsonObject }.getOrNull()
            ?: throw ModelProviderException(ModelProviderFailure.InvalidResponse)
        if (event["error"] != null) throw ModelProviderException(ModelProviderFailure.InvalidResponse)
        return if (protocol == ModelProviderProtocol.ANTHROPIC) anthropic(event) else openAi(event)
    }

    private fun openAi(event: JsonObject): List<GenUiProviderFrame> = buildList {
        val choice = event["choices"]?.jsonArray?.firstOrNull()?.jsonObject ?: return@buildList
        val delta = choice["delta"] as? JsonObject
        delta?.string("content")?.takeIf(String::isNotEmpty)?.let { add(GenUiProviderFrame.Text(it)) }
        delta?.get("tool_calls")?.jsonArray?.forEach { value ->
            val call = value.jsonObject
            val function = call["function"] as? JsonObject ?: return@forEach
            add(GenUiProviderFrame.Tool(call.index(), function.string("name"), function.string("arguments").orEmpty()))
        }
        choice.string("finish_reason")?.let { add(GenUiProviderFrame.Stop(it)) }
    }

    private fun anthropic(event: JsonObject): List<GenUiProviderFrame> {
        val block = event["content_block"] as? JsonObject
        val delta = event["delta"] as? JsonObject
        val frame = when (event.string("type")) {
            "content_block_start" -> when (block?.string("type")) {
                "tool_use" -> GenUiProviderFrame.Tool(event.index(), block.string("name"), "")
                "text" -> block.string("text")?.takeIf(String::isNotEmpty)?.let(GenUiProviderFrame::Text)
                else -> null
            }
            "content_block_delta" -> when (delta?.string("type")) {
                "input_json_delta" -> GenUiProviderFrame.Tool(event.index(), null, delta.string("partial_json").orEmpty())
                "text_delta" -> delta.string("text")?.let(GenUiProviderFrame::Text)
                else -> null
            }
            "message_delta" -> delta?.string("stop_reason")?.let(GenUiProviderFrame::Stop)
            else -> null
        }
        return listOfNotNull(frame)
    }

    private fun JsonObject.string(key: String): String? = (get(key) as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.index(): Int = (get("index") as? JsonPrimitive)?.intOrNull ?: 0
}
