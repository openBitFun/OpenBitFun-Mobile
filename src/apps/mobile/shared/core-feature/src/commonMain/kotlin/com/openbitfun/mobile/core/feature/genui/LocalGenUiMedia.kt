package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.transport.GenUiMediaCache
import com.openbitfun.mobile.core.transport.GenUiUserImages
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

@ConsistentCopyVisibility
public data class LocalGenUiImageSearch internal constructor(
    public val appId: String,
    internal val requestId: String,
    internal val query: String,
)

@ConsistentCopyVisibility
public data class LocalGenUiImage internal constructor(
    public val mimeType: String,
    public val bytes: ByteArray,
)

public class LocalGenUiMedia(directory: String, userImageDirectory: String) {
    internal val userImages = GenUiUserImages(userImageDirectory)
    private val cache = GenUiMediaCache.create(directory)

    public suspend fun search(request: LocalGenUiImageSearch): String = result(request, cache.search(request.query))

    public suspend fun read(path: String): LocalGenUiImage? =
        cache.picture(path)?.let { LocalGenUiImage(it.mimeType, it.bytes) }

    public suspend fun readCollaboration(path: String, appId: String): LocalGenUiImage? =
        userImages.read(appId, path)?.let { LocalGenUiImage("image/jpeg", it) }

    public fun close() {
        cache.close()
    }

    public companion object {
        public fun request(raw: String, app: LocalGenUiApp): LocalGenUiImageSearch? {
            if (app.checking || raw.length > 2400) return null
            val message = LocalGenUiStore.jsonObject(raw) ?: return null
            fun string(key: String): String? = (message[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            if (string("type") != "image_search" || string("appId") != app.id) return null
            val id = string("requestId")?.takeIf { it.isNotBlank() && it.length <= 64 } ?: return null
            val query = string("query") ?: return null
            return LocalGenUiImageSearch(app.id, id, query)
        }

        public fun refused(request: LocalGenUiImageSearch): String = result(request, emptyList())

        private fun result(request: LocalGenUiImageSearch, images: List<String>): String = buildJsonObject {
            put("type", "image_search_result")
            put("appId", request.appId)
            put("requestId", request.requestId)
            put("images", JsonArray(images.map(::JsonPrimitive)))
        }.toString()
    }
}
