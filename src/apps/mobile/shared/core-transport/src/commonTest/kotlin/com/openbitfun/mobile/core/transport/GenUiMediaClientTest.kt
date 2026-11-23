package com.openbitfun.mobile.core.transport

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.HttpTimeout
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class GenUiMediaClientTest {
    @Test
    fun choosesProviderThumbnailsWithoutFollowingUntrustedResultUrls() = runTest {
        val client = GenUiMediaClient(HttpClient(MockEngine { request ->
            assertNull(request.headers[HttpHeaders.Authorization])
            assertNull(request.headers[HttpHeaders.Cookie])
            when (request.url.host) {
                "image.so.com" -> respond("""{"list":[
                    {"thumb":"https://p1.ssl.qhimgs1.com/fruit.jpg","img":"https://unrelated.invalid/photo.jpg"},
                    {"thumb":"http://127.0.0.1/private.png","url":"https://upload.wikimedia.org/fruit.jpg"}]}""")
                "image.baidu.com" -> respond("""{"data":[{"thumbURL":"https://img1.baidu.com/fruit.jpg"}]}""")
                else -> error("Unexpected request")
            }
        }) { install(HttpTimeout) })
        try {
            assertEquals(listOf("https://p1.ssl.qhimgs1.com/fruit.jpg", "https://upload.wikimedia.org/fruit.jpg",
                "https://img1.baidu.com/fruit.jpg"), withContext(Dispatchers.Default) { client.search("Tangerine") })
        } finally { client.close() }
    }

    @Test
    fun fallsBackToWikimediaSizedPhotos() = runTest {
        val client = GenUiMediaClient(HttpClient(MockEngine { request ->
            when (request.url.host) {
                "en.wikipedia.org" -> respond("""{"thumbnail":{"source":"https://thumb.wikimedia.org/example.jpg"}}""")
                "commons.wikimedia.org" -> respond("""{"query":{"pages":[{"imageinfo":[
                    {"url":"https://upload.wikimedia.org/original.svg","thumburl":"https://upload.wikimedia.org/thumb.png"}
                ]}]}}""")
                else -> respond("{}", HttpStatusCode.ServiceUnavailable)
            }
        }) { install(HttpTimeout) })
        try {
            assertEquals(listOf("https://thumb.wikimedia.org/example.jpg", "https://upload.wikimedia.org/thumb.png"),
                withContext(Dispatchers.Default) { client.search("Tangerine") })
        } finally { client.close() }
    }

    @Test
    fun strictPathsAndLimitedRasterDataStayInsideTheHost() = runTest {
        assertNull(photoUrl("https://upload.wikimedia.org.evil.invalid/fruit.png"))
        assertNull(photoUrl("https://upload.wikimedia.org@127.0.0.1/fruit.png"))
        assertNull(photoUrl("https://upload.wikimedia.org:81/fruit.png"))
        assertEquals("https://upload.wikimedia.org/fruit.png", photoUrl("http://upload.wikimedia.org/fruit.png"))
        val path = "/fluent-emoji/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/Tangerine/3D/tangerine_3d.png"
        val icon = assertNotNull(pinnedIcon(path))
        val animation = assertNotNull(pinnedIcon(
            "/fluent-emoji/animated/daa0365c09795789ed2bc6e8b228c97736cb6669/Rocket/animated/rocket_animated.png",
        ))
        assertNull(pinnedIcon(path.replace("Tangerine", "%2E%2E")))
        assertNull(pinnedIcon(path + "?redirect=other"))
        val png = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
        val client = GenUiMediaClient(HttpClient(MockEngine { request ->
            when (request.url.host) {
                "cdn.jsdelivr.net", "media.githubusercontent.com" -> respond(png)
                "upload.wikimedia.org" -> respond("not a raster")
                "thumb.wikimedia.org" -> respond("", headers = headersOf(HttpHeaders.ContentLength, (PHOTO_LIMIT + 1).toString()))
                else -> error("Unexpected request")
            }
        }) { install(HttpTimeout) })
        try {
            assertContentEquals(png, client.icon(icon))
            assertContentEquals(png, client.icon(animation))
            assertNull(client.photo("https://upload.wikimedia.org/not-a-photo.jpg"))
            assertNull(client.photo("https://thumb.wikimedia.org/too-large.jpg"))
        } finally { client.close() }
    }
}
