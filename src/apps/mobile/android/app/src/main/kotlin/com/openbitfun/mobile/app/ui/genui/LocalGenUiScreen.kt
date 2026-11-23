package com.openbitfun.mobile.app.ui.genui

import android.app.Application
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import androidx.core.view.WindowCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.chat.ConversationScrollPolicy
import com.openbitfun.mobile.app.ui.chat.OpenBitFunHeaderAction
import com.openbitfun.mobile.app.ui.chat.OpenBitFunHeaderActionMenu
import com.openbitfun.mobile.app.ui.chat.TitleEditor
import com.openbitfun.mobile.app.ui.chat.ConversationTopEdgeFade
import com.openbitfun.mobile.app.ui.chat.conversationBottomOverlayFade
import com.openbitfun.mobile.app.ui.chat.conversationOverlayFill
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as Geometry
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignTypography
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.genui.LocalGenUiApp
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCalendarAction
import com.openbitfun.mobile.core.feature.genui.LocalGenUiFailure
import com.openbitfun.mobile.core.feature.genui.LocalGenUiIntent
import com.openbitfun.mobile.core.feature.genui.LocalGenUiModelUi
import com.openbitfun.mobile.core.feature.genui.LocalGenUiMedia
import com.openbitfun.mobile.core.feature.genui.LocalGenUiSession
import com.openbitfun.mobile.core.feature.genui.LocalGenUiState
import com.openbitfun.mobile.core.feature.genui.LocalGenUiStore
import com.openbitfun.mobile.core.feature.genui.create
import com.openbitfun.mobile.core.feature.session.ChatComposerPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.UUID

internal class LocalGenUiModel(application: Application) : AndroidViewModel(application) {
    val store = LocalGenUiStore.create(viewModelScope, application)
    var modelPanel by mutableStateOf<GenUiModelPanel?>(null)
        private set
    val orientation = GenUiOrientation()
    val media = LocalGenUiMedia(
        application.cacheDir.resolve("local-genui-media").path,
        application.filesDir.resolve("local-genui-images").path,
    )

    override fun onCleared() {
        media.close()
    }

    fun openModelPanel(owner: String, state: LocalGenUiState) {
        val setup = state.models.none { it.id == state.selectedModelId && it.hasStoredKey }
        store.dispatch(LocalGenUiIntent.ResetModelEditor)
        modelPanel = GenUiModelPanel(owner, setup, setup && state.models.isEmpty())
    }

    fun closeModelPanel(owner: String) {
        if (modelPanel?.owner != owner) return
        modelPanel = null
        store.dispatch(LocalGenUiIntent.ResetModelEditor)
    }
}

@Composable
internal fun LocalGenUiButton(onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(44.dp).clickable(onClick = onOpen)
            .padding(horizontal = 4.dp).testTag("sidebar-local-bot"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(painterResource(R.drawable.ic_symbol_square_and_pencil), null, Modifier.size(24.dp), tint = openBitFunColors.sidebar.muted)
        Text(stringResource(R.string.genui_create), color = openBitFunColors.sidebar.muted)
    }
}

@Composable
internal fun LocalGenUiDialog(
    initialAppId: String? = null,
    model: LocalGenUiModel = viewModel(),
    onClose: () -> Unit,
) {
    val state by model.store.state.collectAsStateWithLifecycle()
    val dispatch = model.store::dispatch
    val panelOwner = rememberSaveable { UUID.randomUUID().toString() }
    LaunchedEffect(initialAppId, state.loading) {
        if (!state.loading && initialAppId != null) dispatch(LocalGenUiIntent.OpenApp(initialAppId))
    }
    val context = LocalContext.current
    DisposableEffect(model, context) {
        onDispose {
            if (context.activity()?.isChangingConfigurations != true) {
                model.closeModelPanel(panelOwner)
                dispatch(LocalGenUiIntent.Close)
            }
        }
    }

    val goBack = {
        when {
            initialAppId != null && (state.failure == LocalGenUiFailure.APP_MISSING ||
                (state.openApp != null && state.selectedSession == null)) -> onClose()
            state.openApp != null || state.selectedSession != null -> dispatch(LocalGenUiIntent.Back)
            else -> onClose()
        }
    }
    Dialog(
        onDismissRequest = goBack,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val view = LocalView.current
        val light = MaterialTheme.colorScheme.background.luminance() > .5f
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.let { window ->
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = light
                    isAppearanceLightNavigationBars = light
                }
            }
        }
        val app = state.openApp
        Box(Modifier.fillMaxSize()) {
            val checker = state.checkingApp
            if (checker != null && (app?.id != checker.id || app.sourceRevision != checker.sourceRevision || !app.checking)) {
                LocalGenUiWebView(
                    checker, 0, false, dispatch, model.media, remember { GenUiOrientation() },
                    Modifier.fillMaxSize().alpha(.001f),
                )
            }
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                when {
                    app != null || (initialAppId != null && state.failure == LocalGenUiFailure.APP_MISSING) ->
                        LocalGenUiAppSurface(app, state, dispatch, model.media, model.orientation, model.viewModelScope, goBack)
                    else -> Column(
                        Modifier.fillMaxSize().safeDrawingPadding().imePadding(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        val session = state.selectedSession
                        if (session != null) {
                            key(session.id) {
                                LocalGenUiConversation(state, dispatch, onBack = goBack,
                                    onModels = { model.openModelPanel(panelOwner, state) }, Modifier.weight(1f))
                            }
                        } else {
                            LocalGenUiSessions(state, dispatch, goBack, Modifier.weight(1f))
                        }
                    }
                }
            }
        }
        model.modelPanel?.takeIf { it.owner == panelOwner }?.let { panel ->
            LocalGenUiModelSheet(state, dispatch, panel) { model.closeModelPanel(panelOwner) }
        }
    }
}

