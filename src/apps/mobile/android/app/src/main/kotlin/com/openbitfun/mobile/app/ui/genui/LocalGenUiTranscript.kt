package com.openbitfun.mobile.app.ui.genui

import android.content.ClipData
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.platform.rememberWindowMetrics
import com.openbitfun.mobile.app.ui.chat.MarkdownContent
import com.openbitfun.mobile.app.ui.common.AdaptiveModalSurface
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as Geometry
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignTypography
import com.openbitfun.mobile.core.feature.genui.LocalGenUiApp
import com.openbitfun.mobile.core.feature.genui.LocalGenUiFailure
import com.openbitfun.mobile.core.feature.genui.LocalGenUiMessage
import com.openbitfun.mobile.core.feature.layout.AdaptiveLayoutInput
import com.openbitfun.mobile.core.feature.layout.SettingsPlacementPolicy
import com.openbitfun.mobile.core.feature.layout.SettingsSheetKind
import com.openbitfun.mobile.core.feature.layout.UserMessageTruncationPolicy
import com.openbitfun.mobile.core.feature.markdown.MarkdownClipboard
import kotlinx.coroutines.launch

@Composable
internal fun GenUiTranscriptMessage(
    message: LocalGenUiMessage,
    app: LocalGenUiApp?,
    timestamp: String?,
    onOpenFullText: () -> Unit,
    onOpenApp: () -> Unit,
) {
    val user = message.role == "user"
    val text = if (message.automaticRepair) stringResource(R.string.genui_auto_repair) else message.text
    val title = message.appTitle ?: app?.title
    val appId = message.appId
    Column(
        Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalAlignment = if (user) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(if (user) 6.dp else 10.dp),
    ) {
        if (text.isNotBlank()) {
            if (user) {
                GenUiUserMessage(text, onOpenFullText)
            } else {
                GenUiTranscriptMarkdown(text)
            }
        }
        if (appId != null && title != null) {
            val status = when {
                message.preparingApp -> R.string.genui_app_preparing
                message.appGenerationFailed -> R.string.genui_app_failed
                message.failure == LocalGenUiFailure.STATE_MIGRATION_REQUIRED -> R.string.genui_state_migration_required
                else -> R.string.genui_app_ready
            }
            GenUiMessageAppCard(appId, title, status, onOpenApp)
        } else {
            GenUiFailure(message.failure)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (timestamp != null) {
                Text(
                    timestamp, Modifier.testTag("local-genui-message-time"),
                    style = MobileDesignTypography.LabelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!user && message.text.isNotBlank()) GenUiCopyMessage(message.text)
        }
    }
}

@Composable
private fun GenUiUserMessage(text: String, onOpenFullText: () -> Unit) {
    val preview = remember(text) { UserMessageTruncationPolicy.truncatedPreview(text) }
    val padding = Modifier.padding(
        horizontal = Geometry.MessageBubbleHorizontalPadding,
        vertical = Geometry.MessageBubbleVerticalPadding,
    )
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var showMenu by remember(text) { mutableStateOf(false) }
    val fullText = stringResource(R.string.chat_full_text)
    val copy = stringResource(R.string.chat_copy_full_text)
    Box {
        Surface(
            Modifier.widthIn(max = Geometry.MessageBubbleMaxWidth),
            shape = RoundedCornerShape(Geometry.MessageBubbleRadius),
            color = MaterialTheme.colorScheme.surfaceVariant,
        ) {
            if (preview == null) {
                SelectionContainer { Text(text, padding, style = MobileDesignTypography.BodyLarge) }
            } else {
                val link = if (MaterialTheme.colorScheme.background.luminance() < .5f) {
                    MobileDesignColors.Dark.FileLink
                } else MobileDesignColors.Light.FileLink
                Text(
                    buildAnnotatedString {
                        append(preview)
                        append(' ')
                        withLink(LinkAnnotation.Clickable(
                            tag = "local-genui-full-text",
                            styles = TextLinkStyles(style = SpanStyle(
                                color = link, textDecoration = TextDecoration.Underline,
                                fontSize = MobileDesignTypography.BodyMedium.fontSize,
                            )),
                        ) { onOpenFullText() }) { append(fullText) }
                    },
                    Modifier.combinedClickable(onClickLabel = fullText, onClick = onOpenFullText, onLongClick = { showMenu = true })
                        .then(padding).testTag("local-genui-truncated-message"),
                    style = MobileDesignTypography.BodyLarge,
                )
            }
        }
        DropdownMenu(showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(text = { Text(copy) }, onClick = {
                showMenu = false
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(copy, text))) }
            })
        }
    }
}

