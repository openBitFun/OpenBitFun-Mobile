package com.openbitfun.mobile.app.ui.remote

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.account.messageRes
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignTypography
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.account.AccountUiState

internal const val CONNECT_ACCOUNT_DEVICE_TEST_TAG: String = "connect-account-device"
internal const val CONNECT_ACCOUNT_DEVICE_REFRESH_TEST_TAG: String = "connect-account-device-refresh"
internal const val CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX: String = "connect-account-device-row:"

/** The signed-in landing page for remote control. */
@Composable
internal fun ConnectAccountDeviceScreen(
    state: AccountUiState.Ready,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onSelect: (String) -> Unit,
    modifier: Modifier,
    connected: Boolean = false,
    switchingDeviceId: String? = null,
    connectionFailed: Boolean = false,
    bottomInset: Dp = 0.dp,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .testTag(CONNECT_ACCOUNT_DEVICE_TEST_TAG),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 72.dp)
                .padding(start = 8.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                val iconHeight = MobileDesignGeometry.NavigationBackIconSize
                Icon(
                    painterResource(R.drawable.connect_remote_ref_back),
                    contentDescription = stringResource(R.string.common_back),
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(iconHeight * (15f / 23f), iconHeight),
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.connect_account_devices_title),
                    style = MobileDesignTypography.ConversationHeaderTitle,
                )
                Text(
                    stringResource(R.string.connect_account_devices_subtitle),
                    style = MobileDesignTypography.BodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = MobileDesignGeometry.SheetContentMaxWidth)
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = bottomInset + 24.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Text(
                    stringResource(R.string.connect_account_devices_body),
                    style = MobileDesignTypography.BodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                DeviceListCard(state, connected, switchingDeviceId, connectionFailed, onRefresh, onSelect)
            }
        }
    }
}

@Composable
private fun DeviceListCard(
    state: AccountUiState.Ready,
    connected: Boolean,
    switchingDeviceId: String?,
    connectionFailed: Boolean,
    onRefresh: () -> Unit,
    onSelect: (String) -> Unit,
) {
    val hasError = connectionFailed || state.refreshFailure != null
    Surface(
        shape = RoundedCornerShape(MobileDesignGeometry.SheetGroupRadius),
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().height(MobileDesignGeometry.SheetRowHeight),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.connect_account_devices_available),
                    style = MobileDesignTypography.BodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Spacer(Modifier.weight(1f))
                Box(
                    modifier = Modifier
                        .height(MobileDesignGeometry.ControlTouchSize)
                        .testTag(CONNECT_ACCOUNT_DEVICE_REFRESH_TEST_TAG)
                        .clickable(enabled = !state.refreshing, onClick = onRefresh)
                        .padding(horizontal = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(when {
                            state.refreshing -> R.string.connect_account_devices_loading
                            hasError -> R.string.account_devices_retry
                            else -> R.string.account_devices_refresh
                        }),
                        style = MobileDesignTypography.BodyMedium,
                        color = when {
                            state.refreshing -> MaterialTheme.colorScheme.onSurfaceVariant
                            hasError -> MaterialTheme.colorScheme.error
                            else -> MaterialTheme.colorScheme.primary
                        },
                    )
                }
            }
            when {
                state.devices.isEmpty() && state.refreshing -> Column {
                    repeat(2) { DeviceSkeletonRow() }
                }
                state.devices.isEmpty() -> Box(
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        stringResource(state.refreshFailure?.messageRes() ?: R.string.connect_account_devices_empty),
                        style = MobileDesignTypography.BodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                else -> Column {
                    state.devices.forEach { device ->
                        val selected = device.id == state.selectedDeviceId
                        val controlling = selected && connected && device.controllable
                        val switching = device.id == switchingDeviceId
                        val enabled = device.controllable && device.online && switchingDeviceId == null
                        val presence = stringResource(if (device.online) R.string.account_online else R.string.account_offline)
                        val status = when {
                            !device.controllable -> stringResource(R.string.account_device_incompatible)
                            switching -> stringResource(R.string.connect_account_device_connecting)
                            controlling -> stringResource(R.string.account_device_controlling, presence)
                            selected -> stringResource(R.string.connect_account_device_last_used, presence)
                            else -> presence
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(60.dp)
                                .testTag(CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX + device.id)
                                .clickable(enabled = enabled, onClick = { onSelect(device.id) })
                                .alpha(if (enabled) 1f else 0.64f)
                                .padding(horizontal = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                painterResource(R.drawable.connect_sidebar_device_desktop),
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(MobileDesignGeometry.SheetIconSize),
                            )
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
                                Text(
                                    device.displayName,
                                    style = MobileDesignTypography.BodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    status,
                                    style = MobileDesignTypography.BodySmall,
                                    color = if (device.online && device.controllable) openBitFunColors.statusSuccess
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            if (enabled && !controlling) {
                                Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = RoundedCornerShape(14.dp)) {
                                    Text(
                                        stringResource(R.string.account_connect),
                                        style = MobileDesignTypography.BodyMedium,
                                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                    )
                                }
                            } else if (device.online && device.controllable) {
                                Icon(
                                    painterResource(R.drawable.ic_symbol_chevron_right),
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.44f),
                                    modifier = Modifier.size(13.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DeviceSkeletonRow() {
    val placeholder = MaterialTheme.colorScheme.surfaceVariant
    Row(
        modifier = Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(width = 26.dp, height = 22.dp).background(placeholder, RoundedCornerShape(5.dp)))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Box(Modifier.fillMaxWidth(0.58f).height(12.dp).background(placeholder, RoundedCornerShape(4.dp)))
            Box(Modifier.width(52.dp).height(9.dp).background(placeholder, RoundedCornerShape(4.dp)))
        }
    }
}
