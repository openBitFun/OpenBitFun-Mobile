package com.openbitfun.mobile.app.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.layout.SettingsPlacement
import com.openbitfun.mobile.core.feature.layout.SettingsPlacementMode

/**
 * Native modal lifecycle around the shared mobile overlay visual contract.
 *
 * Compact and hover windows keep Material's modal sheet semantics. Centered
 * and trailing placements use a Dialog with native back handling and focus
 * containment.
 *
 * @param draggable whether the compact sheet follows a pull-down. A page whose
 * body is itself a scroll should say no: the same pull-down then means both
 * "scroll the body" and "drag the sheet away", so a gesture the user meant as
 * scrolling can move the surface or dismiss the page. Such a page still closes
 * through its own close button, the back action, and a tap on the scrim.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AdaptiveModalSurface(
    visible: Boolean,
    placement: SettingsPlacement,
    onDismissRequest: () -> Unit,
    edgeToEdgeContent: Boolean = false,
    fitContent: Boolean = false,
    draggable: Boolean = true,
    scrimColor: Color = BottomSheetDefaults.ScrimColor,
    connectChrome: Boolean = false,
    content: @Composable (Modifier) -> Unit,
) {
    if (!visible) return
    val hostContext = LocalContext.current
    val hostConfiguration = LocalConfiguration.current

    // Scrim and sheet hit interception must not merge labels into extra clickable
    // accessibility nodes. Close buttons and the native back action remain available.
    if (fitContent) {
        Dialog(onDismissRequest = onDismissRequest,
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            CompositionLocalProvider(
                LocalContext provides hostContext,
                LocalConfiguration provides hostConfiguration,
            ) {
                val window = (LocalView.current.parent as? DialogWindowProvider)?.window
                SideEffect {
                    window?.setDimAmount(0f)
                    // The account sheet is edge-to-edge. Some Android-compatible
                    // hosts otherwise leave the dialog's default white navigation
                    // bar below the rounded surface as a visible strip.
                    window?.navigationBarColor = android.graphics.Color.TRANSPARENT
                    if (android.os.Build.VERSION.SDK_INT >= 29) {
                        window?.isNavigationBarContrastEnforced = false
                    }
                }
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.scrim)
                    .pointerInput(onDismissRequest) { detectTapGestures(onTap = { onDismissRequest() }) }
                    .safeDrawingPadding().imePadding().padding(MobileDesignGeometry.LoginSheetOuterMargin),
                    contentAlignment = Alignment.BottomCenter) {
                    Surface(modifier = Modifier.widthIn(max = MobileDesignGeometry.LoginSheetMaxWidth).fillMaxWidth()
                        .pointerInput(Unit) { detectTapGestures(onTap = {}) },
                        shape = RoundedCornerShape(MobileDesignGeometry.SheetTopRadius),
                        color = MaterialTheme.colorScheme.background) {
                        content(Modifier.fillMaxWidth())
                    }
                }
            }
        }
        return
    }

    val centered = placement.mode == SettingsPlacementMode.CENTER
    if (centered || placement.mode == SettingsPlacementMode.SIDE) {
        Dialog(
            onDismissRequest = onDismissRequest,
            properties = DialogProperties(
                dismissOnBackPress = true,
                dismissOnClickOutside = true,
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            CompositionLocalProvider(
                LocalContext provides hostContext,
                LocalConfiguration provides hostConfiguration,
            ) {
                if (centered || connectChrome) {
                    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
                    SideEffect { window?.setDimAmount(0f) }
                }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.scrim)
                        .pointerInput(onDismissRequest) { detectTapGestures(onTap = { onDismissRequest() }) }
                        .safeDrawingPadding()
                        .imePadding()
                        .padding(if (centered) 16.dp else 0.dp),
                    contentAlignment = if (centered) Alignment.Center else Alignment.CenterEnd,
                ) {
                    val shape = RoundedCornerShape(
                        when {
                            connectChrome -> MobileDesignGeometry.ConnectWidePanelRadius
                            centered -> MobileDesignGeometry.SettingsWidePanelRadius
                            else -> MobileDesignGeometry.SheetSideRadius
                        },
                    )
                    val connectShadow = if (connectChrome) {
                        Modifier.dropShadow(
                            shape,
                            Shadow(
                                radius = MobileDesignGeometry.ConnectWidePanelShadowRadius,
                                color = openBitFunColors.shellScrim,
                                offset = DpOffset(0.dp, MobileDesignGeometry.ConnectWidePanelShadowOffsetY),
                            ),
                        )
                    } else Modifier
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        shape = shape,
                        shadowElevation = if (connectChrome || centered) 0.dp else MobileDesignGeometry.PopoverShadowRadius,
                        modifier = Modifier
                            .width(placement.width.dp)
                            .height(placement.height.dp)
                            .then(connectShadow)
                            .then(if (centered) {
                                Modifier.testTag(if (connectChrome) "connect-centered-panel" else "settings-centered-panel")
                            } else Modifier)
                            .pointerInput(Unit) { detectTapGestures(onTap = {}) },
                    ) {
                        content(Modifier.fillMaxSize())
                    }
                }
            }
        }
        return
    }

    val height = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.height.toDp() }
    val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background,
        scrimColor = if (connectChrome) MaterialTheme.colorScheme.scrim else scrimColor,
        shape = RoundedCornerShape(
            topStart = MobileDesignGeometry.SheetTopRadius,
            topEnd = MobileDesignGeometry.SheetTopRadius,
        ),
        dragHandle = null,
        sheetGesturesEnabled = draggable,
        contentWindowInsets = { if (edgeToEdgeContent) WindowInsets(0) else BottomSheetDefaults.windowInsets },
    ) {
        CompositionLocalProvider(
            LocalContext provides hostContext,
            LocalConfiguration provides hostConfiguration,
        ) {
            val modifier = if (fitContent) {
                Modifier.fillMaxWidth().heightIn(max = (height - topInset - 8.dp).coerceAtLeast(0.dp))
            } else if (edgeToEdgeContent && !connectChrome && placement.mode != SettingsPlacementMode.FOLD_OPERATE) {
                Modifier.fillMaxWidth().height((height - topInset - 8.dp).coerceAtLeast(0.dp))
            } else if (placement.mode == SettingsPlacementMode.FOLD_OPERATE && placement.height > 0) {
                Modifier.fillMaxWidth().height(placement.height.dp)
            } else {
                Modifier.fillMaxWidth().fillMaxHeight(0.94f)
            }
            content(modifier)
        }
    }
}
