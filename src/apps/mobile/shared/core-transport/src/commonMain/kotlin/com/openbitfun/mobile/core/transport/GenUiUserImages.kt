package com.openbitfun.mobile.core.transport

import com.openbitfun.mobile.core.crypto.DeviceIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray

/** User attachments survive a cache clear. The mounted app is part of every lookup. */
public class GenUiUserImages(directory: String) {
    private val root = Path(directory)

    public suspend fun read(appId: String, path: String): ByteArray? = withContext(Dispatchers.IO) {
        val name = fileName(appId, path) ?: return@withContext null
        val location = Path(folder(appId), name)
        runCatching {
            val size = SystemFileSystem.metadataOrNull(location)?.size ?: return@runCatching null
            if (size !in 4L..GenUiImageTransfer.MAX_IMAGE_BYTES.toLong()) return@runCatching null
            SystemFileSystem.source(location).buffered().use { it.readByteArray(size.toInt()) }
                .takeIf(GenUiImageTransfer::isJpeg)
        }.getOrNull()
    }

    // Called on the transfer's I/O dispatcher. There is no suspension between
    // the atomic move and return of the asset, so cancellation can reclaim it.
    public fun write(appId: String, bytes: ByteArray): String {
        require(GenUiImageTransfer.isJpeg(bytes))
        val folder = folder(appId)
        SystemFileSystem.createDirectories(folder)
        val name = "${DeviceIdentity.randomBytes(16).toHexString()}.jpg"
        val temp = Path(folder, "$name.tmp")
        try {
            SystemFileSystem.sink(temp).buffered().use { it.write(bytes) }
            SystemFileSystem.atomicMove(temp, Path(folder, name))
        } catch (error: Exception) {
            runCatching { SystemFileSystem.delete(temp, mustExist = false) }
            throw error
        }
        return ASSET_HOST + prefix(appId) + name
    }

    public fun discard(appId: String, url: String) {
        if (!url.startsWith(ASSET_HOST)) return
        val name = fileName(appId, url.removePrefix(ASSET_HOST)) ?: return
        SystemFileSystem.delete(Path(folder(appId), name), mustExist = false)
    }

    private fun folder(appId: String): Path {
        require(APP_ID.matches(appId))
        return Path(root, appId.substringAfter(':'))
    }

    private fun fileName(appId: String, path: String): String? {
        if (!APP_ID.matches(appId)) return null
        val prefix = prefix(appId)
        if (!path.startsWith(prefix)) return null
        return path.removePrefix(prefix).takeIf(NAME::matches)
    }

    private fun prefix(appId: String): String = "/collaboration/${appId.replace(":", "%3A")}/"

    private companion object {
        const val ASSET_HOST = "https://genui-assets.openbitfun.invalid"
        val APP_ID = Regex("local-genui:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
        val NAME = Regex("[0-9a-f]{32}\\.jpg")
    }
}
