package com.openbitfun.mobile.app.ui.miniapps

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutManager
import android.widget.Toast
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.zIndex
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.platform.MINI_APP_ACTION
import com.openbitfun.mobile.app.platform.MINI_APP_ID_EXTRA
import com.openbitfun.mobile.app.platform.requestMiniAppShortcut
import com.openbitfun.mobile.app.ui.genui.LocalGenUiDialog
import com.openbitfun.mobile.app.ui.genui.LocalGenUiModel
import com.openbitfun.mobile.app.ui.genui.readGenUiThumbnail
import com.openbitfun.mobile.app.ui.genui.rememberGenUiThumbnail
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.genui.LocalGenUiIntent
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as G
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignMotion as Motion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.roundToInt
import org.json.JSONObject
import java.io.ByteArrayInputStream
import androidx.lifecycle.ViewModel

/** Local, bundled tools remain available without an account or a connected host. */
@Composable
internal fun MiniAppsButton(
    sidebar: Boolean = false,
    explore: Boolean = false,
    contentColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.primary,
) {
    var open by rememberSaveable { mutableStateOf(false) }
    if (sidebar) {
        Row(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 8.dp).heightIn(min = 48.dp)
            .clip(RoundedCornerShape(12.dp)).clickable { open = true }
            .padding(start = 4.dp, end = 8.dp).testTag("sidebar-miniapps"),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(R.drawable.ic_symbol_square_grid_2x2), contentDescription = null, modifier = Modifier.size(24.dp))
            Text(stringResource(R.string.miniapps_title), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        }
    } else TextButton(
        onClick = { open = true },
        modifier = Modifier.fillMaxWidth().height(44.dp),
        contentPadding = PaddingValues(0.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = contentColor),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(if (explore) R.string.miniapps_explore else R.string.miniapps_title), style = MaterialTheme.typography.labelSmall)
            Icon(
                painter = painterResource(R.drawable.ic_symbol_chevron_right),
                contentDescription = null,
                modifier = Modifier.padding(start = 5.dp).size(12.dp),
            )
        }
    }
    if (open) MiniAppsDialog { open = false }
}

private data class MiniAppEntry(val id: String, val name: String, val description: String, val generated: Boolean = false) {
    val cover: Int
        get() = when (id) {
            "builtin-gomoku" -> R.drawable.miniapp_gomoku_preview
            "builtin-regex-playground" -> R.drawable.miniapp_regex_preview
            "builtin-daily-divination" -> R.drawable.miniapp_divination_preview
            else -> if (generated) R.mipmap.ic_launcher else R.drawable.miniapp_divination_preview
        }
}

internal class MiniAppsBrowseState : ViewModel() {
    var focused by mutableStateOf<String?>(null)
    var list by mutableStateOf(false)
}

