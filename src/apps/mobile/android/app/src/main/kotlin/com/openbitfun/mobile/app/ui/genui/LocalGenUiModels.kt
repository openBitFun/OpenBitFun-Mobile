package com.openbitfun.mobile.app.ui.genui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignBreakpoints
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as Geometry
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.genui.LocalGenUiIntent
import com.openbitfun.mobile.core.feature.genui.LocalGenUiModelUi
import com.openbitfun.mobile.core.feature.genui.LocalGenUiState

// The activity ViewModel keeps the open panel through configuration changes.
internal class GenUiModelPanel(val owner: String, val setup: Boolean, startInEditor: Boolean) {
    var editor by mutableStateOf(if (startInEditor) GenUiModelDraft(null) else null)
    var deleting by mutableStateOf(false)
    var pendingSerial by mutableStateOf<Int?>(null)
    val listScroll = ScrollState(0)
}

internal class GenUiModelDraft(profile: LocalGenUiModelUi?) {
    val modelId = profile?.id
    var name by mutableStateOf(profile?.name.orEmpty())
    var endpoint by mutableStateOf(profile?.endpoint.orEmpty())
    var modelName by mutableStateOf(profile?.model.orEmpty())
    var secret by mutableStateOf("")
    var revealed by mutableStateOf(false)
    var requested by mutableStateOf(false)
    val scroll = ScrollState(0)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LocalGenUiModelSheet(
    state: LocalGenUiState,
    dispatch: (LocalGenUiIntent) -> Unit,
    panel: GenUiModelPanel,
    onClose: () -> Unit,
) {
    val setup = panel.setup
    val editor = panel.editor
    val authorizeEndpoint = rememberGenUiNetworkConsent()
    val profile = editor?.modelId?.let { id -> state.models.firstOrNull { it.id == id } }
    val writing by rememberUpdatedState(state.writingModel)
    val centered = LocalConfiguration.current.screenWidthDp >= MobileDesignBreakpoints.Wide
    val scrim = MobileDesignColors.Light.GenuiModelScrim

    fun showPage(next: GenUiModelDraft?) {
        dispatch(LocalGenUiIntent.ResetModelEditor)
        panel.editor = next
    }

    fun closePage() {
        if (writing) return
        if (editor == null || (setup && state.models.isEmpty())) onClose()
        else showPage(null)
    }

    fun write(intent: LocalGenUiIntent) {
        if (panel.pendingSerial != null) return
        panel.pendingSerial = state.modelWriteSerial
        dispatch(intent)
    }

    LaunchedEffect(state.modelWriteSerial, state.modelWriteFailure) {
        val pending = panel.pendingSerial ?: return@LaunchedEffect
        if (pending != state.modelWriteSerial) {
            panel.pendingSerial = null
            if (setup) onClose()
            else showPage(null)
        } else if (state.modelWriteFailure != null) panel.pendingSerial = null
    }

    val content: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier) {
            val title = when {
                setup -> R.string.genui_configure
                editor == null -> R.string.genui_models
                editor.modelId == null -> R.string.genui_add_model
                else -> R.string.genui_edit_model
            }
            Row(
                Modifier.fillMaxWidth().height(Geometry.SheetHeaderHeight).padding(start = 16.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(title), Modifier.weight(1f), fontWeight = FontWeight.Medium,
                    style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = ::closePage, enabled = !writing) {
                    Icon(painterResource(R.drawable.ic_symbol_xmark), stringResource(R.string.common_close), Modifier.size(18.dp))
                }
            }
            HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            if (editor == null) {
                Column(
                    Modifier.fillMaxWidth().verticalScroll(panel.listScroll)
                        .padding(start = Geometry.ContentGutter, end = Geometry.ContentGutter, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(Geometry.GenuiModelListSpacing),
                ) {
                    if (state.models.isEmpty()) Text(
                        stringResource(R.string.genui_no_models), Modifier.padding(vertical = 8.dp),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    state.models.forEach { item ->
                        val shape = RoundedCornerShape(Geometry.SettingsCardRadius)
                        Row(
                            Modifier.fillMaxWidth().clip(shape)
                                .background(MaterialTheme.colorScheme.surface)
                                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
                                .clickable(enabled = !writing, role = Role.Button) {
                                    if (setup && item.hasStoredKey) write(LocalGenUiIntent.UseModelForSetup(item.id))
                                    else showPage(GenUiModelDraft(item))
                                }.padding(Geometry.GenuiModelFieldPadding),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(item.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${item.model} · ${modelHost(item.endpoint)}", style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            if (item.id == state.selectedModelId) Text(
                                stringResource(R.string.genui_current_model), style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Icon(painterResource(R.drawable.ic_symbol_chevron_right), null, Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    GenUiModelAction(stringResource(R.string.genui_add_model), enabled = !writing) { showPage(GenUiModelDraft(null)) }
                    GenUiFailure(state.modelWriteFailure, Modifier)
                }
            } else {
                key(editor) {
                    GenUiModelFields(
                        editor, profile, state, setup, dispatch, ::write,
                        authorizeEndpoint = { endpoint, action ->
                            authorizeEndpoint(endpoint) { if (panel.editor === editor) action() }
                        },
                        onDelete = { panel.deleting = true },
                    )
                }
            }
        }
    }
    if (centered) {
        Dialog(
            onDismissRequest = { if (!writing) onClose() },
            properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnBackPress = !writing,
                dismissOnClickOutside = !writing),
        ) {
            val window = (LocalView.current.parent as? DialogWindowProvider)?.window
            SideEffect { window?.setDimAmount(scrim.alpha) }
            content(Modifier.testTag("local-genui-model-centered").padding(16.dp).size(Geometry.GenuiModelPanelWidth, Geometry.GenuiModelPanelHeight)
                .background(MaterialTheme.colorScheme.background, RoundedCornerShape(Geometry.SheetTopRadius))
                .clip(RoundedCornerShape(Geometry.SheetTopRadius)))
        }
    } else {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
            it != SheetValue.Hidden || !writing
        })
        ModalBottomSheet(
            sheetState = sheet,
            onDismissRequest = { if (!writing) onClose() },
            shape = RoundedCornerShape(topStart = Geometry.SheetTopRadius, topEnd = Geometry.SheetTopRadius),
            containerColor = MaterialTheme.colorScheme.background,
            scrimColor = scrim,
            sheetMaxWidth = Geometry.SheetContentMaxWidth,
            dragHandle = null,
            sheetGesturesEnabled = !writing,
        ) {
            val window = (LocalView.current.parent as? DialogWindowProvider)?.window
            SideEffect { window?.setDimAmount(0f) }
            content(Modifier.testTag("local-genui-model-bottom-sheet").fillMaxWidth().fillMaxHeight(.94f))
        }
    }
    if (panel.deleting && profile != null) {
        GenUiDeleteDialog(
            onCancel = { panel.deleting = false },
            onConfirm = {
                panel.deleting = false
                write(LocalGenUiIntent.DeleteModel(profile.id))
            },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GenUiModelFields(
    draft: GenUiModelDraft,
    profile: LocalGenUiModelUi?,
    state: LocalGenUiState,
    setup: Boolean,
    dispatch: (LocalGenUiIntent) -> Unit,
    write: (LocalGenUiIntent) -> Unit,
    authorizeEndpoint: (String, () -> Unit) -> Unit,
    onDelete: () -> Unit,
) {
    val enabled = !state.writingModel
    val retainsKey = profile?.hasStoredKey == true && draft.endpoint.trim().trimEnd('/') == profile.endpoint

    fun clearDiscovery() {
        if (draft.requested) {
            draft.requested = false
            dispatch(LocalGenUiIntent.CancelModelDiscovery)
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(draft.scroll)
            .padding(start = Geometry.ContentGutter, end = Geometry.ContentGutter, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(Geometry.GenuiModelEditorSpacing),
    ) {
        val display = stringResource(R.string.genui_model_name)
        GenUiFieldLabel(display)
        GenUiModelField(draft.name, { draft.name = it }, display, stringResource(R.string.genui_model_name_hint), enabled, "genui-model-display")

        val url = stringResource(R.string.genui_endpoint)
        GenUiFieldLabel(url)
        GenUiModelField(draft.endpoint, { draft.endpoint = it; clearDiscovery() }, url, "https://api.example.com/v1", enabled,
            "genui-model-url", KeyboardType.Uri)

        val keyLabel = stringResource(R.string.genui_token)
        GenUiFieldLabel(keyLabel)
        GenUiModelField(draft.secret, { draft.secret = it; clearDiscovery() }, keyLabel,
            if (retainsKey) stringResource(R.string.genui_keep_key) else keyLabel,
            enabled, "genui-model-key", KeyboardType.Password, hidden = !draft.revealed) {
            IconButton(onClick = { draft.revealed = !draft.revealed }, enabled = enabled, modifier = Modifier.size(36.dp)) {
                Icon(painterResource(if (draft.revealed) R.drawable.ic_symbol_eye else R.drawable.ic_symbol_eye_slash),
                    stringResource(if (draft.revealed) R.string.genui_hide_key else R.string.genui_show_key), Modifier.size(18.dp))
            }
        }
        val modelLabel = stringResource(R.string.genui_model_id)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { GenUiFieldLabel(modelLabel) }
            if (state.discoveringModels) CircularProgressIndicator(Modifier.padding(end = 8.dp).size(18.dp), strokeWidth = 2.dp)
            val fetchEnabled = enabled && !state.discoveringModels && draft.endpoint.isNotBlank()
            GenUiModelChip(
                stringResource(R.string.genui_fetch_models), selected = false, enabled = fetchEnabled,
            ) {
                val request = LocalGenUiIntent.DiscoverModels(profile?.id, draft.endpoint, draft.secret)
                authorizeEndpoint(draft.endpoint) {
                    if (draft.endpoint == request.endpoint && draft.secret == request.apiKey) {
                        draft.requested = true
                        dispatch(request)
                    }
                }
            }
        }
        GenUiModelField(draft.modelName, { draft.modelName = it }, modelLabel, modelLabel, enabled, "genui-model-name", KeyboardType.Ascii)

        if (state.discoveredModels.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.discoveredModels.forEach { id ->
                    GenUiModelChip(id, selected = id == draft.modelName, enabled = enabled) { draft.modelName = id }
                }
            }
        } else if (draft.requested && !state.discoveringModels && state.modelDiscoveryFailure == null) {
            Text(stringResource(R.string.genui_no_discovered_models), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        GenUiFailure(state.modelDiscoveryFailure ?: state.modelWriteFailure, Modifier)
        GenUiModelAction(
            stringResource(if (setup) R.string.genui_save_and_use else R.string.genui_save), enabled = enabled,
        ) {
            write(LocalGenUiIntent.SaveModel(profile?.id, draft.name, draft.endpoint, draft.modelName, draft.secret, setup))
        }
        if (!setup && profile != null) {
            GenUiModelAction(stringResource(R.string.genui_delete_model), enabled, destructive = true, onClick = onDelete)
        }
    }
}

@Composable
private fun GenUiFieldLabel(label: String) {
    Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
}

@Composable
private fun GenUiModelField(
    value: String, onChange: (String) -> Unit, label: String, placeholder: String, enabled: Boolean,
    tag: String, keyboard: KeyboardType = KeyboardType.Text, hidden: Boolean = false,
    accessory: @Composable () -> Unit = {},
) {
    val colors = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(Geometry.SettingsCompactCardRadius)
    BasicTextField(
        value = value,
        onValueChange = onChange,
        enabled = enabled,
        singleLine = true,
        textStyle = MaterialTheme.typography.titleSmall.copy(color = colors.onSurface),
        cursorBrush = SolidColor(colors.primary),
        visualTransformation = if (hidden) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, autoCorrectEnabled = false),
        modifier = Modifier.fillMaxWidth().heightIn(min = Geometry.GenuiModelFieldHeight)
            .shadow(3.dp, shape, ambientColor = MobileDesignColors.Light.ShadowFaint, spotColor = openBitFunColors.shadowSubtle)
            .background(colors.surface, shape).border(.5.dp, colors.outlineVariant, shape)
            .semantics { contentDescription = label }.testTag(tag),
        decorationBox = { input ->
            Row(Modifier.fillMaxWidth().padding(horizontal = Geometry.GenuiModelFieldPadding),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, color = colors.outline, style = MaterialTheme.typography.titleSmall)
                    input()
                }
                accessory()
            }
        },
    )
}

@Composable
private fun GenUiModelChip(label: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Text(label, Modifier.clip(RoundedCornerShape(Geometry.GenuiModelChipRadius))
        .background(if (selected) colors.primary else colors.surfaceVariant)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .padding(horizontal = 10.dp, vertical = 6.dp),
        style = MaterialTheme.typography.labelSmall, color = if (selected) colors.onPrimary else colors.onSurface,
    )
}

@Composable
private fun GenUiModelAction(label: String, enabled: Boolean, destructive: Boolean = false, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Button(
        onClick, Modifier.fillMaxWidth().heightIn(min = Geometry.GenuiModelActionHeight), enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (destructive) colors.error else colors.primary,
            contentColor = if (destructive) colors.onError else colors.onPrimary,
        ),
        elevation = null,
    ) { Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Medium) }
}

internal fun modelHost(endpoint: String): String = endpoint.substringAfter("://", endpoint).substringBefore('/')
