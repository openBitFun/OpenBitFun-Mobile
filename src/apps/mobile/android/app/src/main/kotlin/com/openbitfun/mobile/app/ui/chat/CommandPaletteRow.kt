package com.openbitfun.mobile.app.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.core.feature.session.CommandPaletteCatalogStatus
import com.openbitfun.mobile.core.feature.session.CommandPaletteUiState
import com.openbitfun.mobile.core.feature.session.CommandPaletteUsageStatus
import com.openbitfun.mobile.core.feature.session.RemoteSessionIntent

private enum class PaletteSheet { SKILLS, USAGE }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CommandPaletteRow(
    palette: CommandPaletteUiState,
    sessionId: String,
    draft: String,
    busy: Boolean,
    onIntent: (RemoteSessionIntent) -> Unit,
    modifier: Modifier = Modifier,
) {
    var sheet by remember { mutableStateOf<PaletteSheet?>(null) }
    Column(modifier.fillMaxWidth().testTag("command-palette")) {
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth().height(42.dp).padding(horizontal = 16.dp),
        ) {
            item {
                AssistChip(
                    onClick = { onIntent(RemoteSessionIntent.RunCommandPaletteAction(sessionId, "compact")) },
                    label = { Text(stringResource(R.string.command_compact)) },
                    leadingIcon = { PaletteChipIcon(palette.runningCommand == "compact", "↕") },
                    colors = paletteChipColors(palette.runningCommand == "compact", draft.trim() == "/goal "),
                    enabled = !busy && palette.runningCommand.isEmpty(),
                )
            }
            item {
                AssistChip(
                    onClick = { onIntent(RemoteSessionIntent.RunCommandPaletteAction(sessionId, "init_agents_md")) },
                    label = { Text(stringResource(R.string.command_init)) },
                    leadingIcon = { PaletteChipIcon(palette.runningCommand == "init_agents_md", "▤") },
                    colors = paletteChipColors(palette.runningCommand == "init_agents_md", draft.trim() == "/goal "),
                    enabled = !busy && palette.runningCommand.isEmpty(),
                )
            }
            item {
                AssistChip(
                    onClick = {
                        when {
                            draft == "/goal " -> onIntent(RemoteSessionIntent.UpdateDraft(""))
                            draft.trim().isEmpty() -> onIntent(RemoteSessionIntent.UpdateDraft("/goal "))
                        }
                    },
                    label = { Text(stringResource(R.string.command_goal)) },
                    leadingIcon = { Text("☑") },
                    colors = paletteChipColors(false, draft == "/goal "),
                )
            }
            item {
                AssistChip(
                    onClick = {
                        sheet = PaletteSheet.USAGE
                        onIntent(RemoteSessionIntent.RefreshCommandPaletteUsage)
                    },
                    label = { Text(stringResource(R.string.command_usage)) },
                    leadingIcon = { Text("▦") },
                    colors = paletteChipColors(false, draft == "/goal "),
                    enabled = !busy && palette.runningCommand.isEmpty(),
                )
            }
            item {
                AssistChip(
                    onClick = { sheet = PaletteSheet.SKILLS },
                    label = { Text(stringResource(R.string.command_skills)) },
                    leadingIcon = { Text("⚒") },
                    trailingIcon = { Text("⌃") },
                )
            }
        }
        if (palette.noticeLabelKey.isNotBlank()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    palette.noticeDetail.ifBlank { commandNoticeText(palette.noticeLabelKey) },
                    modifier = Modifier.weight(1f),
                )
                if (palette.noticeRetryAction.isNotBlank()) {
                    TextButton(onClick = { onIntent(RemoteSessionIntent.RunCommandPaletteAction(sessionId, palette.noticeRetryAction)) }) {
                        Text(stringResource(R.string.command_retry))
                    }
                }
            }
        }
    }

    if (sheet != null) {
        ModalBottomSheet(onDismissRequest = { sheet = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            when (sheet) {
                PaletteSheet.SKILLS -> SkillPickerContent(palette, onIntent, onClose = { sheet = null })
                PaletteSheet.USAGE -> UsageReportContent(palette, onIntent, onClose = { sheet = null })
                null -> Unit
            }
        }
    }
}

