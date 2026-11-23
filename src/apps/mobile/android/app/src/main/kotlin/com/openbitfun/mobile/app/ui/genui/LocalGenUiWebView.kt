package com.openbitfun.mobile.app.ui.genui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ApplicationInfo
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.HapticFeedbackConstants
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.viewinterop.AndroidView
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaboration
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaborationRequest
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaborationResult
import com.openbitfun.mobile.core.feature.genui.LocalGenUiApp
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendar
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendarAction
import com.openbitfun.mobile.core.feature.genui.LocalGenUiDocument
import com.openbitfun.mobile.core.feature.genui.LocalGenUiIntent
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCameraStatus
import com.openbitfun.mobile.core.feature.genui.LocalGenUiGestures
import com.openbitfun.mobile.core.feature.genui.LocalGenUiPosePoint
import com.openbitfun.mobile.core.feature.genui.LocalGenUiMedia
import org.json.JSONObject
import java.io.ByteArrayInputStream
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

private const val LOOK_KEY = "local_genui_look"

private enum class GenUiLook(val id: String, val label: Int) {
    CLASSIC("classic", R.string.genui_look_classic),
    AURORA("aurora", R.string.genui_look_aurora),
    BLUEPRINT("blueprint", R.string.genui_look_blueprint),
    CELADON("celadon", R.string.genui_look_celadon),
}

@Composable
private fun rememberGenUiLook(): Pair<GenUiLook, (GenUiLook) -> Unit> {
    val context = LocalContext.current
    val preferences = remember(context) { context.getSharedPreferences("openbitfun_app_settings", Context.MODE_PRIVATE) }
    var selected by remember(preferences) {
        mutableStateOf(GenUiLook.entries.firstOrNull { it.id == preferences.getString(LOOK_KEY, null) } ?: GenUiLook.AURORA)
    }
    DisposableEffect(preferences) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == LOOK_KEY) {
                selected = GenUiLook.entries.firstOrNull { it.id == preferences.getString(key, null) } ?: GenUiLook.AURORA
            }
        }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return selected to { preferences.edit().putString(LOOK_KEY, it.id).apply() }
}

@Composable
private fun currentGenUiLook(): String = rememberGenUiLook().first.id

@Composable
internal fun LocalGenUiLookSettings() {
    val (selected, save) = rememberGenUiLook()
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable { open = true }.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.genui_look), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(selected.label), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            GenUiLook.entries.forEach { look ->
                DropdownMenuItem(text = { Text(stringResource(look.label)) }, onClick = { save(look); open = false })
            }
        }
    }
}

private const val origin = "openbitfun-genui.invalid"
private const val assetOrigin = "genui-assets.openbitfun.invalid"

