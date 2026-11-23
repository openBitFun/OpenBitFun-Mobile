package com.openbitfun.mobile.app.platform

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.os.Build
import com.openbitfun.mobile.app.MainActivity

internal const val MINI_APP_ACTION = "com.openbitfun.mobile.OPEN_MINI_APP"
internal const val MINI_APP_ID_EXTRA = "miniapp_id"

internal fun requestMiniAppShortcut(
    context: Context,
    id: String,
    title: String,
    cover: Int,
    preview: Bitmap?,
    revealHome: Boolean,
): Boolean = runCatching {
    val manager = context.getSystemService(ShortcutManager::class.java) ?: return false
    val icon = preview?.let { previewIcon(manager, it) } ?: Icon.createWithResource(context, cover)
    val onPinned = if (revealHome) openHomeAfterPin(context) else null
    manager.requestPinShortcut(shortcut(context, id, title, icon), onPinned)
}.getOrDefault(false)

internal fun updatePinnedMiniAppShortcut(context: Context, id: String, title: String, preview: Bitmap) {
    val manager = context.getSystemService(ShortcutManager::class.java) ?: return
    runCatching {
        if (manager.pinnedShortcuts.any { it.id == id }) {
            manager.updateShortcuts(listOf(shortcut(context, id, title, previewIcon(manager, preview))))
        }
    }
}

private fun shortcut(context: Context, id: String, title: String, icon: Icon): ShortcutInfo {
    val launch = Intent(context, MainActivity::class.java).setAction(MINI_APP_ACTION).putExtra(MINI_APP_ID_EXTRA, id)
    return ShortcutInfo.Builder(context, id).setShortLabel(title).setIntent(launch).setIcon(icon).build()
}

private fun previewIcon(manager: ShortcutManager, preview: Bitmap): Icon {
    val side = minOf(preview.width, preview.height, manager.iconMaxWidth, manager.iconMaxHeight)
    return Icon.createWithBitmap(Bitmap.createScaledBitmap(preview, side, side, true))
}

@Suppress("DEPRECATION")
private fun openHomeAfterPin(context: Context): IntentSender {
    val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val options = if (Build.VERSION.SDK_INT >= 35) ActivityOptions.makeBasic().apply {
        val mode = if (Build.VERSION.SDK_INT >= 36) ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE
        else ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        setPendingIntentCreatorBackgroundActivityStartMode(mode)
    }.toBundle() else null
    return PendingIntent.getActivity(context, 0, home,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_CANCEL_CURRENT, options).intentSender
}
