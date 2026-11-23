package com.openbitfun.mobile.core.feature.session

/** Lifecycle of the host skill catalog probe. */
public enum class CommandPaletteCatalogStatus { IDLE, LOADING, READY, FAILED }

/** Lifecycle of a session usage report read. */
public enum class CommandPaletteUsageStatus { IDLE, LOADING, READY, FAILED }

/** One skill row returned by the desktop mode catalog. */
public data class CommandPaletteSkill public constructor(
    public val id: String,
    public val name: String,
    public val description: String,
    public val group: String,
    public val source: String,
    public val shadowed: Boolean,
    public val selectedForRuntime: Boolean,
    public val effectiveEnabled: Boolean,
    public val globallyEnabled: Boolean,
    public val allowUserInvocation: Boolean,
)

/** One already formatted usage row. Labels remain source keys for native localization. */
public data class CommandPaletteUsageRow public constructor(
    public val labelKey: String,
    public val value: String,
    public val valueKey: String,
)

/** A section in the usage sheet. */
public data class CommandPaletteUsageSection public constructor(
    public val id: String,
    public val titleKey: String,
    public val rows: List<CommandPaletteUsageRow>,
)

/** Shared remote state for the command chips and their two sheets. */
public data class CommandPaletteUiState public constructor(
    public val catalogStatus: CommandPaletteCatalogStatus,
    public val catalogFailure: String,
    public val catalogErrorText: String,
    public val skills: List<CommandPaletteSkill>,
    public val runningCommand: String,
    public val noticeKind: String,
    public val noticeLabelKey: String,
    public val noticeDetail: String,
    public val noticeRetryAction: String,
    public val usageStatus: CommandPaletteUsageStatus,
    public val usageSections: List<CommandPaletteUsageSection>,
    public val usagePartial: Boolean,
    public val usageErrorText: String,
    public val skillId: String,
    public val skillLabel: String,
) {
    public companion object {
        public fun empty(): CommandPaletteUiState = CommandPaletteUiState(
            catalogStatus = CommandPaletteCatalogStatus.IDLE,
            catalogFailure = "",
            catalogErrorText = "",
            skills = emptyList(),
            runningCommand = "",
            noticeKind = "",
            noticeLabelKey = "",
            noticeDetail = "",
            noticeRetryAction = "",
            usageStatus = CommandPaletteUsageStatus.IDLE,
            usageSections = emptyList(),
            usagePartial = false,
            usageErrorText = "",
            skillId = "",
            skillLabel = "",
        )
    }
}
