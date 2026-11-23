package com.openbitfun.mobile.core.transport

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray
import kotlinx.serialization.json.Json

public data class GenUiMediaImage(public val mimeType: String, public val bytes: ByteArray)

/**
 * The app owns this cache outside WebView storage. Asset requests may only name
 * a photo issued by the search provider or a pinned icon from the build.
 */
public class GenUiMediaCache internal constructor(
    directory: String,
    private val client: GenUiMediaClient,
) {
    private val directory = Path(directory)
    private val owner = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val disk = Mutex()
    private val searchSlots = Semaphore(4)
    private val assetSlots = Semaphore(6)
    private val issued = linkedMapOf<String, String>()
    private val searches = mutableMapOf<String, Deferred<List<String>>>()
    private val pictures = mutableMapOf<String, Deferred<GenUiMediaImage?>>()
    private var remembered: LinkedHashMap<String, List<String>>? = null

    public fun close() {
        owner.cancel()
        client.close()
    }

    public suspend fun search(query: String): List<String> {
        val key = query.trim()
        if (key.count { !it.isLowSurrogate() } !in 2..200) return emptyList()
        val request = lock.withLock {
            searches.getOrPut(key) {
                owner.async {
                    try {
                        val answers = answers()
                        val cached = lock.withLock { answers[key] }
                        val result = cached ?: searchSlots.withPermit { client.search(key) }
                        if (result.isEmpty()) return@async emptyList()
                        lock.withLock {
                            if (cached == null) {
                                answers[key] = result
                                while (answers.size > 300) answers.remove(answers.keys.first())
                                write("queries.json", Json.encodeToString(answers).encodeToByteArray())
                            }
                            result.map(::issue)
                        }
                    } finally {
                        lock.withLock { searches.remove(key) }
                    }
                }
            }
        }
        return request.await()
    }

    public suspend fun picture(path: String): GenUiMediaImage? {
        val file: String
        val limit: Int
        val download: suspend () -> ByteArray?
        val photo = PHOTO.matchEntire(path)
        if (photo != null) {
            val id = photo.groupValues[1]
            file = "$id.img"
            limit = PHOTO_LIMIT
            download = {
                val url = lock.withLock { issued[id] }
                url?.let { client.photo(it) }
            }
        } else if (path.startsWith("/fluent-emoji/")) {
            val icon = pinnedIcon(path) ?: return null
            file = "icon-${imageId(icon.url)}.png"
            limit = icon.limit
            download = { client.icon(icon) }
        } else {
            return null
        }
        val request = lock.withLock {
            pictures.getOrPut(file) {
                owner.async {
                    try {
                        read(file, limit)?.let { bytes ->
                            genUiImageType(bytes)?.let { return@async GenUiMediaImage(it, bytes) }
                        }
                        val bytes = assetSlots.withPermit { download() } ?: return@async null
                        val mimeType = genUiImageType(bytes) ?: return@async null
                        write(file, bytes)
                        GenUiMediaImage(mimeType, bytes)
                    } finally {
                        lock.withLock { pictures.remove(file) }
                    }
                }
            }
        }
        return request.await()
    }

    private suspend fun answers(): LinkedHashMap<String, List<String>> = lock.withLock {
        remembered?.let { return@withLock it }
        val fromFile = read("queries.json", 2 * 1024 * 1024)?.let {
            runCatching { Json.decodeFromString<LinkedHashMap<String, List<String>>>(it.decodeToString()) }.getOrNull()
        }
        val safe = linkedMapOf<String, List<String>>()
        fromFile?.entries?.toList()?.takeLast(300)?.forEach { (query, urls) ->
            val pictures = urls.mapNotNull(::photoUrl).take(4)
            if (query.length <= 400 && pictures.isNotEmpty()) safe[query] = pictures
        }
        remembered = safe
        safe
    }

    private fun issue(url: String): String {
        val id = imageId(url)
        if (id !in issued && issued.size >= 500) issued.remove(issued.keys.first())
        issued[id] = url
        return "https://genui-assets.openbitfun.invalid/photo/$id"
    }

    private suspend fun read(name: String, limit: Int): ByteArray? = disk.withLock {
        val path = Path(directory, name)
        runCatching {
            val size = SystemFileSystem.metadataOrNull(path)?.size ?: return@runCatching null
            if (size !in 1L..limit.toLong()) return@runCatching null
            SystemFileSystem.source(path).buffered().use { it.readByteArray() }
        }.getOrNull()
    }

    private suspend fun write(name: String, value: ByteArray) = disk.withLock {
        val temporary = Path(directory, "$name.tmp")
        try {
            SystemFileSystem.createDirectories(directory)
            SystemFileSystem.sink(temporary).buffered().use { it.write(value) }
            SystemFileSystem.atomicMove(temporary, Path(directory, name))
        } catch (_: Exception) {
            runCatching { SystemFileSystem.delete(temporary, mustExist = false) }
        }
    }

    public companion object {
        public fun create(directory: String): GenUiMediaCache = GenUiMediaCache(directory, GenUiMediaClient.create())
        private val PHOTO = Regex("^/photo/([0-9a-f]{16})$")
    }
}

internal fun imageId(url: String): String {
    var first = 0x811c9dc5u
    var second = 0x01000193u xor 0x5bd1e995u
    for (character in url) {
        first = (first xor character.code.toUInt()) * 0x01000193u
        second = (second xor character.code.toUInt()) * 0x5bd1e995u
    }
    return first.toString(16).padStart(8, '0') + second.toString(16).padStart(8, '0')
}