@Composable
internal fun GenUiFullTextSheet(text: String?, onClose: () -> Unit) {
    if (text == null) return
    val window = rememberWindowMetrics()
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val placement = SettingsPlacementPolicy.resolve(
        AdaptiveLayoutInput(
            viewportWidth = window.widthDp,
            viewportHeight = window.heightDp,
            isFolded = window.isFolded,
            isExpandedFoldable = window.isExpandedFoldable,
            isHoverOperate = window.isHoverLayout,
            wideLayoutMatched = window.wideViewportMatched,
            verticalCreases = window.creases,
            horizontalCreases = window.horizontalCreases,
            isRtl = rtl,
        ),
        SettingsSheetKind.USER_MESSAGE_FULL_TEXT,
    )
    AdaptiveModalSurface(
        visible = true, placement = placement, onDismissRequest = onClose, edgeToEdgeContent = true,
        scrimColor = MaterialTheme.colorScheme.scrim,
    ) { modifier ->
        Column(modifier.testTag("local-genui-full-text-sheet")) {
            Row(
                Modifier.fillMaxWidth().height(Geometry.SheetHeaderHeight).padding(
                    start = Geometry.SheetHorizontalPadding,
                    end = 12.dp,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.chat_full_text), Modifier.weight(1f),
                    style = MobileDesignTypography.ConversationHeaderTitle)
                IconButton(onClose, Modifier.size(Geometry.ControlTouchSize)) {
                    Icon(painterResource(R.drawable.ic_symbol_xmark), stringResource(R.string.common_close), Modifier.size(18.dp))
                }
            }
            HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()) {
                SelectionContainer {
                    Text(text, Modifier.fillMaxWidth().padding(
                        start = Geometry.SheetHorizontalPadding, end = Geometry.SheetHorizontalPadding,
                        top = 18.dp, bottom = 24.dp,
                    ), style = MobileDesignTypography.BodyMedium)
                }
            }
        }
    }
}

@Composable
internal fun GenUiTranscriptMarkdown(text: String, streaming: Boolean = false) {
    val uriHandler = LocalUriHandler.current
    MarkdownContent(text, onOpenLink = { uri, _ ->
        if (uri.startsWith("https://", ignoreCase = true) || uri.startsWith("http://", ignoreCase = true)) {
            runCatching { uriHandler.openUri(uri) }
        }
    }, modifier = Modifier.fillMaxWidth(), streaming = streaming)
}

@Composable
private fun GenUiCopyMessage(text: String) {
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val copy = stringResource(R.string.chat_copy)
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }, Modifier.size(Geometry.MessageActionTouchSize)) {
            Icon(
                painterResource(R.drawable.ic_chat_copy), copy, Modifier.size(Geometry.MessageActionIconSize),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(
            expanded, onDismissRequest = { expanded = false },
            modifier = Modifier.width(Geometry.CompactPopoverWidth),
            offset = DpOffset(0.dp, 4.dp),
            shape = RoundedCornerShape(Geometry.CompactPopoverRadius),
            containerColor = MaterialTheme.colorScheme.surface,
            shadowElevation = 3.dp,
            border = BorderStroke(.5.dp, MaterialTheme.colorScheme.outlineVariant),
        ) {
            GenUiCopyItem(R.string.chat_copy_rich) {
                expanded = false
                scope.launch {
                    clipboard.setClipEntry(ClipEntry(ClipData.newHtmlText(copy, MarkdownClipboard.plainText(text), MarkdownClipboard.html(text))))
                }
            }
            GenUiCopyItem(R.string.chat_copy_markdown) {
                expanded = false
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(copy, text))) }
            }
            GenUiCopyItem(R.string.chat_copy_plain) {
                expanded = false
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(copy, MarkdownClipboard.plainText(text)))) }
            }
        }
    }
}

