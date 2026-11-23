package com.openbitfun.mobile.app.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as Geometry
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignTypography as Typography
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.session.DeviceModelAvailability
import com.openbitfun.mobile.core.feature.session.DeviceModelDefaultsUiState
import com.openbitfun.mobile.core.feature.session.DeviceModelOperation
import com.openbitfun.mobile.core.feature.session.DeviceModelRole
import com.openbitfun.mobile.core.feature.session.DeviceModelRoleUi

@Composable
internal fun DeviceModelSettingsEntry(availability: DeviceModelAvailability, onClick: () -> Unit) {
    val enabled = availability == DeviceModelAvailability.AVAILABLE
    Box(contentAlignment = Alignment.TopEnd) {
        Row(
            Modifier.clip(RoundedCornerShape(Geometry.SettingsGroupRadius))
                .clickable(enabled = enabled || availability == DeviceModelAvailability.UNSUPPORTED,
                    role = Role.Button, onClick = onClick)
                .testTag("device-model-settings")
                .heightIn(min = Geometry.ControlTouchSize)
                .alpha(if (enabled) 1f else .38f)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(horizontal = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(painterResource(R.drawable.ic_symbol_gearshape), null, Modifier.size(16.dp))
            Text(stringResource(R.string.device_models_title), style = Typography.BodyMedium,
                fontWeight = FontWeight.Medium, maxLines = 1)
        }
        if (availability == DeviceModelAvailability.UNSUPPORTED) {
            Text(stringResource(R.string.device_models_upgrade),
                Modifier.offset(y = (-8).dp).background(MaterialTheme.colorScheme.onSurface, RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp),
                color = MaterialTheme.colorScheme.surface, style = Typography.LabelSmall, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
internal fun DeviceModelSettingsPage(
    state: DeviceModelDefaultsUiState,
    desktopName: String,
    role: DeviceModelRole?,
    onPickRole: (DeviceModelRole) -> Unit,
    onSelect: (DeviceModelRole, String?) -> Unit,
    onRetry: () -> Unit,
    onBack: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val saving = state.operation == DeviceModelOperation.SAVING
    val connected = state.availability != DeviceModelAvailability.DISCONNECTED
    val selectedRole = state.roles.firstOrNull { it.role == role }
    val colors = MaterialTheme.colorScheme
    BackHandler { if (!saving) onBack() }
    Column(modifier.fillMaxSize().background(colors.background).testTag("device-model-defaults")) {
        Row(Modifier.fillMaxWidth().heightIn(min = Geometry.SheetHeaderHeight)
            .padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, enabled = !saving) {
                Icon(painterResource(R.drawable.ic_symbol_chevron_left), stringResource(R.string.common_back), Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.device_models_title), style = Typography.BodySmall, color = colors.onSurfaceVariant)
                Text(role?.let { stringResource(it.titleRes) } ?: desktopName,
                    style = Typography.ConversationHeaderTitle, fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            IconButton(onClick = onClose, enabled = !saving) {
                Icon(painterResource(R.drawable.ic_symbol_xmark), stringResource(R.string.common_close), Modifier.size(18.dp))
            }
        }
        HorizontalDivider(thickness = .5.dp)
        key(role) {
            Column(
                Modifier.widthIn(max = Geometry.SettingsContentMaxWidth).fillMaxWidth()
                    .align(Alignment.CenterHorizontally).verticalScroll(rememberScrollState())
                    .padding(start = Geometry.SheetHorizontalPadding, end = Geometry.SheetHorizontalPadding,
                        top = if (role == null) 16.dp else 12.dp, bottom = 34.dp),
                verticalArrangement = Arrangement.spacedBy(Geometry.SettingsSectionGap),
            ) {
                if (role == null) {
                    SettingsCard(Modifier, Geometry.SettingsGroupRadius, bordered = true) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = Geometry.ModelSourceRowHeight)
                                .padding(horizontal = Geometry.SettingsRowPadding, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Icon(painterResource(R.drawable.ic_symbol_desktop), null, Modifier.size(Geometry.SettingsIconSize))
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(desktopName, style = Typography.BodyMedium, fontWeight = FontWeight.Medium)
                                val link = stringResource(if (connected) R.string.connection_connected else R.string.remote_settings_source_none)
                                Text("$link · ${stringResource(R.string.model_service_account_source)}",
                                    style = Typography.BodySmall,
                                    color = if (connected) openBitFunColors.statusSuccess else colors.onSurfaceVariant)
                            }
                        }
                    }
                }

                if (role == null && state.roles.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.models_title), Modifier.padding(start = 8.dp),
                            style = Typography.BodySmall, color = colors.onSurfaceVariant)
                        SettingsCard(Modifier, Geometry.SettingsGroupRadius, bordered = true) {
                            state.roles.forEach { row ->
                                DeviceModelRow(stringResource(row.role.titleRes),
                                    row.valueText(), row.resolved, state.canEdit, navigation = true,
                                    saving = saving && state.activeRole == row.role,
                                    updated = state.operation == DeviceModelOperation.SAVED && state.activeRole == row.role,
                                ) { onPickRole(row.role) }
                            }
                        }
                    }
                }

                val status = when (state.availability) {
                    DeviceModelAvailability.DISCONNECTED -> R.string.remote_settings_source_none
                    DeviceModelAvailability.CHECKING -> R.string.device_models_load
                    DeviceModelAvailability.UNSUPPORTED -> R.string.device_models_unsupported
                    DeviceModelAvailability.AVAILABLE -> when (state.operation) {
                        DeviceModelOperation.IDLE, DeviceModelOperation.LOADING -> R.string.device_models_load
                        DeviceModelOperation.SAVING -> R.string.device_models_save
                        DeviceModelOperation.SAVED -> R.string.device_models_updated
                        DeviceModelOperation.LOAD_FAILED -> R.string.device_models_load_failed
                        DeviceModelOperation.WRITE_FAILED -> R.string.device_models_save_failed
                        DeviceModelOperation.READY -> null
                    }
                }
                status?.let { text ->
                    SettingsCard(Modifier, Geometry.SettingsGroupRadius, bordered = true) {
                        Row(Modifier.fillMaxWidth().padding(Geometry.SettingsRowPadding),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (state.busy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            val value = state.roles.firstOrNull { it.role == state.activeRole }
                            val feedback = if (state.operation == DeviceModelOperation.SAVED && value != null) {
                                stringResource(R.string.device_models_updated_value, value.valueText())
                            } else stringResource(text)
                            Text(feedback, Modifier.weight(1f), style = Typography.BodySmall,
                                color = if (state.operation == DeviceModelOperation.SAVED) openBitFunColors.statusSuccess else colors.onSurface)
                            if (state.operation == DeviceModelOperation.LOAD_FAILED || state.operation == DeviceModelOperation.WRITE_FAILED) {
                                TextButton(onClick = onRetry) { Text(stringResource(R.string.model_catalog_retry)) }
                            }
                        }
                    }
                }

                if (role == null) {
                    if (state.roles.isNotEmpty() && !state.hasModels) {
                        SettingsCard(Modifier, Geometry.SettingsGroupRadius, bordered = true) {
                            Column(Modifier.fillMaxWidth().padding(horizontal = Geometry.SettingsRowPadding, vertical = 24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(painterResource(R.drawable.ic_symbol_desktop), null, Modifier.size(26.dp))
                                Text(stringResource(R.string.device_models_empty_catalog), style = Typography.BodyMedium)
                                Text(stringResource(R.string.device_models_empty_catalog_hint), style = Typography.BodySmall,
                                    color = colors.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            }
                        }
                    }
                    SettingsCard(Modifier, Geometry.SettingsGroupRadius, bordered = true) {
                        Column(Modifier.padding(horizontal = Geometry.SettingsRowPadding, vertical = 14.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            listOf(R.string.device_models_scope, R.string.device_models_fast_hint, R.string.device_models_image_hint)
                                .forEach { Text(stringResource(it), style = Typography.BodySmall, color = colors.onSurfaceVariant) }
                        }
                    }
                } else if (selectedRole != null) {
                    Column {
                        Text(stringResource(
                            if (role == DeviceModelRole.IMAGE_UNDERSTANDING) R.string.device_models_image_filter else R.string.device_models_text_filter,
                            desktopName), Modifier.padding(start = 4.dp, end = 4.dp, bottom = 12.dp),
                            style = Typography.LabelSmall, color = colors.onSurfaceVariant)
                        if (role.allowsUnset) {
                            DeviceModelRow(stringResource(role.unsetRes),
                                stringResource(role.hintRes),
                                selectedRole.selected == null, state.canEdit, navigation = false) { onSelect(role, null) }
                            if (selectedRole.choices.isNotEmpty()) {
                                HorizontalDivider(Modifier.padding(vertical = 6.dp), thickness = .5.dp)
                            }
                        }
                        if (selectedRole.choices.isEmpty()) {
                            Text(stringResource(R.string.device_models_empty), Modifier.padding(10.dp),
                                style = Typography.LabelSmall, color = colors.onSurfaceVariant)
                        }
                        selectedRole.choices.forEach { choice ->
                            DeviceModelRow(choice.title, choice.subtitle, selectedRole.selected?.id == choice.id,
                                state.canEdit, navigation = false, imageBadge = role == DeviceModelRole.IMAGE_UNDERSTANDING) {
                                onSelect(role, choice.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DeviceModelRow(
    title: String, subtitle: String, selected: Boolean, enabled: Boolean, navigation: Boolean,
    saving: Boolean = false, updated: Boolean = false, imageBadge: Boolean = false, onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    val highlighted = saving || !navigation && selected
    Row(Modifier.fillMaxWidth().heightIn(min = if (navigation) Geometry.SettingsDetailRowHeight else Geometry.ModelAccountRowHeight)
        .clip(RoundedCornerShape(Geometry.ComposerModelSelectorRowRadius))
        .background(if (highlighted) colors.surfaceVariant else openBitFunColors.transparent)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .semantics { if (!navigation) this.selected = selected }
        .padding(horizontal = if (navigation) Geometry.SettingsRowPadding else 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
            if (saving) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            else if (selected) Icon(painterResource(if (navigation) R.drawable.ic_symbol_checkmark else R.drawable.ic_symbol_checkmark_circle),
                null, Modifier.size(if (navigation) 18.dp else 16.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, Modifier.weight(1f), style = if (navigation) Typography.BodyMedium else Typography.TitleSmall,
                    fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (imageBadge) Text(stringResource(R.string.device_models_image_badge),
                    Modifier.background(colors.surfaceVariant, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 1.dp),
                    style = Typography.LabelSmall, color = colors.onSurfaceVariant)
            }
            if (subtitle.isNotEmpty()) Text(subtitle, style = Typography.LabelSmall, color = colors.onSurfaceVariant, maxLines = 2)
        }
        if (updated) Text(stringResource(R.string.device_models_updated), style = Typography.BodyMedium, color = openBitFunColors.statusSuccess)
        if (navigation) Icon(painterResource(R.drawable.ic_symbol_chevron_right), null, Modifier.size(14.dp), tint = colors.onSurfaceVariant)
    }
}

private val DeviceModelRole.titleRes: Int get() = when (this) {
    DeviceModelRole.PRIMARY -> R.string.model_primary
    DeviceModelRole.FAST -> R.string.model_fast
    DeviceModelRole.IMAGE_UNDERSTANDING -> R.string.device_models_image
}

private val DeviceModelRole.unsetRes: Int get() =
    if (this == DeviceModelRole.FAST) R.string.device_models_follow else R.string.model_service_not_configured

private val DeviceModelRole.hintRes: Int get() =
    if (this == DeviceModelRole.FAST) R.string.device_models_fast_unset else R.string.device_models_image_unset

@Composable
private fun DeviceModelRoleUi.valueText(): String {
    val choice = selected
    return when {
        choice != null -> listOf(choice.title, choice.subtitle).filter { it.isNotEmpty() }.joinToString(" · ")
        role.allowsUnset -> "${stringResource(role.unsetRes)} · ${stringResource(role.hintRes)}"
        else -> stringResource(role.unsetRes)
    }
}
