package com.openbitfun.mobile.core.transport

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.timeout
import io.ktor.client.request.header
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.URLBuilder
import io.ktor.http.URLProtocol
import io.ktor.http.Url
import io.ktor.http.contentLength
import io.ktor.http.decodeURLPart
import io.ktor.http.encodeURLPathPart
import io.ktor.http.encodeURLQueryComponent
import io.ktor.utils.io.readRemaining
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.io.readByteArray
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

private const val USER_AGENT = "OpenBitFun-Mobile/1.0 (https://github.com/openBitFun/OpenBitFun)"
private const val STATIC_REVISION = "1ffb34c752ecf5d402f04cfb4b392c77f57c54bc"
private const val ANIMATED_REVISION = "daa0365c09795789ed2bc6e8b228c97736cb6669"
private const val ONE_MIB = 1024 * 1024
internal const val PHOTO_LIMIT = 4 * ONE_MIB
private val PHOTO_FIELDS = listOf("thumb", "thumburl", "thumbURL", "middleURL", "src", "img", "url", "objURL", "hoverURL")

/** A separate client carries neither model credentials nor cookies. Web documents never call it directly. */
internal class GenUiMediaClient(private val http: HttpClient) {
    fun close() = http.close()

    suspend fun search(query: String): List<String> = withTimeoutOrNull(16_000) {
        val escaped = query.encodeURLQueryComponent()
        val domestic = coroutineScope {
            val so = async {
                collect(json("https://image.so.com/j?q=$escaped&pn=0&sn=0&pd=1&correct=$escaped", 6_000))
            }
            val baidu = async {
                collect(json("https://image.baidu.com/search/acjson?tn=resultjson_com&word=$escaped&ie=utf-8&pn=0&rn=10", 6_000))
            }
            (so.await() + baidu.await()).distinct().take(4)
        }
        domestic.ifEmpty { openImages(query, escaped) }
    }.orEmpty()

    private suspend fun openImages(query: String, escaped: String): List<String> = coroutineScope {
        val summary = async {
            val name = query.replace(' ', '_').encodeURLPathPart()
            val result = json("https://en.wikipedia.org/api/rest_v1/page/summary/$name", 8_000) as? JsonObject
            ((result?.get("thumbnail") as? JsonObject)?.get("source") as? JsonPrimitive)
                ?.contentOrNull?.let(::photoUrl)
        }
        val commons = async {
            val result = json("https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2" +
                "&generator=search&gsrsearch=$escaped&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=960", 8_000)
            val pages = ((result as? JsonObject)?.get("query") as? JsonObject)?.get("pages") as? JsonArray
            pages.orEmpty().mapNotNull { page ->
                val image = ((page as? JsonObject)?.get("imageinfo") as? JsonArray)?.firstOrNull() as? JsonObject
                // Prefer the server-sized raster. The original can be large or an SVG.
                val url = (image?.get("thumburl") ?: image?.get("url")) as? JsonPrimitive
                url?.contentOrNull?.let(::photoUrl)
            }
        }
        (listOfNotNull(summary.await()) + commons.await()).distinct().take(4)
    }

