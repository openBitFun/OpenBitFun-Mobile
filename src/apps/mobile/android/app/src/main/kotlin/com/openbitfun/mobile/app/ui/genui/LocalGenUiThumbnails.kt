package com.openbitfun.mobile.app.ui.genui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.AtomicFile
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import com.openbitfun.mobile.app.platform.updatePinnedMiniAppShortcut
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

private data class SavedThumbnail(val sourceRevision: Int, val version: Long)

private val savedThumbnails = MutableStateFlow<Map<String, SavedThumbnail>>(emptyMap())
private val thumbnailWrites = Dispatchers.IO.limitedParallelism(1)
private val thumbnailId = Regex("local-genui:[0-9a-f-]{36}")
internal const val GENUI_THUMBNAIL_MAX_PIXELS = 480

@Composable
internal fun rememberGenUiThumbnail(id: String): ImageBitmap? {
    val context = LocalContext.current.applicationContext
    var thumbnail by remember(id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(context, id) {
        savedThumbnails.map { it[id]?.version }.distinctUntilChanged().collectLatest {
            thumbnail = withContext(Dispatchers.IO) { readGenUiThumbnail(context, id)?.asImageBitmap() }
        }
    }
    return thumbnail
}

internal fun readGenUiThumbnail(context: Context, id: String): Bitmap? {
    val path = thumbnailPath(context, id)?.takeIf { it.isFile } ?: return null
    val image = BitmapFactory.decodeFile(path.path) ?: return null
    val side = minOf(image.width, image.height)
    // Earlier builds stored the whole WebView instead of its top square.
    val square = Bitmap.createBitmap(image, 0, 0, side, side)
    if (square !== image) image.recycle()
    if (side <= GENUI_THUMBNAIL_MAX_PIXELS) return square
    return Bitmap.createScaledBitmap(square, GENUI_THUMBNAIL_MAX_PIXELS, GENUI_THUMBNAIL_MAX_PIXELS, true)
        .also { square.recycle() }
}

internal suspend fun saveGenUiThumbnail(context: Context, id: String, title: String, sourceRevision: Int, bitmap: Bitmap) {
    withContext(thumbnailWrites) {
        val path = thumbnailPath(context, id) ?: return@withContext
        val previous = savedThumbnails.value[id]
        if (previous != null && previous.sourceRevision > sourceRevision) return@withContext
        if (!writeThumbnail(path, bitmap)) return@withContext
        // Publish only after readers can open the completed file. The document
        // revision may already be visible when its screenshot finishes.
        val saved = SavedThumbnail(sourceRevision, (previous?.version ?: 0L) + 1L)
        savedThumbnails.value = savedThumbnails.value + (id to saved)
        updatePinnedMiniAppShortcut(context, id, title, bitmap)
    }
}

private fun thumbnailPath(context: Context, id: String): File? {
    if (!thumbnailId.matches(id)) return null
    return File(File(context.filesDir, "genui-thumbnails"), id.substringAfter(':') + ".png")
}

private fun writeThumbnail(path: File, bitmap: Bitmap): Boolean = runCatching {
    path.parentFile?.mkdirs()
    val file = AtomicFile(path)
    val stream = file.startWrite()
    try {
        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
        file.finishWrite(stream)
    } catch (error: Exception) {
        file.failWrite(stream)
        throw error
    }
}.isSuccess
