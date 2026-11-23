package com.openbitfun.mobile.core.feature.account

/**
 * Which of an account's registered devices can be driven from this one.
 *
 * The transport filters device kinds before projecting the account directory.
 * Membership, presence and Relay compatibility still govern device selection.
 */
public object AccountDevicePolicy {
    /**
     * Names our own mobile clients register under.
     *
     * A phone is never a control target — it is the thing doing the
     * controlling — and the current device is excluded separately by id, so this
     * set is about the user's *other* phones.
     */
    private val MOBILE_CLIENT_NAMES: Set<String> = setOf("HarmonyOS Phone")

    /**
     * The rows a device list shows: everything the account has registered except
     * this device and the user's other phones.
     *
     * Offline devices stay in the list. They are what tells a user the desktop
     * they are looking for is known to the account and simply not running, which
     * is a different problem from it never having been paired.
     */
    public fun controlTargets(
        devices: List<AccountDeviceUi>,
        currentDeviceId: String,
    ): List<AccountDeviceUi> = devices.filter { isTarget(it, currentDeviceId) }

    /** Whether tapping [device] can do anything. */
    public fun canSelect(device: AccountDeviceUi, currentDeviceId: String): Boolean =
        device.online && device.controllable && isTarget(device, currentDeviceId)

    /**
     * The device to drive when the user has not picked one — after a fresh sign
     * in, where a list of one online desktop should not need a second tap.
     *
     * Null when nothing is online, rather than the first offline row: a target
     * that cannot answer is worse than no target, because the session list would
     * then fail against it instead of saying there is nowhere to look.
     */
    public fun preferredTarget(
        devices: List<AccountDeviceUi>,
        currentDeviceId: String,
    ): AccountDeviceUi? = devices.firstOrNull { canSelect(it, currentDeviceId) }

    private fun isTarget(device: AccountDeviceUi, currentDeviceId: String): Boolean =
        device.id != currentDeviceId && device.name !in MOBILE_CLIENT_NAMES
}