    private suspend fun json(url: String, timeoutMs: Long): JsonElement? {
        val bytes = fetch(url, ONE_MIB, timeoutMs) ?: return null
        return runCatching { Json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true)) }.getOrNull()
    }

    suspend fun photo(upstream: String): ByteArray? {
        val url = photoUrl(upstream) ?: return null
        val referrer = if (hostUnder(Url(url).host, "baidu.com") || hostUnder(Url(url).host, "bdimg.com")) {
            "https://image.baidu.com/"
        } else null
        return fetch(url, PHOTO_LIMIT, 15_000, referrer)?.takeIf { genUiImageType(it) != null }
    }

    suspend fun icon(asset: GenUiPinnedIcon): ByteArray? =
        fetch(asset.url, asset.limit, if (asset.animated) 30_000 else 10_000)
            ?.takeIf { genUiImageType(it) == "image/png" }

    private suspend fun fetch(url: String, maxBytes: Int, timeoutMs: Long, referrer: String? = null): ByteArray? {
        return try {
            http.prepareGet(url) {
                header(HttpHeaders.UserAgent, USER_AGENT)
                if (referrer != null) header(HttpHeaders.Referrer, referrer)
                timeout { requestTimeoutMillis = timeoutMs }
            }.execute { response ->
                if (response.status != HttpStatusCode.OK || (response.contentLength() ?: 0) > maxBytes) return@execute null
                response.bodyAsChannel().readRemaining(maxBytes.toLong() + 1).readByteArray()
                    .takeIf { it.isNotEmpty() && it.size <= maxBytes }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    private fun collect(root: JsonElement?): List<String> {
        val images = linkedSetOf<String>()
        fun visit(value: JsonElement?, depth: Int) {
            if (depth > 20 || images.size >= 8) return
            when (value) {
                is JsonArray -> value.forEach { visit(it, depth + 1) }
                is JsonObject -> {
                    PHOTO_FIELDS.firstNotNullOfOrNull { field ->
                        (value[field] as? JsonPrimitive)?.contentOrNull?.let(::photoUrl)
                    }?.let(images::add)
                    value.values.forEach { visit(it, depth + 1) }
                }
                else -> Unit
            }
        }
        visit(root, 0)
        return images.take(4)
    }

    companion object {
        fun create(): GenUiMediaClient = GenUiMediaClient(HttpClient {
            followRedirects = false
            expectSuccess = false
            install(HttpTimeout) {
                connectTimeoutMillis = 8_000
                socketTimeoutMillis = 15_000
            }
        })
    }
}

// These providers return CDN URLs intermixed with result-page links. The app
// only retrieves images from the providers' image infrastructure.
private val photoDomains = setOf(
    "bdimg.com", "bdstatic.com", "360tres.com", "360img.com",
    "qhimg.com", "qhimgs.com", "qhimgs0.com", "qhimgs1.com", "qhimgs2.com", "qhimgs3.com",
    "upload.wikimedia.org", "thumb.wikimedia.org",
)
private val photoExactHosts = setOf("img0.baidu.com", "img1.baidu.com", "img2.baidu.com", "img3.baidu.com")

private fun hostUnder(host: String, domain: String): Boolean = host == domain || host.endsWith(".$domain")

internal fun photoUrl(input: String): String? {
    val candidate = input.trim()
    if (candidate.length !in 1..2048 || !candidate.startsWith("https://", ignoreCase = true) &&
        !candidate.startsWith("http://", ignoreCase = true) ||
        candidate.any { it.isWhitespace() || it == '\\' || it.code < 32 }
    ) return null
    val url = runCatching { Url(candidate) }.getOrNull() ?: return null
    if (url.user != null || url.password != null || url.fragment.isNotEmpty() || url.port != url.protocol.defaultPort) return null
    val host = url.host.lowercase()
    if (host !in photoExactHosts && photoDomains.none { hostUnder(host, it) }) return null
    val path = url.encodedPath.lowercase()
    if (path.contains(".svg") || path.contains("logo") || path.contains("icon")) return null
    return URLBuilder(url).apply {
        protocol = URLProtocol.HTTPS
        port = URLProtocol.HTTPS.defaultPort
    }.buildString()
}

internal data class GenUiPinnedIcon(val url: String, val animated: Boolean, val limit: Int)

internal fun pinnedIcon(path: String): GenUiPinnedIcon? {
    val parts = path.removePrefix("/fluent-emoji/").split('/')
    val animated = parts.firstOrNull() == "animated"
    val revision = if (animated) ANIMATED_REVISION else STATIC_REVISION
    val start = if (animated) 2 else 1
    if (parts.getOrNull(start - 1) != revision || parts.size !in (start + 3)..(start + 4)) return null
    val decoded = runCatching { parts.drop(start).map { it.decodeURLPart() } }.getOrNull() ?: return null
    val (name, folder, file) = if (decoded.size == 4 && decoded[1] == "Default") {
        Triple(decoded[0], decoded[2], decoded[3])
    } else if (decoded.size == 3) Triple(decoded[0], decoded[1], decoded[2]) else return null
    if (folder != if (animated) "animated" else "3D") return null
    val suffix = if (animated) "_animated" else "_3d"
    if (!validIconSegment(name, 81, " ,.'&()!_-") || !validIconSegment(file, 122, "_().!'&,-") ||
        !(file.endsWith("$suffix.png") || file.endsWith("${suffix}_default.png"))
    ) return null
    val upstream = if (animated) {
        "https://media.githubusercontent.com/media/microsoft/fluentui-emoji-animated/$revision/assets/"
    } else {
        "https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@$revision/assets/"
    }
    return GenUiPinnedIcon(upstream + decoded.joinToString("/") { it.encodeURLPathPart() }, animated, (if (animated) 6 else 2) * ONE_MIB)
}

private fun validIconSegment(value: String, max: Int, punctuation: String): Boolean =
    value.length in 1..max && value.first().isLetterOrDigit() && ".." !in value &&
        value.all { it.isLetterOrDigit() || it in punctuation }

internal fun genUiImageType(bytes: ByteArray): String? {
    fun starts(signature: String, at: Int = 0): Boolean =
        signature.length + at <= bytes.size && signature.indices.all { bytes[at + it] == signature[it].code.toByte() }
    return when {
        starts("\u0089PNG\r\n\u001a\n") -> "image/png"
        starts("\u00ff\u00d8\u00ff") -> "image/jpeg"
        starts("GIF87a") || starts("GIF89a") -> "image/gif"
        starts("RIFF") && starts("WEBP", 8) -> "image/webp"
        starts("ftypavif", 4) || starts("ftypavis", 4) -> "image/avif"
        starts("BM") -> "image/bmp"
        else -> null
    }
}