@Composable
internal fun MiniAppsDialog(initialAppId: String? = null, onClose: () -> Unit) {
    val local: LocalGenUiModel = viewModel()
    val browse: MiniAppsBrowseState = viewModel()
    val genUi by local.store.state.collectAsStateWithLifecycle()
    var generated by rememberSaveable(initialAppId) { mutableStateOf(initialAppId?.takeIf { it.startsWith("local-genui:") }) }
    val context = LocalContext.current
    val locale = if (LocalConfiguration.current.locales[0].language == "zh") "zh-CN" else "en-US"
    var selected by rememberSaveable(initialAppId) { mutableStateOf(initialAppId?.takeUnless { it.startsWith("local-genui:") }) }
    var focused by browse::focused
    var list by browse::list
    var retry by remember { mutableIntStateOf(0) }
    val catalog = remember(retry, locale) {
        runCatching {
            val array = org.json.JSONArray(context.assets.open("miniapps/catalog.json").bufferedReader().use { it.readText() })
            List(array.length()) { index ->
                val app = array.getJSONObject(index)
                val locales = app.getJSONObject("locales")
                val copy = locales.optJSONObject(locale) ?: locales.getJSONObject("en-US")
                MiniAppEntry(app.getString("id"), copy.getString("name"), copy.getString("description"))
            }
        }
    }
    val generatedLabel = stringResource(R.string.genui_generated_app)
    val apps = catalog.getOrDefault(emptyList()) + genUi.galleryApps.map {
        MiniAppEntry(it.id, it.title, generatedLabel, generated = true)
    }
    val current = apps.firstOrNull { it.id == selected }
    val goBack = { if (selected != null && initialAppId == null) selected = null else onClose() }
    val standalone = generated
    if (standalone != null) {
        LocalGenUiDialog(initialAppId = standalone, model = local) {
            if (initialAppId != null) onClose() else generated = null
        }
        return
    }
    val pinSupport = context.getSystemService(ShortcutManager::class.java)?.isRequestPinShortcutSupported == true
    val scope = rememberCoroutineScope()
    val onPin: ((MiniAppEntry, Boolean) -> Unit)? = if (pinSupport) {
        { item, revealHome -> scope.launch { requestMiniAppPin(context, item, revealHome) } }
    } else null
    val desktopDrag = remember { MiniAppDesktopDrag() }
    Dialog(onDismissRequest = goBack, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        val lightBackground = desktopDrag.item == null && MaterialTheme.colorScheme.background.luminance() > 0.5f
        SideEffect {
            window?.let {
                WindowCompat.getInsetsController(it, it.decorView).apply {
                    isAppearanceLightStatusBars = lightBackground
                    isAppearanceLightNavigationBars = lightBackground
                }
            }
        }
        Surface(Modifier.fillMaxSize().onGloballyPositioned { desktopDrag.window = it },
            color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(
                    Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = goBack, modifier = Modifier.size(48.dp)) {
                        Icon(painterResource(R.drawable.ic_symbol_chevron_left), stringResource(R.string.miniapps_back))
                    }
                    Text(
                        current?.name ?: stringResource(R.string.miniapps_title),
                        modifier = Modifier.weight(1f), textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    if (current == null) {
                        IconButton(onClick = { list = !list }, Modifier.size(48.dp).testTag("miniapp-view-toggle")) {
                            Box(
                                Modifier.size(G.MiniappViewToggleSurfaceSize)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    painterResource(if (list) R.drawable.ic_miniapp_view_cards else R.drawable.ic_miniapp_view_list),
                                    stringResource(if (list) R.string.miniapps_show_cards else R.string.miniapps_show_list),
                                    Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    } else Spacer(Modifier.width(48.dp))
                }
                when {
                    current != null -> key(current.id, locale) { MiniAppWebView(current.id, locale, Modifier.weight(1f)) }
                    catalog.isFailure -> Column(Modifier.padding(16.dp)) {
                        Text(stringResource(R.string.miniapps_load_failed))
                        TextButton(onClick = { retry++ }) { Text(stringResource(R.string.account_devices_retry)) }
                    }
                    else -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.TopCenter) {
                        MiniAppGallery(
                            apps = apps, focused = focused, list = list,
                            desktopDrag = desktopDrag,
                            onFocus = { focused = it.id },
                            onSelect = {
                                focused = it.id
                                if (it.generated) generated = it.id else selected = it.id
                            },
                            onPin = onPin,
                            onRemove = { local.store.dispatch(LocalGenUiIntent.SetGallery(it.id, false)) },
                            modifier = Modifier.widthIn(max = 1000.dp).fillMaxSize(),
                        )
                    }
                }
            }
            desktopDrag.item?.let { MiniAppDesktopOverlay(it, desktopDrag, Modifier.fillMaxSize()) }
        }
    }
}