@Composable
private fun LocalGenUiHeader(
    title: String,
    onBack: () -> Unit,
    onTitle: (() -> Unit)? = null,
    trailing: @Composable () -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onBack, Modifier.size(48.dp)) {
            Icon(painterResource(R.drawable.ic_symbol_chevron_left), stringResource(R.string.miniapps_back))
        }
        val titleModifier = Modifier.weight(1f)
        val renameLabel = stringResource(R.string.session_rename)
        Text(title, style = MobileDesignTypography.ConversationHeaderTitle,
            fontWeight = FontWeight.Medium,
            maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = if (onTitle == null) titleModifier else titleModifier.clickable(
                onClickLabel = renameLabel, role = Role.Button, onClick = onTitle,
            ).testTag("local-genui-rename-session"),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { trailing() }
    }
}

@Composable
private fun LocalGenUiSessions(
    state: LocalGenUiState, dispatch: (LocalGenUiIntent) -> Unit, onBack: () -> Unit, modifier: Modifier,
) {
    var sendImage by remember { mutableStateOf(false) }
    var toolsOpen by remember { mutableStateOf(false) }
    var actionSessionId by remember { mutableStateOf<String?>(null) }
    val locale = LocalConfiguration.current.locales[0]
    val menuGap = with(LocalDensity.current) { Geometry.GenuiHistoryMenuGap.roundToPx() }
    val menuPosition = remember(menuGap) { GenUiHistoryMenuPosition(menuGap) }
    val times = remember(locale) {
        SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, "yyyyMMddjjmm"), locale)
    }
    val compactWidth = Modifier.widthIn(max = Geometry.SheetContentMaxWidth).fillMaxWidth()
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        LocalGenUiHeader(stringResource(R.string.genui_create), onBack) {
            IconButton(onClick = { toolsOpen = true }) {
                Icon(painterResource(R.drawable.ic_symbol_ellipsis), stringResource(R.string.general_chat_menu), Modifier.size(19.dp))
            }
            DropdownMenu(expanded = toolsOpen, onDismissRequest = { toolsOpen = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.genui_image_send)) }, onClick = {
                    toolsOpen = false
                    sendImage = true
                })
            }
        }
        when {
            state.loading -> Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) {
                CircularProgressIndicator(Modifier.padding(24.dp).size(28.dp))
            }
            state.sessions.isEmpty() -> Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) {
                Text(stringResource(R.string.genui_empty), Modifier.padding(top = 32.dp),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> LazyColumn(compactWidth.weight(1f).testTag("local-genui-history"), contentPadding = PaddingValues(
                start = Geometry.GenuiHistoryHorizontalInset, end = Geometry.GenuiHistoryHorizontalInset,
                top = Geometry.GenuiHistoryVerticalInset,
            )) {
                itemsIndexed(state.sessions, key = { _, session -> session.id }) { index, session ->
                    if (index > 0) HorizontalDivider(Modifier.padding(horizontal = Geometry.GenuiHistoryHorizontalInset),
                        thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                    val active = session.id == state.activeSessionId
                    val remove = stringResource(R.string.genui_delete)
                    val shape = RoundedCornerShape(Geometry.GenuiHistoryRowRadius)
                    Box {
                        Row(Modifier.fillMaxWidth().heightIn(min = Geometry.GenuiHistoryRowHeight).clip(shape)
                            .background(if (active) openBitFunColors.sidebar.selection else openBitFunColors.transparent)
                            .combinedClickable(
                                enabled = !state.busy || active,
                                role = Role.Button,
                                onClick = { dispatch(LocalGenUiIntent.OpenSession(session.id)) },
                                onLongClickLabel = remove.takeUnless { state.busy },
                                onLongClick = if (state.busy) null else { { actionSessionId = session.id } },
                            )
                            .semantics { selected = active }.testTag("local-genui-session")
                            .padding(horizontal = Geometry.GenuiHistoryHorizontalInset, vertical = Geometry.GenuiHistoryVerticalInset),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Geometry.GenuiHistoryLabelSpacing)) {
                                Text(session.title.ifBlank { stringResource(R.string.sidebar_untitled) }, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = if (active) FontWeight.Medium else FontWeight.Normal)
                                (session.updatedAtMillis ?: session.createdAtMillis)?.let { time ->
                                    Text(times.format(Date(time)), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.testTag("local-genui-session-time"))
                                }
                            }
                            when {
                                active && state.busy -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                active -> Icon(painterResource(R.drawable.ic_symbol_checkmark), null, Modifier.size(16.dp))
                                else -> Icon(painterResource(R.drawable.ic_symbol_chevron_right), null, Modifier.size(12.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        if (actionSessionId == session.id && !state.busy) {
                            Popup(menuPosition, onDismissRequest = { actionSessionId = null },
                                properties = PopupProperties(focusable = true)) {
                                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 9.dp) {
                                    Box(Modifier.clickable(role = Role.Button) {
                                        actionSessionId = null
                                        dispatch(LocalGenUiIntent.DeleteSession(session.id))
                                    }.heightIn(min = Geometry.GenuiHistoryMenuHeight)
                                        .padding(horizontal = Geometry.GenuiHistoryActionInset), contentAlignment = Alignment.Center) {
                                        Text(remove, style = MaterialTheme.typography.bodyMedium)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (state.failure != null) {
            GenUiFailure(state.failure)
            TextButton(onClick = { dispatch(LocalGenUiIntent.Reload) }) { Text(stringResource(R.string.account_devices_retry)) }
        }
        Button(
            onClick = { dispatch(LocalGenUiIntent.NewSession) },
            enabled = !state.loading && !state.busy && state.failure == null,
            modifier = compactWidth.padding(horizontal = Geometry.GenuiHistoryActionInset, vertical = 16.dp)
                .heightIn(min = Geometry.SheetActionHeight).testTag("local-genui-new-session"),
        ) {
            Text(stringResource(R.string.genui_new))
        }
    }
    if (sendImage) LocalGenUiSendImage { sendImage = false }
}

private class GenUiHistoryMenuPosition(private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize,
    ): IntOffset {
        val x = (anchorBounds.center.x - popupContentSize.width / 2)
            .coerceIn(0, (windowSize.width - popupContentSize.width).coerceAtLeast(0))
        val below = anchorBounds.bottom + gap
        val y = if (below + popupContentSize.height <= windowSize.height) below
        else (anchorBounds.top - gap - popupContentSize.height).coerceAtLeast(0)
        return IntOffset(x, y)
    }
}

@Composable
private fun LocalGenUiConversationHeader(
    session: LocalGenUiSession,
    busy: Boolean,
    dispatch: (LocalGenUiIntent) -> Unit,
    onBack: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    var actionsOpen by remember { mutableStateOf(false) }
    var editingTitle by remember { mutableStateOf(false) }
    var renameDraft by rememberSaveable { mutableStateOf("") }
    val canRename = session.messages.isNotEmpty()
    LocalGenUiHeader(
        session.title.ifEmpty { stringResource(R.string.genui_create) },
        onBack,
        onTitle = if (canRename) ({
            focusManager.clearFocus()
            actionsOpen = false
            renameDraft = session.title
            editingTitle = true
        }) else null,
    ) {
        IconButton(
            onClick = {
                focusManager.clearFocus()
                editingTitle = false
                actionsOpen = !actionsOpen
            },
            modifier = Modifier.size(Geometry.ControlTouchSize),
        ) {
            Icon(painterResource(R.drawable.ic_symbol_ellipsis), stringResource(R.string.session_actions),
                modifier = Modifier.size(width = 23.dp, height = 7.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        OpenBitFunHeaderActionMenu(
            expanded = actionsOpen,
            onDismiss = { actionsOpen = false },
            sectionTitle = stringResource(R.string.session_section),
            actions = buildList {
                add(OpenBitFunHeaderAction(R.drawable.ic_symbol_folder, stringResource(R.string.genui_history), onBack))
                if (canRename && !busy) {
                    add(OpenBitFunHeaderAction(R.drawable.ic_symbol_trash, stringResource(R.string.session_delete),
                        onClick = { dispatch(LocalGenUiIntent.DeleteSession(session.id)) }))
                }
            },
        )
    }
    if (editingTitle) {
        TitleEditor(
            draft = renameDraft, enabled = canRename, onDraftChange = { renameDraft = it },
            onSave = {
                dispatch(LocalGenUiIntent.RenameSession(session.id, renameDraft))
                editingTitle = false
            },
            onCancel = { editingTitle = false },
        )
    }
}

@Composable
private fun LocalGenUiConversation(
    state: LocalGenUiState,
    dispatch: (LocalGenUiIntent) -> Unit,
    onBack: () -> Unit,
    onModels: () -> Unit,
    modifier: Modifier,
) {
    val session = state.selectedSession ?: return
    var draft by rememberSaveable(session.id) { mutableStateOf(state.draft) }
    var modelMenu by remember { mutableStateOf(false) }
    var submittedDraft by remember(session.id) { mutableStateOf<String?>(null) }
    val model = state.models.firstOrNull { it.id == state.selectedModelId && it.hasStoredKey }
    val authorizeEndpoint = rememberGenUiNetworkConsent()
    val focusManager = LocalFocusManager.current
    var focused by remember { mutableStateOf(false) }
    val expanded = ChatComposerPolicy.isExpanded(
        text = draft, inputFocused = focused, quickActionsOpen = false, modelSelectorOpen = false,
    )
    val minInputHeight = if (expanded) Geometry.ComposerExpandedInputRowHeight else Geometry.ComposerInputHeight
    val showDraftPreview = !expanded && draft.isNotEmpty()
    var modelAnchorTop by remember { mutableStateOf(0.dp) }
    var fullText by remember { mutableStateOf<String?>(null) }
    val density = LocalDensity.current
    val ime = WindowInsets.ime
    var topInset by remember { mutableStateOf(Geometry.ConversationHeaderHeight + Geometry.ConversationEdgeFadeHeight) }
    var bottomInset by remember { mutableStateOf(0.dp) }
    val timeline = rememberLazyListState()
    var stickToBottom by rememberSaveable { mutableStateOf(true) }
    var userDragging by remember { mutableStateOf(false) }
    LaunchedEffect(ime, density, focusManager) {
        var wasVisible = false
        snapshotFlow { ime.getBottom(density) > 0 }.collect { visible ->
            if (wasVisible && !visible) focusManager.clearFocus()
            wasVisible = visible
        }
    }
    LaunchedEffect(timeline) {
        timeline.interactionSource.interactions.collect { interaction ->
            when (interaction) {
                is DragInteraction.Start -> {
                    userDragging = true
                    stickToBottom = false
                }
                is DragInteraction.Stop, is DragInteraction.Cancel -> userDragging = false
            }
        }
    }
    LaunchedEffect(timeline) {
        snapshotFlow { userDragging to timeline.canScrollForward }.collect { (dragging, canScrollForward) ->
            stickToBottom = ConversationScrollPolicy.shouldStickToBottom(
                currentlySticking = stickToBottom,
                isAtBottom = !canScrollForward,
                isScrollInProgress = dragging,
            )
        }
    }
    BackHandler(enabled = modelMenu) { modelMenu = false }
    LaunchedEffect(state.draftAcceptedSerial) {
        submittedDraft?.let { submitted ->
            if (draft == submitted) {
                draft = ""
            } else {
                dispatch(LocalGenUiIntent.EditDraft(session.id, state.draftAcceptedSerial, draft))
            }
        }
        submittedDraft = null
        stickToBottom = true
    }
    Box(modifier.fillMaxSize().testTag("local-genui-conversation"), contentAlignment = Alignment.TopCenter) {
        val shownStreaming = state.streamingText.isNotBlank()
        val locale = LocalConfiguration.current.locales[0]
        val messageTime = remember(locale) {
            SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, "yyyyMMddjjmm"), locale)
        }
        val lastIndex = maxOf(1, session.messages.size) - 1 + listOf(state.recovering, shownStreaming).count { it }
        LaunchedEffect(lastIndex, state.streamingText, stickToBottom, topInset, bottomInset) {
            if (stickToBottom) timeline.scrollToItem(lastIndex, scrollOffset = Int.MAX_VALUE)
        }
        LazyColumn(
            Modifier.widthIn(max = 760.dp).fillMaxSize().testTag("local-genui-transcript"),
            state = timeline,
            contentPadding = PaddingValues(
                start = Geometry.ConversationOverlaySideInset,
                end = Geometry.ConversationOverlaySideInset,
                top = topInset, bottom = bottomInset,
            ),
            verticalArrangement = Arrangement.spacedBy(Geometry.MessageSpacing),
        ) {
            if (session.messages.isEmpty()) {
                item {
                    Text(stringResource(R.string.genui_empty_conversation), Modifier.padding(vertical = 24.dp),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(session.messages) { row ->
                GenUiTranscriptMessage(
                    message = row,
                    app = state.apps.firstOrNull { it.id == row.appId },
                    timestamp = row.createdAtMillis?.let { messageTime.format(Date(it)) },
                    onOpenFullText = {
                        focusManager.clearFocus()
                        fullText = row.text
                    },
                    onOpenApp = { row.appId?.let { dispatch(LocalGenUiIntent.OpenApp(it)) } },
                )
            }
            if (state.recovering) item { Text(stringResource(R.string.genui_recovering), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (shownStreaming) item { GenUiTranscriptMarkdown(state.streamingText, streaming = true) }
        }
        Column(
            Modifier.align(Alignment.TopCenter).fillMaxWidth()
                .onSizeChanged { topInset = with(density) { it.height.toDp() } },
        ) {
            Column(Modifier.fillMaxWidth().background(conversationOverlayFill())) {
                LocalGenUiConversationHeader(session, state.busy, dispatch, onBack)
            }
            ConversationTopEdgeFade()
        }
        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(conversationBottomOverlayFade())
                .onSizeChanged { bottomInset = with(density) { it.height.toDp() } },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            GenUiFailure(state.failure)
            val colors = MaterialTheme.colorScheme
            Surface(
                Modifier.widthIn(max = 760.dp).fillMaxWidth().padding(
                    start = Geometry.ConversationOverlaySideInset,
                    end = Geometry.ConversationOverlaySideInset,
                    top = 8.dp, bottom = 14.dp,
                ),
                shape = RoundedCornerShape(Geometry.ComposerExpandedRadius),
                color = colors.surface.copy(alpha = .94f),
                border = BorderStroke(.5.dp, colors.outlineVariant),
                shadowElevation = 2.dp,
            ) {
                Column(
                    modifier = Modifier.heightIn(min = if (expanded) Geometry.ComposerExpandedHeight else 0.dp)
                        .padding(start = 8.dp, end = 8.dp, top = if (expanded) 4.dp else 2.dp, bottom = 2.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    BasicTextField(
                        value = draft,
                        onValueChange = {
                            draft = it
                            dispatch(LocalGenUiIntent.EditDraft(session.id, state.draftAcceptedSerial, it))
                        },
                        modifier = Modifier.fillMaxWidth().heightIn(min = minInputHeight)
                            .onFocusChanged { focused = it.isFocused }
                            .testTag("local-genui-composer"),
                        singleLine = !expanded,
                        maxLines = if (expanded) 4 else 1,
                        textStyle = MobileDesignTypography.BodyLarge.copy(
                            color = if (showDraftPreview) openBitFunColors.transparent else colors.onSurface,
                            lineHeightStyle = LineHeightStyle(
                                alignment = LineHeightStyle.Alignment.Center,
                                trim = LineHeightStyle.Trim.None,
                            ),
                        ),
                        cursorBrush = SolidColor(colors.onSurface),
                        decorationBox = { field ->
                            Box(
                                Modifier.fillMaxWidth().heightIn(min = minInputHeight).padding(
                                    start = 4.dp, end = 4.dp,
                                    top = if (expanded) 10.dp else 0.dp,
                                    bottom = if (expanded) 8.dp else 0.dp,
                                ),
                                contentAlignment = if (expanded) Alignment.TopStart else Alignment.CenterStart,
                            ) {
                                if (draft.isEmpty()) {
                                    Text(stringResource(R.string.genui_prompt), color = colors.onSurfaceVariant,
                                        style = MobileDesignTypography.BodyLarge)
                                }
                                field()
                                if (showDraftPreview) {
                                    Text(
                                        draft, Modifier.clearAndSetSemantics {}, color = colors.onSurface,
                                        style = MobileDesignTypography.BodyLarge, maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        },
                    )
                    Row(Modifier.fillMaxWidth().height(Geometry.ComposerExpandedActionRowHeight),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.onGloballyPositioned {
                            modelAnchorTop = with(density) { it.positionInWindow().y.toDp() }
                        }) {
                            val label = model?.composerLabel ?: stringResource(R.string.genui_configure)
                            Row(
                                Modifier.heightIn(min = Geometry.ComposerActionSize).widthIn(max = 220.dp)
                                    .clip(RoundedCornerShape(9.dp)).clickable(enabled = !state.busy) {
                                        if (model == null) { focusManager.clearFocus(); onModels() }
                                        else modelMenu = !modelMenu
                                    }.padding(horizontal = 4.dp).testTag("local-genui-model-control"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                Text(label, Modifier.widthIn(max = 192.dp), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    color = if (model == null) colors.onSurface else colors.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                                Icon(painterResource(when {
                                    model == null -> R.drawable.ic_symbol_plus
                                    modelMenu -> R.drawable.ic_symbol_chevron_up
                                    else -> R.drawable.ic_symbol_chevron_down
                                }), null, Modifier.size(13.dp))
                            }
                            if (modelMenu && model != null) {
                                GenUiComposerModelMenu(
                                    selected = model,
                                    profiles = state.models,
                                    spaceAbove = modelAnchorTop,
                                    onDismiss = { modelMenu = false },
                                    onSelect = {
                                        modelMenu = false
                                        dispatch(LocalGenUiIntent.SelectModel(it))
                                    },
                                    onManage = {
                                        modelMenu = false
                                        focusManager.clearFocus()
                                        onModels()
                                    },
                                )
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        val active = state.busy || draft.isNotBlank()
                        val actionLabel = stringResource(if (state.busy) R.string.message_stop else R.string.genui_send)
                        Box(
                            modifier = Modifier.size(Geometry.ComposerActionSize).clip(CircleShape)
                                .background(if (active) openBitFunColors.transparent else colors.surfaceVariant)
                                .clickable(enabled = active, role = Role.Button) {
                                    when {
                                        state.busy -> dispatch(LocalGenUiIntent.Cancel)
                                        model == null -> { focusManager.clearFocus(); onModels() }
                                        else -> authorizeEndpoint(model.endpoint) {
                                            submittedDraft = draft
                                            dispatch(LocalGenUiIntent.Send(session.id, state.draftAcceptedSerial, draft))
                                        }
                                    }
                                }.semantics { contentDescription = actionLabel },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (active) {
                                Box(Modifier.size(Geometry.ComposerPrimarySurfaceSize)
                                    .background(colors.onSurface, CircleShape))
                            }
                            if (state.busy) {
                                Box(Modifier.size(10.dp).background(colors.onPrimary, RoundedCornerShape(2.5.dp)))
                            } else {
                                Icon(painterResource(R.drawable.ic_symbol_arrow_up), null, Modifier.size(20.dp),
                                    tint = if (active) colors.onPrimary else colors.onSurfaceVariant.copy(alpha = .38f))
                            }
                        }
                    }
                }
            }
        }
    }
    GenUiFullTextSheet(fullText) { fullText = null }
}

@Composable
private fun GenUiComposerModelMenu(
    selected: LocalGenUiModelUi,
    profiles: List<LocalGenUiModelUi>,
    spaceAbove: Dp,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
    onManage: () -> Unit,
) {
    val density = LocalDensity.current
    val gap = with(density) { 8.dp.roundToPx() }
    val position = remember(gap) { GenUiComposerModelMenuPosition(gap) }
    val width = minOf(Geometry.ComposerModelSelectorWidth, (LocalConfiguration.current.screenWidthDp - 24).dp)
    val colors = MaterialTheme.colorScheme
    val options = listOf(selected) + profiles.filter { it.hasStoredKey && it.id != selected.id }
    val rowHeight = Geometry.ComposerModelSelectorRowHeight
    val rowGap = Geometry.ComposerModelSelectorRowGap
    val listHeight = minOf(rowHeight * 5 + rowGap * 4, (spaceAbove - rowHeight - 48.dp).coerceAtLeast(0.dp))
    Popup(position, onDismissRequest = onDismiss, properties = PopupProperties(focusable = false)) {
        Surface(
            modifier = Modifier.width(width).testTag("local-genui-model-menu"),
            shape = RoundedCornerShape(Geometry.ComposerModelSelectorRadius),
            color = colors.surface,
            border = BorderStroke(.5.dp, colors.outlineVariant),
            shadowElevation = 9.dp,
        ) {
            Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(rowGap)) {
                Column(
                    Modifier.heightIn(max = listHeight).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(rowGap),
                ) {
                    options.forEach { option ->
                        val current = option.id == selected.id
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = rowHeight)
                                .clip(RoundedCornerShape(Geometry.ComposerModelSelectorRowRadius))
                                .background(if (current) colors.surfaceVariant else openBitFunColors.transparent)
                                .clickable(role = Role.Button) { onSelect(option.id) }
                                .semantics { this.selected = current }.padding(horizontal = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
                                if (current) Icon(painterResource(R.drawable.ic_symbol_checkmark_circle), null, Modifier.size(16.dp))
                            }
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(option.composerLabel, style = MobileDesignTypography.BodySmall, fontWeight = FontWeight.Medium,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(option.composerDetails, style = MobileDesignTypography.LabelSmall, color = colors.onSurfaceVariant,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                HorizontalDivider(thickness = .5.dp)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = rowHeight)
                        .clip(RoundedCornerShape(Geometry.ComposerModelSelectorRowRadius))
                        .clickable(role = Role.Button, onClick = onManage).padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
                        Icon(painterResource(R.drawable.ic_symbol_gearshape), null, Modifier.size(16.dp))
                    }
                    Text(stringResource(R.string.genui_models), style = MobileDesignTypography.BodySmall, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

private class GenUiComposerModelMenuPosition(private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize,
    ): IntOffset {
        val limit = (windowSize.width - popupContentSize.width - gap).coerceAtLeast(gap)
        val x = (anchorBounds.center.x - popupContentSize.width / 2).coerceIn(gap, limit)
        val y = (anchorBounds.top - gap - popupContentSize.height).coerceAtLeast(gap)
        return IntOffset(x, y)
    }
}

@Composable
internal fun GenUiDeleteDialog(onCancel: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.genui_delete)) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.genui_delete)) } },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.genui_cancel)) } },
    )
}

@Composable
internal fun GenUiFailure(failure: LocalGenUiFailure?, modifier: Modifier = Modifier.padding(8.dp)) {
    val message = when (failure) {
        null -> return
        LocalGenUiFailure.STORAGE -> R.string.genui_storage
        LocalGenUiFailure.INVALID_MODEL -> R.string.genui_invalid_model
        LocalGenUiFailure.MISSING_MODEL -> R.string.genui_missing_model
        LocalGenUiFailure.AUTHENTICATION -> R.string.general_chat_authentication
        LocalGenUiFailure.RATE_LIMIT -> R.string.general_chat_rate_limited
        LocalGenUiFailure.NETWORK -> R.string.general_chat_network
        LocalGenUiFailure.INVALID_RESPONSE -> R.string.genui_invalid_response
        LocalGenUiFailure.STATE_MIGRATION_REQUIRED -> R.string.genui_state_migration_required
        LocalGenUiFailure.APP_MISSING -> R.string.genui_unavailable_app
    }
    Text(stringResource(message), modifier, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
}

private const val LOCAL_NETWORK_PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"

@Composable
internal fun rememberGenUiNetworkConsent(): (String, () -> Unit) -> Unit {
    val context = LocalContext.current
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    var denied by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val action = pending
        pending = null
        if (granted) action?.invoke() else denied = true
    }
    if (denied) {
        AlertDialog(
            onDismissRequest = { denied = false },
            title = { Text(stringResource(R.string.genui_network_permission)) },
            confirmButton = { TextButton(onClick = { denied = false }) { Text(stringResource(R.string.genui_cancel)) } },
        )
    }
    return { endpoint, action ->
        if (Build.VERSION.SDK_INT >= 37 && endpointUsesLocalNetwork(endpoint) &&
            ContextCompat.checkSelfPermission(context, LOCAL_NETWORK_PERMISSION) != PackageManager.PERMISSION_GRANTED
        ) {
            pending = action
            launcher.launch(LOCAL_NETWORK_PERMISSION)
        } else {
            action()
        }
    }
}

private fun endpointUsesLocalNetwork(endpoint: String): Boolean {
    val host = Uri.parse(endpoint).host?.lowercase()?.trim('[', ']') ?: return false
    if (host == "localhost" || host == "::1" || host.startsWith("127.")) return false
    if (host.endsWith(".local") || host.startsWith("fe80:")) return true
    if (':' in host) return host.startsWith("fc") || host.startsWith("fd")
    val blocks = host.split('.')
    if (blocks.size == 1) return true
    if (blocks.size != 4 || blocks.any { (it.toIntOrNull() ?: -1) !in 0..255 }) return false
    val first = blocks[0].toInt()
    val second = blocks[1].toInt()
    return first == 10 || first == 172 && second in 16..31 ||
        first == 192 && second == 168 || first == 169 && second == 254
}

@Composable
private fun LocalGenUiAppSurface(
    app: LocalGenUiApp?,
    state: LocalGenUiState,
    dispatch: (LocalGenUiIntent) -> Unit,
    media: LocalGenUiMedia,
    orientation: GenUiOrientation,
    calendarScope: CoroutineScope,
    onBack: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    var capture by remember(app?.id, app?.sourceRevision) { mutableIntStateOf(0) }
    val calendar = rememberLocalGenUiCalendarRunner(calendarScope)
    var calendarNotice by remember(app?.id, app?.sourceRevision) { mutableStateOf<CalendarNotice?>(null) }
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val safe = WindowInsets.safeDrawing
    val controlLeft = with(density) { maxOf(Geometry.GenuiAppControlSideInset, safe.getLeft(density, direction).toDp()) }
    val controlRight = with(density) { maxOf(Geometry.GenuiAppControlSideInset, safe.getRight(density, direction).toDp()) }
    LaunchedEffect(calendarNotice) {
        if (calendarNotice != null) {
            delay(5000)
            calendarNotice = null
        }
    }
    Box(Modifier.fillMaxSize()) {
        if (app != null && !app.failedValidation) {
            LocalGenUiWebView(
                app, state.stateWriteSerial, state.stateWriteConflict, dispatch, media, orientation, Modifier.fillMaxSize(),
                capture = capture,
                onCaptured = { dispatch(LocalGenUiIntent.SetGallery(app.id, true)) },
                liveControls = true,
                calendar = calendar,
                onCalendarResult = { action, count -> calendarNotice = CalendarNotice(action, count) },
            )
        }
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(safe.only(WindowInsetsSides.Top))
                .absolutePadding(left = controlLeft, right = controlRight, top = Geometry.GenuiAppControlTopInset),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 4.dp) {
                IconButton(onBack, Modifier.size(Geometry.GenuiAppControlSize)) {
                    Icon(painterResource(R.drawable.ic_symbol_chevron_left), stringResource(R.string.miniapps_back), Modifier.size(20.dp))
                }
            }
            val loading = app != null && (state.repairing || state.recovering || app.streaming || app.checking)
            val status = when {
                app == null -> R.string.genui_unavailable_app
                state.recovering -> R.string.genui_recovering
                state.repairing -> R.string.genui_repairing
                loading -> R.string.genui_generating
                app.failedValidation -> R.string.genui_app_failed
                state.failure == LocalGenUiFailure.STATE_MIGRATION_REQUIRED -> R.string.genui_state_migration_required
                else -> null
            }
            if (status != null) {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    Row(Modifier.height(Geometry.GenuiAppStatusHeight).widthIn(max = Geometry.GenuiAppStatusMaxWidth)
                        .padding(horizontal = Geometry.GenuiAppStatusHorizontalPadding)
                        .testTag("local-genui-app-status"), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (loading) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                        Text(stringResource(status), style = MaterialTheme.typography.labelSmall,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (app == null || loading || app.failedValidation) {
                Spacer(Modifier.width(Geometry.GenuiAppControlSize))
            } else {
                Box {
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 4.dp) {
                        IconButton(onClick = { menu = true }, Modifier.size(Geometry.GenuiAppControlSize)) {
                            Icon(painterResource(R.drawable.ic_symbol_ellipsis), stringResource(R.string.genui_app_actions), Modifier.size(18.dp))
                        }
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        if (state.selectedSession == null && state.sessions.any { it.id == app.sessionId }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.genui_back_to_chat)) },
                                onClick = {
                                    menu = false
                                    dispatch(LocalGenUiIntent.OpenSession(app.sessionId))
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(stringResource(if (app.inGallery) R.string.genui_remove_gallery else R.string.genui_add_gallery)) },
                            onClick = {
                                menu = false
                                if (app.inGallery) dispatch(LocalGenUiIntent.SetGallery(app.id, false))
                                else capture++
                            },
                        )
                    }
                }
            }
        }
        val noticeText = calendarNotice?.let { notice ->
            val message = when (notice.action) {
                LocalGenUiCalendarAction.CREATE -> R.string.genui_calendar_created
                LocalGenUiCalendarAction.UPDATE -> R.string.genui_calendar_updated
                LocalGenUiCalendarAction.DELETE -> R.string.genui_calendar_deleted
                LocalGenUiCalendarAction.LIST -> R.string.genui_calendar_listed
            }
            notice.value?.let { stringResource(message, it) } ?: stringResource(R.string.genui_calendar_failed)
        }
        if (noticeText != null) {
            Surface(
                Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = 72.dp, start = 24.dp, end = 24.dp),
                shape = RoundedCornerShape(16.dp), color = openBitFunColors.toastBackground,
                contentColor = MobileDesignColors.Light.ContentOnAction,
            ) {
                Text(
                    noticeText,
                    Modifier.padding(horizontal = 14.dp, vertical = 8.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

private class CalendarNotice(val action: LocalGenUiCalendarAction, val value: Long?)