@SuppressLint("SetJavaScriptEnabled")
@Composable
internal fun LocalGenUiWebView(
    app: LocalGenUiApp,
    stateWriteSerial: Int,
    conflict: Boolean,
    dispatch: (LocalGenUiIntent) -> Unit,
    media: LocalGenUiMedia,
    orientation: GenUiOrientation,
    modifier: Modifier,
    capture: Int = 0,
    onCaptured: () -> Unit = {},
    liveControls: Boolean = false,
    calendar: LocalGenUiCalendarRunner? = null,
    onCalendarResult: (LocalGenUiCalendarAction, Long?) -> Unit = { _, _ -> },
) {
    val scheme = if (MaterialTheme.colorScheme.background.luminance() > .5f) "light" else "dark"
    val locale = if (LocalConfiguration.current.locales[0].language == "zh") "zh-CN" else "en-US"
    val density = LocalDensity.current
    val layout = LocalLayoutDirection.current
    val inset = WindowInsets.safeDrawing
    val chrome = if (liveControls) {
        MobileDesignGeometry.GenuiAppControlTopInset + MobileDesignGeometry.GenuiAppControlSize
    } else 0.dp
    val insets = with(density) {
        LocalGenUiDocument.insets(
            (inset.getTop(density).toDp() + chrome).value.roundToInt(),
            inset.getLeft(density, layout).toDp().value.roundToInt(),
            inset.getRight(density, layout).toDp().value.roundToInt(),
            inset.getBottom(density).toDp().value.roundToInt(),
        )
    }
    val look = currentGenUiLook()
    val scope = rememberCoroutineScope()
    val host = remember(orientation, media, scope, liveControls) { LocalGenUiWebHost(orientation, media, scope, liveControls) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(host, lifecycle, liveControls) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) host.cancelCollaboration()
            host.setVisible(liveControls && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        }
        lifecycle.addObserver(observer)
        host.setVisible(liveControls && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        onDispose {
            lifecycle.removeObserver(observer)
            host.setVisible(false)
        }
    }
    val currentCaptureComplete by rememberUpdatedState(onCaptured)
    LaunchedEffect(capture) {
        if (capture == 0) return@LaunchedEffect
        host.captureThumbnail(app)
        currentCaptureComplete()
    }
    BoxWithConstraints(modifier) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    layoutParams = android.view.ViewGroup.LayoutParams(
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
                        if (bottom - top != oldBottom - oldTop) host.updateHeight((bottom - top) / resources.displayMetrics.density)
                    }
                    settings.javaScriptEnabled = true
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    settings.javaScriptCanOpenWindowsAutomatically = false
                    settings.setSupportMultipleWindows(false)
                    webViewClient = LocalGenUiAssetClient(context, media, host::appId)
                    addJavascriptInterface(host, "genuiNative")
                    host.attach(this, context.assets.open("genui/runtime-manifest.json").bufferedReader().use { it.readText() })
                    loadUrl("https://$origin/index.html")
                }
            },
            update = { host.update(app, stateWriteSerial, conflict, scheme, locale, look, insets, dispatch, calendar, onCalendarResult) },
            onRelease = {
                host.detach()
                it.removeJavascriptInterface("genuiNative")
                it.stopLoading()
                it.destroy()
            },
        )
        if (liveControls) LocalGenUiCamera(
            subscribed = host.cameraSubscribed,
            wanted = host.cameraWanted,
            landscape = maxWidth > maxHeight,
            compact = maxHeight < MobileDesignGeometry.GenuiCameraCompactHeightThreshold,
            onStatus = host::cameraStatus,
            onPose = host::poseFrame,
            modifier = Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(
                end = MobileDesignGeometry.GenuiCameraSideInset,
                bottom = MobileDesignGeometry.GenuiCameraBottomInset,
            ),
        )
    }
    host.collaboration?.let { request ->
        key(request) {
            LocalGenUiReceiveImage(media, request) { status, reason, asset ->
                host.finishCollaboration(request, status, reason, asset)
            }
        }
    }
}

private class LocalGenUiAssetClient(
    private val context: Context,
    private val media: LocalGenUiMedia,
    private val activeApp: () -> String?,
) : WebViewClient() {
    private val files = mapOf(
        "/index.html" to "text/html",
        "/runtime.js" to "text/javascript",
        "/runtime.css" to "text/css",
        "/fonts/hm-symbol/HMSymbolVF.ttf" to "font/ttf",
    )

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
        val uri = request.url
        val path = uri.path
        val mime = files[path]
        if (!request.isForMainFrame && request.method == "GET" && uri.scheme == "https" &&
            uri.encodedAuthority == assetOrigin && uri.encodedQuery == null && uri.encodedFragment == null
        ) {
            val collaboration = path?.startsWith("/collaboration/") == true
            val owner = activeApp()
            val bytes = runCatching {
                runBlocking(Dispatchers.IO) {
                    val encoded = uri.encodedPath ?: return@runBlocking null
                    if (collaboration) owner?.let { media.readCollaboration(encoded, it) }
                    else media.read(encoded)
                }
            }.getOrNull()
            if (bytes != null && (!collaboration || activeApp() == owner)) {
                val cache = if (collaboration) "no-store" else "max-age=31536000, immutable"
                return WebResourceResponse(bytes.mimeType, null, 200, "OK",
                    mapOf("Cache-Control" to cache), ByteArrayInputStream(bytes.bytes))
            }
        }
        if (uri.scheme == "https" && uri.encodedAuthority == origin && uri.query == null && mime != null) {
            val asset = runCatching { context.assets.open("genui/runtime$path") }.getOrNull()
            if (asset != null) return WebResourceResponse(mime, "UTF-8", asset)
        }
        return WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))
    }
}