@Composable
private fun MiniAppGallery(
    apps: List<MiniAppEntry>,
    focused: String?,
    list: Boolean,
    desktopDrag: MiniAppDesktopDrag,
    onFocus: (MiniAppEntry) -> Unit,
    onSelect: (MiniAppEntry) -> Unit,
    onPin: ((MiniAppEntry, Boolean) -> Unit)?,
    onRemove: (MiniAppEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (apps.isEmpty()) return
    val index = apps.indexOfFirst { it.id == focused }.coerceAtLeast(0)
    val nextLabel = stringResource(R.string.miniapps_next)
    val previousLabel = stringResource(R.string.miniapps_previous)
    val pinLabel = stringResource(R.string.miniapps_pin)
    val removeLabel = stringResource(R.string.genui_remove_gallery)
    var menuId by remember { mutableStateOf<String?>(null) }
    val lifted = desktopDrag.item
    val deckIndex = if (lifted == null || apps.size == 1) index else if (index < apps.lastIndex) index + 1 else index - 1
    BoxWithConstraints(modifier.testTag("miniapps-gallery"), contentAlignment = Alignment.Center) {
        val width = maxWidth
        if (list) {
            val rowShape = RoundedCornerShape(G.MiniappListRadius)
            LazyVerticalGrid(
                columns = GridCells.Fixed(if (width >= 840.dp) 2 else 1),
                horizontalArrangement = Arrangement.spacedBy(G.MiniappListGap),
                verticalArrangement = Arrangement.spacedBy(G.MiniappListGap),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(apps, key = MiniAppEntry::id) { app ->
                    Row(
                        Modifier.fillMaxWidth().clip(rowShape)
                            .background(MaterialTheme.colorScheme.surface)
                            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, rowShape)
                            .combinedClickable(
                                onClick = { onSelect(app) },
                                onLongClick = if (onPin != null || app.generated) ({ menuId = app.id }) else null,
                            ).testTag("miniapp:${app.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        MiniAppCover(app, Modifier.width(minOf(G.MiniappListCoverSize, width * 0.36f)).height(G.MiniappListCoverSize))
                        Box(Modifier.weight(1f)) {
                            MiniAppCopy(app, Modifier.fillMaxWidth().padding(16.dp), titleLines = 2)
                            DropdownMenu(menuId == app.id, onDismissRequest = { menuId = null }) {
                                if (onPin != null) DropdownMenuItem(text = { Text(pinLabel) }, onClick = { menuId = null; onPin(app, false) })
                                if (app.generated) DropdownMenuItem(text = { Text(removeLabel) }, onClick = { menuId = null; onRemove(app) })
                            }
                        }
                    }
                }
            }
        } else {
            val shape = RoundedCornerShape(G.MiniappCardRadius)
            val cardWidth = minOf(width * 0.82f, when {
                width >= 840.dp -> G.MiniappWideCardWidth
                width >= 600.dp -> G.MiniappFoldCardWidth
                else -> G.MiniappCardWidth
            })
            val cardMaxHeight = when {
                width >= 840.dp -> G.MiniappWideCardHeight
                width >= 600.dp -> G.MiniappFoldCardHeight
                else -> G.MiniappCardHeight
            }
            val latestFocus by rememberUpdatedState(onFocus)
            val latestPin by rememberUpdatedState(onPin)
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                BoxWithConstraints(
                    Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(0.dp))
                        .pointerInput(index, apps) {
                            var offset = 0f
                            detectHorizontalDragGestures(
                                onDragStart = { offset = 0f },
                                onDragEnd = {
                                    val direction = when {
                                        offset < -48.dp.toPx() -> 1
                                        offset > 48.dp.toPx() -> -1
                                        else -> 0
                                    }
                                    if (desktopDrag.item == null) apps.getOrNull(index + direction)?.let(latestFocus)
                                },
                            ) { _, delta -> offset += delta }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    val cardHeight = minOf(cardMaxHeight, (maxHeight - 40.dp).coerceAtLeast(0.dp))
                    apps.forEachIndexed { position, app ->
                        key(app.id) {
                            val distance = position - deckIndex
                            val active = position == index
                            val foremost = distance == 0
                            val shift by animateDpAsState((if (width >= 600.dp) 60.dp else 70.dp) * distance, tween(240), label = "card offset")
                            val tilt by animateFloatAsState(distance.coerceIn(-1, 1) * 5f, tween(240), label = "card rotation")
                            val scale by animateFloatAsState(if (foremost) 1f else .85f, tween(240), label = "card scale")
                            val opacity by animateFloatAsState(if (foremost) 1f else if (abs(distance) == 1) .6f else 0f,
                                tween(240), label = "card opacity")
                            var cardLayout by remember { mutableStateOf<LayoutCoordinates?>(null) }
                            val latestApp by rememberUpdatedState(app)
                            val interaction = if (active) Modifier.clickable { onSelect(app) }
                                .testTag("miniapp:${app.id}")
                                .semantics {
                                    customActions = buildList {
                                        apps.getOrNull(index - 1)?.let { add(CustomAccessibilityAction(previousLabel) { latestFocus(it); true }) }
                                        apps.getOrNull(index + 1)?.let { add(CustomAccessibilityAction(nextLabel) { latestFocus(it); true }) }
                                        if (onPin != null) add(CustomAccessibilityAction(pinLabel) { onPin(app, false); true })
                                        if (app.generated) add(CustomAccessibilityAction(removeLabel) { onRemove(app); true })
                                    }
                                } else Modifier.semantics { hideFromAccessibility() }
                            val drag = if (active && onPin != null) Modifier.onGloballyPositioned { cardLayout = it }
                                .pointerInput(app.id) {
                                    detectDragGesturesAfterLongPress(
                                        onDragStart = { desktopDrag.begin(latestApp, cardLayout, it) },
                                        onDragCancel = desktopDrag::end,
                                        onDragEnd = {
                                            val dropped = desktopDrag.item?.takeIf { desktopDrag.overTarget }
                                            desktopDrag.end()
                                            if (dropped != null) latestPin?.invoke(dropped, true)
                                        },
                                    ) { change, _ -> desktopDrag.move(cardLayout, change.position) }
                                } else Modifier
                            Column(
                                Modifier.zIndex(if (foremost) 3f else 1f).size(cardWidth, cardHeight)
                                    .graphicsLayer {
                                        alpha = if (lifted?.id == app.id) 0f else opacity
                                        translationX = shift.toPx()
                                        rotationZ = tilt
                                        scaleX = scale
                                        scaleY = scale
                                    }
                                    .shadow(16.dp, shape, ambientColor = openBitFunColors.shadowSubtle, spotColor = openBitFunColors.shadowSubtle).clip(shape)
                                    .background(MaterialTheme.colorScheme.surface)
                                    .then(drag).then(interaction),
                            ) {
                                MiniAppCover(app, Modifier.fillMaxWidth().height(cardHeight * .65f))
                                Box(Modifier.fillMaxWidth().weight(1f).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterStart) {
                                    MiniAppCopy(app, Modifier.fillMaxWidth(), titleLines = 1)
                                }
                            }
                        }
                    }
                }
                Row(Modifier.padding(top = 20.dp, bottom = 12.dp)
                    .graphicsLayer { alpha = if (lifted == null) 1f else 0f }, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    apps.indices.forEach { position ->
                        val active = position == index
                        Box(Modifier.size(if (active) 24.dp else 8.dp, 8.dp).background(
                            MaterialTheme.colorScheme.onBackground.copy(alpha = if (active) 1f else .4f),
                            RoundedCornerShape(4.dp),
                        ))
                    }
                }
                Text(
                    stringResource(if (onPin != null) R.string.miniapps_pin_hint else R.string.miniapps_swipe_hint),
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp).graphicsLayer { alpha = if (lifted == null) 1f else 0f },
                )
            }
        }
    }
}

