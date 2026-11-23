package com.openbitfun.mobile.app

import android.content.res.Configuration
import android.graphics.Bitmap
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import com.openbitfun.mobile.core.feature.session.RemoteSessionIntent
import com.openbitfun.mobile.core.feature.session.RemoteSessionFailureReason
import com.openbitfun.mobile.app.ui.chat.CONVERSATION_LOADING_TEST_TAG
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.openbitfun.mobile.app.platform.rememberWindowMetrics
import com.openbitfun.mobile.app.ui.common.AdaptiveModalSurface
import com.openbitfun.mobile.app.ui.remote.CONNECT_ACCOUNT_DEVICE_REFRESH_TEST_TAG
import com.openbitfun.mobile.app.ui.remote.CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX
import com.openbitfun.mobile.app.ui.remote.ConnectAccountDeviceScreen
import com.openbitfun.mobile.app.ui.remote.AccountRemoteScreen
import com.openbitfun.mobile.app.ui.theme.OpenBitFunTheme
import com.openbitfun.mobile.core.feature.account.AccountDeviceUi
import com.openbitfun.mobile.core.feature.account.AccountUiState
import com.openbitfun.mobile.core.feature.connection.ConnectionPhase
import com.openbitfun.mobile.core.feature.layout.AdaptiveLayoutInput
import com.openbitfun.mobile.core.feature.layout.SettingsPlacement
import com.openbitfun.mobile.core.feature.layout.SettingsPlacementMode
import com.openbitfun.mobile.core.feature.layout.SettingsPlacementPolicy
import com.openbitfun.mobile.core.feature.layout.SettingsSheetKind
import com.openbitfun.mobile.core.feature.session.RemoteSessionUiState
import com.openbitfun.mobile.core.feature.workspace.RemoteWorkspaceUiState
import java.io.File
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals

class AccountRemoteScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun accountPickerKeepsAllDeviceRowsInOneScrollSurface() {
        val account = AccountUiState.Ready(
            userId = "fixture", username = "octocat",
            devices = (1..9).map { index ->
                AccountDeviceUi("account-desktop-$index", "Account desktop $index", index % 3 != 0, index.toLong())
            },
            selectedDeviceId = "account-desktop-1", selectedDeviceName = "Account desktop 1",
        )
        val switching = mutableStateOf<String?>(null)
        val failed = mutableStateOf(false)
        val directory = mutableStateOf(account)
        composeRule.setContent {
            val context = LocalContext.current
            val configuration = LocalConfiguration.current
            val chinese = remember(configuration) {
                Configuration(configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) }
            }
            val localized = remember(context, chinese) { context.createConfigurationContext(chinese) }
            CompositionLocalProvider(LocalConfiguration provides chinese, LocalContext provides localized) {
                OpenBitFunTheme(dark = false) {
                    val window = rememberWindowMetrics()
                    val expanded = window.widthDp >= 600
                    val placement = SettingsPlacementPolicy.resolve(AdaptiveLayoutInput(
                        viewportWidth = window.widthDp, viewportHeight = window.heightDp,
                        isFolded = !expanded, isExpandedFoldable = expanded, isHoverOperate = false,
                        wideLayoutMatched = expanded, verticalCreases = emptyList(),
                        horizontalCreases = emptyList(), isRtl = false,
                    ), SettingsSheetKind.CONNECT)
                    AdaptiveModalSurface(
                        visible = true, placement = placement, onDismissRequest = {},
                        edgeToEdgeContent = true, connectChrome = true,
                    ) { modifier ->
                        ConnectAccountDeviceScreen(
                            state = directory.value, onBack = {}, onRefresh = { failed.value = false },
                            onSelect = { switching.value = it }, modifier = modifier, connected = true,
                            switchingDeviceId = switching.value, connectionFailed = failed.value,
                        )
                    }
                }
            }
        }
        val title = composeRule.onAllNodesWithText("选择桌面设备")
        composeRule.waitUntil(5_000) {
            composeRule.onAllNodesWithText("选择桌面设备").fetchSemanticsNodes().isNotEmpty()
        }
        title.assertCountEquals(1)[0].assertIsDisplayed()
        val instrument = InstrumentationRegistry.getInstrumentation()
        instrument.uiAutomation.waitForIdle(400, 4000)
        val bitmap = instrument.uiAutomation.takeScreenshot()
        val suffix = if (bitmap.width > 1800) "expanded" else "compact"
        if (suffix == "expanded") {
            composeRule.onNodeWithTag("connect-centered-panel")
                .assertWidthIsEqualTo(480.dp).assertHeightIsEqualTo(560.dp)
        }
        File(instrument.targetContext.getExternalFilesDir(null), "connect-account-$suffix.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
        fun row(index: Int) = composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX + "account-desktop-$index")
        composeRule.runOnIdle {
            directory.value = account.copy(devices = account.devices.map {
                if (it.id == "account-desktop-5") it.copy(compatible = false) else it
            })
        }
        row(5).performScrollTo().assertIsNotEnabled()
        composeRule.onNodeWithText("客户端版本不兼容，无法互控。").assertIsDisplayed()
        val blocked = instrument.uiAutomation.takeScreenshot()
        File(instrument.targetContext.getExternalFilesDir(null), "connect-incompatible-$suffix.png").outputStream().use {
            blocked.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        blocked.recycle()
        row(9).performScrollTo().assertIsDisplayed()
        title.assertCountEquals(1)[0].assertIsDisplayed()
        row(3).performScrollTo().assertIsNotEnabled()
        row(2).performScrollTo().performClick()
        composeRule.onAllNodesWithText("正在连接").assertCountEquals(1)
        row(1).assertIsNotEnabled()
        composeRule.runOnIdle {
            switching.value = null
            failed.value = true
        }
        composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_REFRESH_TEST_TAG).performScrollTo()
        composeRule.onNodeWithText("重试").assertIsDisplayed()
        row(2).assertIsDisplayed()
    }

    @Test
    fun aSelectedAccountDeviceBypassesThePairingForm() {
        composeRule.setContent {
            OpenBitFunTheme(dark = false) {
                AccountRemoteScreen(
                    remoteState = RemoteSessionUiState.Idle,
                    workspaceState = RemoteWorkspaceUiState.Idle,
                    deviceId = "device-1",
                    deviceName = "Studio Mac",
                    createDevices = emptyList(),
                    accountUsername = "tester",
                    phase = ConnectionPhase.CONNECTED,
                    settingsPlacement = SettingsPlacement(
                        mode = SettingsPlacementMode.BOTTOM,
                        width = 0,
                        height = 0,
                        maxHeight = 0,
                    ),
                    sessionDetailsPlacement = SettingsPlacement(
                        mode = SettingsPlacementMode.BOTTOM,
                        width = 0,
                        height = 0,
                        maxHeight = 0,
                    ),
                    viewSettingsPlacement = SettingsPlacement(
                        mode = SettingsPlacementMode.BOTTOM,
                        width = 0,
                        height = 0,
                        maxHeight = 0,
                    ),
                    onOpenRemoteSettings = {},
                    onCreateDevicePick = {},
                    onSessionIntent = {},
                    onWorkspaceIntent = {},
                    modifier = Modifier,
                )
            }
        }

        composeRule.onAllNodesWithText(testString(R.string.pairing_title)).assertCountEquals(0)
    }

    @Test
    fun aRequestedSessionRoutesImmediatelyAndCanRetryALoadFailure() {
        val state = mutableStateOf<RemoteSessionUiState>(RemoteSessionUiState.Idle)
        val intents = mutableListOf<RemoteSessionIntent>()
        var wentBack = false
        composeRule.setContent {
            OpenBitFunTheme(dark = false) {
                val placement = SettingsPlacement(SettingsPlacementMode.BOTTOM, 0, 0, 0)
                AccountRemoteScreen(
                    remoteState = state.value, workspaceState = RemoteWorkspaceUiState.Idle,
                    deviceId = "device-1", deviceName = "Studio Mac", createDevices = emptyList(),
                    accountUsername = "tester", phase = ConnectionPhase.RECONNECTING,
                    settingsPlacement = placement, sessionDetailsPlacement = placement,
                    viewSettingsPlacement = placement, onOpenRemoteSettings = {}, onCreateDevicePick = {},
                    onSessionIntent = { intents += it }, onWorkspaceIntent = {},
                    requestedSessionId = "requested", onRemoteHome = { wentBack = true },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        composeRule.mainClock.advanceTimeBy(200)
        composeRule.onNodeWithTag(CONVERSATION_LOADING_TEST_TAG).assertIsDisplayed()
        composeRule.onNodeWithText(testString(R.string.home_recent_title)).assertDoesNotExist()
        composeRule.runOnIdle { state.value = RemoteSessionUiState.Failed(RemoteSessionFailureReason.TRANSPORT) }
        composeRule.onNodeWithTag(CONVERSATION_LOADING_TEST_TAG).assertDoesNotExist()
        composeRule.onNodeWithText(testString(R.string.sessions_failed)).assertIsDisplayed()
        composeRule.onNodeWithText(testString(R.string.sessions_retry)).performClick()
        assertEquals(listOf(RemoteSessionIntent.Open("requested")), intents)
        composeRule.onNodeWithText(testString(R.string.conversation_back)).performClick()
        assertEquals(true, wentBack)
    }

    @Test
    fun aSignedInAccountWithoutATargetCanRefreshOrSelect() {
        var refreshes = 0
        var selected = ""
        composeRule.setContent {
            OpenBitFunTheme(dark = false) {
                ConnectAccountDeviceScreen(
                    state = AccountUiState.Ready(
                        userId = "user-1",
                        username = "tester",
                        devices = listOf(
                            AccountDeviceUi("desk-1", "Studio Mac", online = true, lastSeenAt = null),
                            AccountDeviceUi("desk-2", "Office PC", online = false, lastSeenAt = null),
                        ),
                        selectedDeviceId = null,
                        selectedDeviceName = null,
                    ),
                    onBack = {},
                    onRefresh = { refreshes += 1 },
                    onSelect = { selected = it },
                    modifier = Modifier,
                )
            }
        }

        composeRule.onNodeWithText(testString(R.string.connect_account_devices_title)).assertIsDisplayed()
        composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_REFRESH_TEST_TAG).performClick()
        composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX + "desk-1").performClick()
        composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX + "desk-2").assertIsNotEnabled()

        assertEquals(1, refreshes)
        assertEquals("desk-1", selected)
    }

    @Test
    fun thePreviousOfflineDeviceRemainsVisibleAndCannotBeSelectedFromThePicker() {
        var selected = ""
        composeRule.setContent {
            OpenBitFunTheme(dark = false) {
                ConnectAccountDeviceScreen(
                    state = AccountUiState.Ready(
                        userId = "user-1",
                        username = "tester",
                        devices = listOf(
                            AccountDeviceUi("desk-1", "Studio Mac", online = true, lastSeenAt = null),
                            AccountDeviceUi("desk-2", "Office PC", online = false, lastSeenAt = null),
                        ),
                        selectedDeviceId = "desk-2",
                        selectedDeviceName = "Office PC",
                    ),
                    onBack = {},
                    onRefresh = {},
                    onSelect = { selected = it },
                    modifier = Modifier,
                )
            }
        }

        composeRule.onNodeWithTag(CONNECT_ACCOUNT_DEVICE_ROW_TEST_TAG_PREFIX + "desk-2").assertIsNotEnabled()
        composeRule.onNodeWithText(testString(R.string.account_offline), substring = true).assertIsDisplayed()

        assertEquals("", selected)
    }
}