@Composable
private fun PaletteChipIcon(running: Boolean, glyph: String) {
    if (running) {
        CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
    } else {
        Text(glyph)
    }
}

@Composable
private fun paletteChipColors(running: Boolean, goalPending: Boolean) =
    AssistChipDefaults.assistChipColors(
        containerColor = if (goalPending) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.surfaceVariant,
        labelColor = if (goalPending) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.onSurface,
        leadingIconContentColor = if (goalPending) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.onSurface,
        trailingIconContentColor = if (goalPending) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.onSurface,
        disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
        disabledLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
    )

@Composable
private fun SkillPickerContent(
    palette: CommandPaletteUiState,
    onIntent: (RemoteSessionIntent) -> Unit,
    onClose: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().padding(16.dp).widthIn(max = 520.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(stringResource(R.string.command_skills_title), style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onClose) { Text(stringResource(R.string.common_close)) }
        }
        OutlinedTextField(query, { query = it }, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp), label = { Text(stringResource(R.string.command_skills_search)) })
        if (palette.catalogStatus == CommandPaletteCatalogStatus.LOADING) {
            Text(stringResource(R.string.command_loading))
        } else if (palette.catalogStatus == CommandPaletteCatalogStatus.FAILED) {
            Text(palette.catalogErrorText.ifBlank { stringResource(R.string.command_skills_failed) })
            TextButton(onClick = { onIntent(RemoteSessionIntent.RefreshCommandCatalog) }) { Text(stringResource(R.string.command_retry)) }
        } else if (palette.skills.isEmpty()) {
            Text(stringResource(R.string.command_skills_empty))
        } else {
            palette.skills
                .filter { query.isBlank() || it.name.contains(query, true) || it.id.contains(query, true) || it.description.contains(query, true) }
                .groupBy { it.group.ifBlank { if (it.source == "builtin") "Built-in" else "Custom" } }
                .toSortedMap()
                .forEach { (group, skills) ->
                    Text(group, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 8.dp))
                    skills.forEach { skill ->
                        TextButton(
                            onClick = {
                                onIntent(RemoteSessionIntent.SelectCommandPaletteSkill(skill.id, skill.name))
                                onClose()
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.fillMaxWidth()) {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(skill.name)
                                    if (palette.skillId == skill.id) Text("✓")
                                }
                                if (skill.description.isNotBlank()) {
                                    Text(skill.description, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                    }
                }
        }
    }
}

@Composable
private fun UsageReportContent(palette: CommandPaletteUiState, onIntent: (RemoteSessionIntent) -> Unit, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(16.dp).widthIn(max = 520.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(stringResource(R.string.command_usage_title), style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onClose) { Text(stringResource(R.string.common_close)) }
        }
        when (palette.usageStatus) {
            CommandPaletteUsageStatus.LOADING -> Text(stringResource(R.string.command_loading), Modifier.padding(vertical = 16.dp))
            CommandPaletteUsageStatus.FAILED -> {
                Text(palette.usageErrorText.ifBlank { stringResource(R.string.command_usage_failed) })
                TextButton(onClick = { onIntent(RemoteSessionIntent.RefreshCommandPaletteUsage) }) { Text(stringResource(R.string.command_retry)) }
            }
            else -> if (palette.usageSections.isEmpty()) {
                Text(stringResource(R.string.command_usage_empty), Modifier.padding(vertical = 16.dp))
            } else {
                palette.usageSections.forEach { section ->
                    Text(stringResourceByKey(section.titleKey), modifier = Modifier.padding(top = 12.dp))
                    section.rows.forEach { row ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(stringResourceByKey(row.labelKey))
                            Text(if (row.valueKey.isBlank()) row.value else stringResourceByKey(row.valueKey))
                        }
                    }
                    HorizontalDivider()
                }
                if (palette.usagePartial) Text(stringResource(R.string.usage_partial_note), Modifier.padding(top = 8.dp))
            }
        }
    }
}