private class MiniAppDesktopDrag {
    var window: LayoutCoordinates? = null
    var item by mutableStateOf<MiniAppEntry?>(null)
        private set
    var source by mutableStateOf(Rect.Zero)
        private set
    var pointer by mutableStateOf(Offset.Zero)
        private set
    var pickupOffset by mutableStateOf(Offset.Zero)
        private set
    var targetTop by mutableFloatStateOf(Float.POSITIVE_INFINITY)

    val overTarget: Boolean
        get() = window?.size?.let { size ->
            pointer.x in 0f..size.width.toFloat() && pointer.y in targetTop..size.height.toFloat()
        } == true

    fun begin(app: MiniAppEntry, card: LayoutCoordinates?, position: Offset) {
        val root = window?.takeIf { it.isAttached } ?: return
        if (card?.isAttached != true) return
        source = root.localBoundingBoxOf(card, clipBounds = false)
        pointer = root.localPositionOf(card, position)
        pickupOffset = source.topLeft - pointer
        targetTop = Float.POSITIVE_INFINITY
        item = app
    }

    fun move(card: LayoutCoordinates?, position: Offset) {
        val root = window?.takeIf { it.isAttached } ?: return
        if (card?.isAttached == true) pointer = root.localPositionOf(card, position)
    }

    fun end() { item = null }
}

