package com.openbitfun.mobile.core.feature.layout

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class SettingsPlacementPolicyTest {
    @Test
    fun phoneUsesBottomSheet() {
        assertEquals(SettingsPlacementMode.BOTTOM, resolve(width = 390, height = 844).mode)
    }

    @Test
    fun wideSettingsUseTheHarmonyPanelSizeAndCenterAcrossAContinuousWindow() {
        val reference = SettingsPlacement(SettingsPlacementMode.CENTER, 480, 560, 0)
        assertEquals(reference, resolve(707, 773))
        assertEquals(reference, resolve(773, 707))
        assertEquals(reference, resolve(1024, 1366))
        assertEquals(reference, resolve(2000, 1200))
        assertEquals(reference, SettingsPlacementPolicy.resolve(
            input(707, 773, vertical = listOf(WindowCrease(351, 5))),
            SettingsSheetKind.SETTINGS,
        ))
    }

    @Test
    fun smallLandscapeWindowCapsSettingsToItsHeightAndStillDocksDetailSheets() {
        assertEquals(SettingsPlacement(SettingsPlacementMode.CENTER, 480, 500, 0), resolve(800, 500))
        assertEquals(SettingsPlacement(SettingsPlacementMode.SIDE, 360, 560, 0),
            SettingsPlacementPolicy.resolve(input(800, 500), SettingsSheetKind.USER_MESSAGE_FULL_TEXT))
    }

    @Test
    fun sideSheetFitsTrailingPhysicalLeaf() {
        val input = input(1000, 800, vertical = listOf(WindowCrease(480, 20)))
        val placement = SettingsPlacementPolicy.resolve(input, SettingsSheetKind.USER_MESSAGE_FULL_TEXT)
        assertEquals(SettingsPlacement(SettingsPlacementMode.SIDE, 500, 720, 0), placement)
        assertFalse(
            SettingsPlacementPolicy.sheetIntersectsVerticalCrease(
                placement,
                input.verticalCreases[0],
                1000,
                false,
            ),
        )
    }

    @Test
    fun rtlSideSheetFitsLeadingPhysicalLeaf() {
        val input = input(1000, 800, vertical = listOf(WindowCrease(480, 20)), isRtl = true)
        val placement = SettingsPlacementPolicy.resolve(input, SettingsSheetKind.USER_MESSAGE_FULL_TEXT)
        assertEquals(SettingsPlacement(SettingsPlacementMode.SIDE, 480, 720, 0), placement)
        assertEquals(0, SettingsPlacementPolicy.sheetLeft(placement, 1000, isRtl = true))
    }

    @Test
    fun hoverUsesOperateRegionAndKindCap() {
        val input = input(
            width = 700,
            height = 900,
            hover = true,
            horizontal = listOf(HorizontalWindowCrease(420, 20)),
        )
        assertEquals(
            SettingsPlacement(SettingsPlacementMode.CENTER, 480, 560, 0),
            SettingsPlacementPolicy.resolve(input, SettingsSheetKind.SETTINGS),
        )
        assertEquals(
            SettingsPlacement(SettingsPlacementMode.FOLD_OPERATE, 0, 460, 460),
            SettingsPlacementPolicy.resolve(input, SettingsSheetKind.SESSION_DETAILS),
        )
    }

    @Test
    fun invalidCreaseFallsBackWithoutExceedingViewport() {
        val placement = SettingsPlacementPolicy.resolve(
            input(640, 900, vertical = listOf(WindowCrease(640, 20))),
            SettingsSheetKind.USER_MESSAGE_FULL_TEXT,
        )
        assertEquals(SettingsPlacement(SettingsPlacementMode.SIDE, 400, 760, 0), placement)
    }

    @Test
    fun foldedWindowUsesBottomEvenWhenWide() {
        val placement = SettingsPlacementPolicy.resolve(
            input(900, 900, folded = true),
            SettingsSheetKind.REMOTE_VIEW_SETTINGS,
        )
        assertEquals(SettingsPlacement(SettingsPlacementMode.BOTTOM, 0, 520, 0), placement)
    }

    @Test
    fun connectCentersAcrossAnExpandedFoldableAndUsesTheOperateRegionDuringHover() {
        val expanded = input(707, 773, vertical = listOf(WindowCrease(351, 5)))
        val hover = input(707, 773, hover = true, horizontal = listOf(HorizontalWindowCrease(351, 5)))
        val folded = expanded.copy(isFolded = true)
        val tablet = expanded.copy(isExpandedFoldable = false, verticalCreases = emptyList())
        val kind = SettingsSheetKind.CONNECT
        assertEquals(SettingsPlacement(SettingsPlacementMode.CENTER, 480, 560, 0), SettingsPlacementPolicy.resolve(expanded, kind))
        assertEquals(SettingsPlacement(SettingsPlacementMode.FOLD_OPERATE, 0, 417, 417), SettingsPlacementPolicy.resolve(hover, kind))
        assertEquals(SettingsPlacement(SettingsPlacementMode.BOTTOM, 0, 0, 0), SettingsPlacementPolicy.resolve(folded, kind))
        assertEquals(SettingsPlacement(SettingsPlacementMode.SIDE, 400, 693, 0), SettingsPlacementPolicy.resolve(tablet, kind))
    }

    private fun resolve(width: Int, height: Int): SettingsPlacement =
        SettingsPlacementPolicy.resolve(input(width, height), SettingsSheetKind.SETTINGS)

    private fun input(
        width: Int,
        height: Int,
        folded: Boolean = false,
        hover: Boolean = false,
        vertical: List<WindowCrease> = emptyList(),
        horizontal: List<HorizontalWindowCrease> = emptyList(),
        isRtl: Boolean = false,
    ): AdaptiveLayoutInput = AdaptiveLayoutInput(
        viewportWidth = width,
        viewportHeight = height,
        isFolded = folded,
        isExpandedFoldable = vertical.isNotEmpty() || horizontal.isNotEmpty(),
        isHoverOperate = hover,
        wideLayoutMatched = width >= ConversationLayoutPolicy.MD_MIN_WIDTH,
        verticalCreases = vertical,
        horizontalCreases = horizontal,
        isRtl = isRtl,
    )
}