@Composable
private fun stringResourceByKey(key: String): String = when (key) {
    "usage.sectionOverview" -> stringResource(R.string.usage_section_overview)
    "usage.sectionTime" -> stringResource(R.string.usage_section_time)
    "usage.sectionTokens" -> stringResource(R.string.usage_section_tokens)
    "usage.sectionModels" -> stringResource(R.string.usage_section_models)
    "usage.sectionTools" -> stringResource(R.string.usage_section_tools)
    "usage.sectionFiles" -> stringResource(R.string.usage_section_files)
    "usage.sectionCompression" -> stringResource(R.string.usage_section_compression)
    "usage.sectionErrors" -> stringResource(R.string.usage_section_errors)
    "usage.sectionPrivacy" -> stringResource(R.string.usage_section_privacy)
    "usage.scopeTurns" -> stringResource(R.string.usage_scope_turns)
    "usage.scopeKind" -> stringResource(R.string.usage_scope_kind)
    "usage.scopeSubagents" -> stringResource(R.string.usage_scope_subagents)
    "usage.workspace" -> stringResource(R.string.usage_workspace)
    "usage.coverageLevel" -> stringResource(R.string.usage_coverage_level)
    "usage.coverageMissing" -> stringResource(R.string.usage_coverage_missing)
    "usage.timeSpan" -> stringResource(R.string.usage_time_span)
    "usage.timeTurns" -> stringResource(R.string.usage_time_turns)
    "usage.timeModel" -> stringResource(R.string.usage_time_model)
    "usage.timeTools" -> stringResource(R.string.usage_time_tools)
    "usage.tokensInput" -> stringResource(R.string.usage_tokens_input)
    "usage.tokensOutput" -> stringResource(R.string.usage_tokens_output)
    "usage.tokensTotal" -> stringResource(R.string.usage_tokens_total)
    "usage.tokensCached" -> stringResource(R.string.usage_tokens_cached)
    "usage.filesChanged" -> stringResource(R.string.usage_files_changed)
    "usage.filesAdded" -> stringResource(R.string.usage_files_added)
    "usage.filesDeleted" -> stringResource(R.string.usage_files_deleted)
    "usage.compactionCount" -> stringResource(R.string.usage_compaction_count)
    "usage.manualCompactionCount" -> stringResource(R.string.usage_manual_compaction_count)
    "usage.automaticCompactionCount" -> stringResource(R.string.usage_automatic_compaction_count)
    "usage.compactionSaved" -> stringResource(R.string.usage_compaction_saved)
    "usage.modelRow" -> stringResource(R.string.usage_model_row)
    "usage.toolRow" -> stringResource(R.string.usage_tool_row)
    "usage.errorsTotal" -> stringResource(R.string.usage_errors_total)
    "usage.errorsTools" -> stringResource(R.string.usage_errors_tools)
    "usage.errorsModels" -> stringResource(R.string.usage_errors_models)
    "usage.privacyPrompt" -> stringResource(R.string.usage_privacy_prompt)
    "usage.privacyTools" -> stringResource(R.string.usage_privacy_tools)
    "usage.privacyCommands" -> stringResource(R.string.usage_privacy_commands)
    "usage.privacyFiles" -> stringResource(R.string.usage_privacy_files)
    "usage.yes" -> stringResource(R.string.usage_yes)
    "usage.no" -> stringResource(R.string.usage_no)
    else -> key
}

@Composable
private fun commandNoticeText(key: String): String = when (key) {
    "chat.rolledBackNotice" -> stringResource(R.string.chat_rollback_done)
    "chat.rollbackFailed" -> stringResource(R.string.chat_rollback_failed)
    "commands.compactDone" -> stringResource(R.string.command_compact_done)
    "commands.initDone" -> stringResource(R.string.command_init_done)
    "commands.compactFailed" -> stringResource(R.string.command_compact_failed)
    "commands.initFailed" -> stringResource(R.string.command_init_failed)
    else -> key
}