@Composable
private fun MiniAppDesktopOverlay(app: MiniAppEntry, drag: MiniAppDesktopDrag, modifier: Modifier) {
    val contraction = remember { Animatable(0f) }
    val hint = remember { Animatable(0f) }
    var reduceMotion by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { contraction.animateTo(1f, tween(Motion.MiniappDragContract, easing = LinearOutSlowInEasing)) }
    LaunchedEffect(Unit) {
        reduceMotion = coroutineContext[MotionDurationScale]?.scaleFactor == 0f
        if (!reduceMotion) delay(Motion.MiniappDragHintDelay.toLong())
        hint.animateTo(1f, tween(Motion.MiniappDragHintFade, easing = LinearOutSlowInEasing))
    }
    val density = LocalDensity.current
    val glow = with(density) { G.MiniappDragGlowHeight + WindowInsets.safeDrawing.getBottom(this).toDp() }
    val fraction = contraction.value
    val iconSize = G.MiniappDragIconSize
    val width = with(density) { lerp(drag.source.width.toDp(), iconSize, fraction) }
    val height = with(density) { lerp(drag.source.height.toDp(), iconSize, fraction) }
    val coverHeight = with(density) { lerp(drag.source.height.toDp() * .65f, iconSize, fraction) }
    val radius = lerp(G.MiniappCardRadius, G.MiniappDragIconRadius, fraction)
    val shape = RoundedCornerShape(radius)
    val overTarget = drag.overTarget
    val light = MaterialTheme.colorScheme.background.luminance() > .5f
    val accent = if (light) MobileDesignColors.Light.ConnectHeroAccent else MobileDesignColors.Dark.ConnectHeroAccent
    val secondary = if (light) MobileDesignColors.Light.ConnectHeroSecondary else MobileDesignColors.Dark.ConnectHeroSecondary
    val ink = MobileDesignColors.Light.ContentOnAction
    val dark = MobileDesignColors.Dark.MediaBackground
    val transparent = MobileDesignColors.Dark.Transparent

    Box(modifier.clip(RoundedCornerShape(0.dp))) {
        Box(Modifier.matchParentSize().background(dark.copy(alpha = .64f * fraction)))
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(glow + G.MiniappDragTargetExtraHeight)
            .graphicsLayer { alpha = hint.value }
            .background(Brush.verticalGradient(0f to transparent, .76f to MobileDesignColors.Dark.MediaScrim, 1f to dark))) {
            val glowOpacity by animateFloatAsState(if (overTarget) .23f else .10f, tween(200), label = "desktop glow")
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(glow)
                .graphicsLayer { alpha = glowOpacity }
                .background(Brush.verticalGradient(0f to transparent, .72f to secondary, 1f to accent)))
            Canvas(Modifier.align(Alignment.BottomCenter).size(236.dp).graphicsLayer {
                scaleX = 1.35f
                scaleY = .32f
                transformOrigin = TransformOrigin(.5f, 1f)
                translationX = if (reduceMotion) 0f else (drag.pointer.x - (drag.window?.size?.width ?: 0) / 2f) * .34f
                translationY = 39.dp.toPx()
                alpha = if (overTarget) .68f else .3f
            }) {
                drawCircle(Brush.radialGradient(0f to accent, .22f to secondary, 1f to transparent))
            }
            Column(Modifier.align(Alignment.BottomCenter).widthIn(max = 420.dp).fillMaxWidth()
                .onGloballyPositioned { target ->
                    drag.window?.takeIf { it.isAttached }?.let { drag.targetTop = it.localPositionOf(target, Offset.Zero).y }
                }.padding(top = 10.dp, bottom = glow), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        repeat(2) { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                repeat(2) { column ->
                                    val tile = RoundedCornerShape(2.5.dp)
                                    if (row == 0 && column == 1) {
                                        MiniAppCover(app, Modifier.size(8.dp).graphicsLayer {
                                            rotationZ = if (overTarget) 0f else 12f
                                            translationX = if (overTarget) 0f else 3.dp.toPx()
                                            translationY = if (overTarget) 0f else -5.dp.toPx()
                                        }.border(.5.dp, ink, tile).clip(tile))
                                    } else Box(Modifier.size(8.dp).background(ink.copy(alpha = if (overTarget) .85f else .55f), tile))
                                }
                            }
                        }
                    }
                    Text(stringResource(if (overTarget) R.string.miniapps_release_pin else R.string.miniapps_drop_pin),
                        color = ink, textAlign = TextAlign.Center, maxLines = 2, fontWeight = FontWeight.Medium,
                        style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("miniapp-desktop-drop-target"))
                }
                val lineWidth by animateFloatAsState(if (overTarget) .84f else .56f, tween(240), label = "desktop target line")
                Spacer(Modifier.height(13.dp))
                Box(Modifier.fillMaxWidth(lineWidth).height(1.dp).background(Brush.horizontalGradient(
                    listOf(transparent, secondary.copy(alpha = .36f), ink.copy(alpha = .5f), accent.copy(alpha = .64f), transparent),
                )))
            }
        }
        Column(Modifier.absoluteOffset {
            val center = -iconSize.toPx() / 2
            val offset = drag.pickupOffset * (1f - fraction) + Offset(center, center) * fraction + drag.pointer
            IntOffset(offset.x.roundToInt(), offset.y.roundToInt())
        }.size(width, height)
            .shadow(lerp(16.dp, 6.dp, fraction), shape,
                ambientColor = openBitFunColors.shadowStrong, spotColor = openBitFunColors.shadowStrong)
            .clip(shape).background(MaterialTheme.colorScheme.surface).semantics { hideFromAccessibility() }) {
            MiniAppCover(app, Modifier.fillMaxWidth().height(coverHeight))
            Box(Modifier.fillMaxWidth().weight(1f).padding(horizontal = 20.dp)
                .graphicsLayer { alpha = 1f - fraction }, contentAlignment = Alignment.CenterStart) {
                MiniAppCopy(app, Modifier.fillMaxWidth(), titleLines = 1)
            }
        }
    }
}