@Composable
private fun GenUiCopyItem(label: Int, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(stringResource(label), style = MobileDesignTypography.BodySmall) },
        onClick = onClick, modifier = Modifier.height(Geometry.CompactPopoverActionHeight),
    )
}

@Composable
private fun GenUiMessageAppCard(appId: String, title: String, status: Int, onOpen: () -> Unit) {
    val dark = MaterialTheme.colorScheme.background.luminance() < .5f
    val accent = if (dark) MobileDesignColors.Dark.ConnectHeroAccent else MobileDesignColors.Light.ConnectHeroAccent
    val surface = if (dark) MobileDesignColors.Dark.ConnectHeroSurface else MobileDesignColors.Light.ConnectHeroSurface
    val background = if (dark) MobileDesignColors.Dark.ConnectHeroBg else MobileDesignColors.Light.ConnectHeroBg
    val action = if (dark) MobileDesignColors.Dark.PrimaryAction else MobileDesignColors.Light.PrimaryAction
    val badge = if (dark) MobileDesignColors.Dark.ToastBackground else MobileDesignColors.Light.ToastBackground
    val inkOnAction = MobileDesignColors.Light.ContentOnAction
    val outline = MaterialTheme.colorScheme.outlineVariant
    val cardShape = RoundedCornerShape(Geometry.MessageAppCardRadius)
    val cardShadow = if (dark) MobileDesignColors.Dark.ShadowFaint else MobileDesignColors.Light.ShadowFaint
    val thumbnail = rememberGenUiThumbnail(appId)
    Surface(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth().shadow(12.dp, cardShape, clip = false, ambientColor = cardShadow, spotColor = cardShadow)
            .testTag("local-genui-app-card"),
        shape = cardShape,
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(.5.dp, outline),
    ) {
        Row(
            Modifier.padding(Geometry.MessageAppCardPadding),
            horizontalArrangement = Arrangement.spacedBy(Geometry.MessageAppCardPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val shape = RoundedCornerShape(Geometry.MessageAppPreviewRadius)
            Box(
                Modifier.size(Geometry.MessageAppPreviewSize).clip(shape)
                    .background(Brush.linearGradient(listOf(surface, background))).border(.5.dp, outline, shape),
                contentAlignment = Alignment.Center,
            ) {
                val image = thumbnail
                if (image == null) {
                    val trimmed = title.trim()
                    val initial = if (trimmed.isEmpty()) "AI" else String(Character.toChars(trimmed.codePointAt(0)))
                    Text(initial, style = MobileDesignTypography.DisplayLarge, fontWeight = FontWeight.Bold, color = accent)
                } else {
                    Image(image, contentDescription = null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                }
                Box(
                    Modifier.align(Alignment.BottomEnd).padding(Geometry.MessageAppBadgeInset)
                        .size(Geometry.MessageAppBadgeSize).background(badge, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(painterResource(R.drawable.ic_symbol_wand_and_stars), contentDescription = null,
                        modifier = Modifier.size(11.dp), tint = inkOnAction)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MobileDesignTypography.TitleSmall, fontWeight = FontWeight.Medium,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(stringResource(status), style = MobileDesignTypography.LabelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    stringResource(R.string.common_open),
                    Modifier.padding(top = 4.dp).background(action, RoundedCornerShape(Geometry.MessageAppOpenRadius))
                        .padding(horizontal = Geometry.MessageAppOpenHorizontalPadding, vertical = Geometry.MessageAppOpenVerticalPadding),
                    style = MobileDesignTypography.LabelMedium, fontWeight = FontWeight.Medium, color = inkOnAction,
                )
            }
        }
    }
}
