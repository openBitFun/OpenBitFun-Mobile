package com.openbitfun.mobile.core.feature.session

import kotlin.test.Test
import kotlin.test.assertEquals

class ConversationHeaderPresentationTest {
    @Test
    fun aResolvedWorkspacePathIsTheAnswerBeforeTheDesktopName() {
        assertEquals(
            "/workspace/OpenBitFun",
            ConversationHeaderPresenter.contextTitle(
                desktopName = "Studio",
                workspaceBranch = "main",
                workspacePath = "/workspace/OpenBitFun",
                workspaceName = "OpenBitFun",
            ),
        )
    }

    @Test
    fun withoutADesktopTheBranchIsShownBesideTheBrand() {
        assertEquals(
            "OpenBitFun · feat/chat",
            ConversationHeaderPresenter.contextTitle(desktopName = "", workspaceBranch = "feat/chat"),
        )
    }

    @Test
    fun aWorkspaceNameIsUsedWhenItsPathIsMissing() {
        assertEquals(
            "OpenBitFun",
            ConversationHeaderPresenter.contextTitle(
                desktopName = "Studio",
                workspaceBranch = "main",
                workspacePath = "",
                workspaceName = "OpenBitFun",
            ),
        )
    }

    @Test
    fun blankIsNotAName() {
        assertEquals(
            "OpenBitFun",
            ConversationHeaderPresenter.contextTitle(desktopName = "  ", workspaceBranch = "\n"),
        )
    }
}