internal fun miniAppShortcutId(intent: Intent): String? {
    if (intent.action != MINI_APP_ACTION) return null
    val id = intent.getStringExtra(MINI_APP_ID_EXTRA) ?: return null
    return id.takeIf { it in builtinMiniAppIds || Regex("local-genui:[0-9a-f-]{36}").matches(it) }
}

private val builtinMiniAppIds = setOf("builtin-gomoku", "builtin-regex-playground", "builtin-daily-divination")

private suspend fun requestMiniAppPin(context: Context, item: MiniAppEntry, revealHome: Boolean) {
    val accepted = withContext(Dispatchers.IO) {
        val preview = if (item.generated) readGenUiThumbnail(context, item.id) else null
        try {
            requestMiniAppShortcut(context, item.id, item.name, item.cover, preview, revealHome)
        } finally {
            preview?.recycle()
        }
    }
    if (!accepted) Toast.makeText(context, R.string.miniapps_pin_failed, Toast.LENGTH_SHORT).show()
}

@Composable
private fun MiniAppCover(app: MiniAppEntry, modifier: Modifier) {
    if (app.generated) {
        val art = rememberGenUiThumbnail(app.id)
        val colors = openBitFunColors
        Box(modifier.background(colors.heroSurface), contentAlignment = Alignment.Center) {
            if (art != null) Image(art, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            else Icon(painterResource(R.drawable.ic_miniapp_view_list), contentDescription = null,
                modifier = Modifier.size(30.dp), tint = colors.heroAccent)
        }
    } else {
        Image(painterResource(app.cover), contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
    }
}

@Composable
private fun MiniAppCopy(app: MiniAppEntry, modifier: Modifier, titleLines: Int) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(app.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold,
            maxLines = titleLines, overflow = TextOverflow.Ellipsis)
        Text(app.description, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis)
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun MiniAppWebView(appId: String, locale: String, modifier: Modifier) {
    AndroidView(modifier = modifier.fillMaxWidth(), factory = { context ->
        WebView(context).apply {
            // A wrap-content WebView gives a percentage-height iframe a zero-height viewport.
            layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            )
            settings.javaScriptEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.setSupportMultipleWindows(false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    return request.url.scheme !in setOf("blob", "about")
                }
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    // Blob frames contain only bundled bytes. No app can request a network resource.
                    if (request.url.scheme == "blob" || request.url.scheme == "data") return null
                    return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                }
            }
            addJavascriptInterface(BuiltinMiniAppBridge(context, appId) { reply ->
                post { evaluateJavascript("window.__miniappReply($reply)", null) }
            }, "miniappNative")
            val html = context.assets.open("miniapps/$appId.$locale.html").bufferedReader().use { it.readText() }
            loadDataWithBaseURL("https://miniapp.local/", html, "text/html", "UTF-8", null)
        }
    }, onRelease = { view ->
        view.removeJavascriptInterface("miniappNative")
        view.stopLoading()
        view.destroy()
    })
}

