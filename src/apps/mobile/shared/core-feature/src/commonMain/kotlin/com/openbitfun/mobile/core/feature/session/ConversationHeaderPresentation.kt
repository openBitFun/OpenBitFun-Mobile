package com.openbitfun.mobile.core.feature.session

/**
 * The second line of a conversation header, ported from `headerContextTitle` in
 * `pages/components/RemoteChatHeader.ets`.
 *
 * It answers "where am I typing", which on a phone is not obvious: the same
 * session list can be reached through a paired desktop or through an account
 * device, and the answer is a device name in one case and a branch in the other.
 */
public object ConversationHeaderPresenter {
    /**
     * Not a localized string: it is the product's name, the same in every
     * locale, so it belongs here rather than in each app's string table.
     */
    private const val BRAND = "OpenBitFun"

    /**
     * The active workspace path is the primary context, matching the HarmonyOS
     * conversation header. Device and branch labels remain fallbacks for
     * sessions without a resolved workspace.
     */
    public fun contextTitle(desktopName: String, workspaceBranch: String): String =
        contextTitle(desktopName, workspaceBranch, "", "")

    public fun contextTitle(
        desktopName: String,
        workspaceBranch: String,
        workspacePath: String,
        workspaceName: String,
    ): String {
        val path = workspacePath.trim()
        if (path.isNotEmpty()) return path
        val name = workspaceName.trim()
        if (name.isNotEmpty()) return name
        val branch = workspaceBranch.trim()
        if (branch.isNotEmpty()) return "$BRAND · $branch"
        val desktop = desktopName.trim()
        return if (desktop.isNotEmpty()) desktop else BRAND
    }
}
