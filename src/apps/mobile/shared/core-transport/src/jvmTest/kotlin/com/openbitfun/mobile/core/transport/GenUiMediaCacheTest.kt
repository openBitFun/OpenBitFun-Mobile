package com.openbitfun.mobile.core.transport

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.HttpTimeout
import io.ktor.http.HttpStatusCode
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class GenUiMediaCacheTest {
    @Test
    fun storedSearchAndRasterAreUsableWithANewOfflineOwner() = runBlocking {
        val directory = Files.createTempDirectory("genui-media-cache").toFile()
        val photo = "https://upload.wikimedia.org/fruit.png"
        val bytes = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
        val online = GenUiMediaClient(HttpClient(MockEngine { request ->
            when (request.url.host) {
                "image.so.com" -> respond("""{"list":[{"thumb":"$photo"}]}""")
                "image.baidu.com" -> respond("{}", HttpStatusCode.ServiceUnavailable)
                "upload.wikimedia.org" -> respond(bytes)
                else -> error("Unexpected request")
            }
        }) { install(HttpTimeout) })
        val offline = GenUiMediaClient(HttpClient(MockEngine { error("This owner has no network") }) { install(HttpTimeout) })
        try {
            val first = GenUiMediaCache(directory.path, online)
            val original: String
            try {
                original = first.search("Tangerine").single()
                val path = original.removePrefix("https://genui-assets.openbitfun.invalid")
                assertContentEquals(bytes, assertNotNull(first.picture(path)).bytes)
            } finally { first.close() }
            val reopened = GenUiMediaCache(directory.path, offline)
            try {
                assertEquals(listOf(original), reopened.search("Tangerine"))
                val path = original.removePrefix("https://genui-assets.openbitfun.invalid")
                assertEquals("image/png", assertNotNull(reopened.picture(path)).mimeType)
                assertNull(reopened.picture("/photo/0000000000000000"))
            } finally { reopened.close() }
        } finally { directory.deleteRecursively() }
    }
}