/** Per-app key allowlist; unparseable persisted JSON is retained and reported, never reset. */
internal class BuiltinMiniAppBridge(private val context: Context, private val appId: String, private val reply: (String) -> Unit) {
    @JavascriptInterface
    @Synchronized
    fun request(raw: String) {
        val request = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val id = request.optString("id")
        if (id.isEmpty()) return
        val response = JSONObject().put("id", id)
        try {
            val params = request.getJSONObject("params")
            val method = request.getString("method")
            val key = params.optString("key")
            val allowedKey = when (appId) {
                "builtin-gomoku" -> "stats"
                "builtin-regex-playground" -> "regex-state"
                "builtin-daily-divination" -> "lastReading"
                else -> error("Unsupported MiniApp")
            }
            val result = when (method) {
                "clipboard.writeText" -> {
                    val text = params.getString("text")
                    android.os.Handler(context.mainLooper).post {
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("", text))
                    }
                    JSONObject.NULL
                }
                "storage.get", "storage.set" -> {
                    require(key == allowedKey) { "Unsupported storage key" }
                    val store = context.getSharedPreferences("miniapps-$appId", Context.MODE_PRIVATE)
                    if (method == "storage.get") {
                        store.getString(key, null)?.let { JSONObject(it).get("value") } ?: JSONObject.NULL
                    } else {
                        val encoded = JSONObject().put("value", params.opt("value") ?: JSONObject.NULL).toString()
                        // Store an envelope so scalar/null values retain valid JSON too.
                        check(store.edit().putString(key, encoded).commit()) { "Unable to save MiniApp data" }
                        JSONObject.NULL
                    }
                }
                else -> error("Unsupported capability")
            }
            response.put("result", result)
        } catch (error: Exception) {
            response.put("error", JSONObject().put("message", error.message ?: "MiniApp operation failed"))
        }
        reply(response.toString())
    }
}