private class LocalGenUiWebHost(
    private val orientation: GenUiOrientation,
    private val media: LocalGenUiMedia,
    private val scope: CoroutineScope,
    private val liveControls: Boolean,
) {
    @Volatile private var web: WebView? = null
    private var manifest = ""
    private var catalog = ""
    @Volatile private var mounted: LocalGenUiApp? = null
    private var stateSerial = 0
    private var scheme = "light"
    private var locale = "en-US"
    private var look = "aurora"
    private var insets = ""
    private var height = 0
    private var booted = false
    private var actionTime = 0L
    private var hapticTime = 0L
    private var dispatch: ((LocalGenUiIntent) -> Unit)? = null
    private var calendar: LocalGenUiCalendarRunner? = null
    private var onCalendarResult: ((LocalGenUiCalendarAction, Long?) -> Unit)? = null
    private val calendarPending = mutableSetOf<Pair<String, String>>()
    private val completedCalendar = mutableSetOf<Pair<String, String>>()
    private val calendarCalls = ArrayDeque<Long>()
    private val searchCalls = ArrayDeque<Long>()
    private val gestures = LocalGenUiGestures()
    var cameraWanted by mutableStateOf(false)
        private set
    var cameraSubscribed by mutableStateOf(false)
        private set

    var collaboration by mutableStateOf<LocalGenUiCollaborationRequest?>(null)
        private set

    fun appId(): String? = mounted?.id

    fun cancelCollaboration() {
        collaboration?.let { finishCollaboration(it, LocalGenUiCollaborationResult.CANCELLED, "localCancelled", "") }
    }

    fun finishCollaboration(
        request: LocalGenUiCollaborationRequest,
        status: LocalGenUiCollaborationResult,
        reason: String,
        asset: String,
    ) {
        if (collaboration !== request) {
            if (asset.isNotEmpty()) scope.launch { LocalGenUiCollaboration.discard(media, request, asset) }
            return
        }
        collaboration = null
        send(LocalGenUiCollaboration.reply(request, status, reason, asset))
    }

    private fun handleCollaboration(raw: String, app: LocalGenUiApp) {
        val request = LocalGenUiCollaboration.request(raw, app) ?: return
        val pending = collaboration
        when {
            request.kind == null -> if (pending?.id == request.id) cancelCollaboration()
            !liveControls -> send(LocalGenUiCollaboration.reply(request, LocalGenUiCollaborationResult.UNAVAILABLE, "missingSyscap", ""))
            pending != null -> if (pending.id != request.id) {
                send(LocalGenUiCollaboration.reply(request, LocalGenUiCollaborationResult.FAILED, "busy", ""))
            }
            else -> {
                collaboration = request
                send(LocalGenUiCollaboration.reply(request, LocalGenUiCollaborationResult.PENDING, "", ""))
            }
        }
    }

    fun setVisible(visible: Boolean) = applyGestureReplies(gestures.setVisible(visible))
    fun cameraStatus(status: LocalGenUiCameraStatus) = applyGestureReplies(gestures.cameraStatus(status))
    fun poseFrame(points: List<LocalGenUiPosePoint>) = applyGestureReplies(gestures.frame(points))

    private fun applyGestureReplies(replies: List<String> = emptyList()) {
        cameraSubscribed = gestures.hasSubscriptions
        cameraWanted = gestures.cameraWanted
        replies.forEach(::send)
    }

    fun attach(view: WebView, manifestJson: String) {
        web = view
        manifest = manifestJson
        catalog = runCatching { view.context.assets.open("genui/catalog.json").bufferedReader().use { it.readText() } }.getOrDefault("")
    }

    private fun snapshot(): Bitmap? {
        val view = web ?: return null
        val side = minOf(view.width, view.height)
        if (!booted || side <= 0) return null
        val size = side.coerceAtMost(GENUI_THUMBNAIL_MAX_PIXELS)
        val scale = size.toFloat() / side
        return runCatching {
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { image ->
                Canvas(image).apply { scale(scale, scale); view.draw(this) }
            }
        }.getOrNull()
    }

    suspend fun captureThumbnail(app: LocalGenUiApp) {
        val current = mounted ?: return
        if (current.id != app.id || current.sourceRevision != app.sourceRevision || current.checking || current.streaming) return
        val context = web?.context?.applicationContext ?: return
        val bitmap = snapshot() ?: return
        try {
            saveGenUiThumbnail(context, app.id, app.title, app.sourceRevision, bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    fun detach() {
        val activity = web?.context?.activity()
        if (activity?.isChangingConfigurations != true) orientation.restore(activity)
        web = null
        dispatch = null
        calendar = null
        onCalendarResult = null
        mounted = null
        collaboration = null
        gestures.mount(null)
        applyGestureReplies()
        booted = false
    }

    fun update(
        app: LocalGenUiApp, serial: Int, conflict: Boolean, nextScheme: String,
        nextLocale: String, nextLook: String, nextInsets: String, onIntent: (LocalGenUiIntent) -> Unit,
        calendarRunner: LocalGenUiCalendarRunner?,
        reportCalendarResult: (LocalGenUiCalendarAction, Long?) -> Unit,
    ) {
        val previous = mounted
        val mountChanged = previous?.id != app.id || previous.sourceRevision != app.sourceRevision ||
            previous.streaming != app.streaming || previous.checking != app.checking || previous.reopening != app.reopening || locale != nextLocale
        val themeChanged = scheme != nextScheme || look != nextLook
        val insetsChanged = insets != nextInsets
        dispatch = onIntent
        calendar = calendarRunner
        onCalendarResult = reportCalendarResult
        mounted = app
        scheme = nextScheme
        locale = nextLocale
        look = nextLook
        insets = nextInsets
        if (previous != null && previous.id != app.id) orientation.restore(web?.context?.activity())
        if (booted) {
            when {
                mountChanged -> mount()
                previous?.source != app.source -> send(LocalGenUiDocument.updateSource(app))
                serial != stateSerial -> send(LocalGenUiDocument.state(app, conflict))
            }
            if (!mountChanged && themeChanged) send(LocalGenUiDocument.theme(scheme, look))
            if (insetsChanged) send(insets)
        }
        stateSerial = serial
    }

    @JavascriptInterface
    fun post(raw: String) {
        if (raw.length > 512 * 1024) return
        val view = web ?: return
        view.post { if (web === view) receive(raw) }
    }

    private fun receive(raw: String) {
        val event = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val type = event.optString("type")
        if (type == "boot") {
            booted = true
            applyHeight()
            send(insets)
            mount()
            return
        }
        val app = mounted ?: return
        if (type == "image_search") {
            val search = LocalGenUiMedia.request(raw, app) ?: return
            val now = android.os.SystemClock.elapsedRealtime()
            while (searchCalls.firstOrNull()?.let { now - it >= 60_000 } == true) searchCalls.removeFirst()
            if (searchCalls.size >= 60) {
                send(LocalGenUiMedia.refused(search))
                return
            }
            searchCalls.addLast(now)
            scope.launch {
                val reply = media.search(search)
                val current = mounted
                if (current?.id == app.id && current.sourceRevision == app.sourceRevision && !current.checking) send(reply)
            }
            return
        }
        if (app.checking) {
            if (type == "ready") {
                val activity = web?.context?.activity()
                if (app.reopening && activity != null &&
                    activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                    activity.intent?.getBooleanExtra("openbitfun.test.holdGenUiReopen", false) == true
                ) return
                LocalGenUiDocument.merge(app)?.let(::send)
                send(LocalGenUiDocument.probe(app))
            } else LocalGenUiDocument.readIntent(raw, app, catalog)?.let { dispatch?.invoke(it) }
            return
        }
        if (event.optString("appId") != app.id || app.streaming) return
        if (type == "preview_ready") {
            if (liveControls && event.optInt("sourceRevision", -1) == app.sourceRevision) {
                scope.launch { captureThumbnail(app) }
            }
            return
        }
        val intent = LocalGenUiDocument.readIntent(raw, app, catalog)
        if (intent != null) {
            if (intent is LocalGenUiIntent.ContinueConversation) {
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - actionTime < 1000) return
                actionTime = now
            }
            dispatch?.invoke(intent)
            return
        }
        val requestId = event.optString("requestId").takeIf { it.isNotBlank() && it.length <= 64 }
        when (type) {
            "action" -> if (LocalGenUiCalendar.isCalendarAction(event.optString("action")) &&
                event.optInt("sourceRevision", -1) == app.sourceRevision
            ) handleCalendar(raw, app, requestId)
            "collaboration" -> handleCollaboration(raw, app)
            "capability" -> applyGestureReplies(gestures.receive(raw))
            "orientation" -> {
                if (event.optInt("sourceRevision", -1) != app.sourceRevision) return
                val requested = when (event.optString("orientation")) {
                    "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                    "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    "auto" -> { orientation.restore(web?.context?.activity()); return }
                    else -> return
                }
                orientation.request(web?.context?.activity(), requested)
            }
            "haptic" -> {
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - hapticTime < 120) return
                hapticTime = now
                web?.performHapticFeedback(if (event.optString("kind") == "heavy") HapticFeedbackConstants.LONG_PRESS else HapticFeedbackConstants.CLOCK_TICK)
            }
        }
    }

    fun updateHeight(value: Float) {
        height = value.toInt().coerceAtLeast(0)
        if (booted) applyHeight()
    }

    private fun applyHeight() {
        if (height > 0) web?.evaluateJavascript(
            "document.documentElement.style.setProperty('--genui-host-height','${height}px')",
            null,
        )
    }

    private fun handleCalendar(raw: String, app: LocalGenUiApp, requestId: String?) {
        fun reply(ok: Boolean) {
            if (requestId != null) send(LocalGenUiCalendar.result(app, requestId, ok))
        }
        val request = LocalGenUiCalendar.read(raw, app)
        val runner = calendar
        if (request == null || runner == null) {
            reply(false)
            return
        }
        val receipt = request.receipt?.let { app.id to it }
        if (receipt != null) {
            if (receipt.second in app.calendarReceipts || receipt in completedCalendar) {
                reply(true)
                return
            }
            if (receipt in calendarPending) return
        }
        val cutoff = android.os.SystemClock.elapsedRealtime() - 60_000
        while (calendarCalls.firstOrNull()?.let { it <= cutoff } == true) calendarCalls.removeFirst()
        if (calendarCalls.size >= 30) {
            reply(false)
            onCalendarResult?.invoke(request.action, null)
            return
        }
        calendarCalls.addLast(android.os.SystemClock.elapsedRealtime())
        if (receipt != null) calendarPending.add(receipt)
        val recordReceipt = dispatch
        val isCurrent = { mounted?.let { it.id == app.id && it.sourceRevision == app.sourceRevision && !it.streaming && !it.checking } == true }
        runner.run(request, isCurrent) { result ->
            if (receipt != null) {
                calendarPending.remove(receipt)
                if (result != null) {
                    completedCalendar += receipt
                    recordReceipt?.invoke(LocalGenUiIntent.RecordCalendarReceipt(app.id, receipt.second))
                }
            }
            if (isCurrent()) {
                reply(result != null)
                onCalendarResult?.invoke(request.action, result)
            }
        }
    }

    private fun mount() {
        collaboration = null
        gestures.mount(mounted)
        applyGestureReplies()
        mounted?.let { app ->
            send(LocalGenUiDocument.mount(manifest, app, scheme, locale, look, imageSearchAvailable = true))
            if (!app.checking && !app.streaming) {
                if (calendar != null) send(LocalGenUiCalendar.receipts(app))
                send(LocalGenUiCollaboration.availability(app, liveControls))
            }
        }
    }

    private fun send(message: String) {
        if (message.isNotEmpty()) web?.evaluateJavascript("window.__genuiHost?.receive(${JSONObject.quote(message)})", null)
    }
}

internal fun Context.activity(): Activity? {
    var context = this
    while (context is ContextWrapper && context !is Activity) {
        val base = context.baseContext
        if (base === context) break
        context = base
    }
    return context as? Activity
}

internal class GenUiOrientation {
    private var original: Int? = null

    fun request(activity: Activity?, orientation: Int) {
        if (activity == null || activity.requestedOrientation == orientation) return
        if (original == null) original = activity.requestedOrientation
        activity.requestedOrientation = orientation
    }

    fun restore(activity: Activity?) {
        original?.let { activity?.requestedOrientation = it }
        original = null
    }
}
