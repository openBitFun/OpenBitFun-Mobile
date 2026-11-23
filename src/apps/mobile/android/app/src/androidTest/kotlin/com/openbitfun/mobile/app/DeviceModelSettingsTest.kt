package com.openbitfun.mobile.app

import android.content.res.Configuration
import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.openbitfun.mobile.app.ui.settings.SettingsScreen
import com.openbitfun.mobile.app.platform.rememberWindowMetrics
import com.openbitfun.mobile.app.ui.theme.OpenBitFunTheme
import com.openbitfun.mobile.core.feature.account.AccountDeviceUi
import com.openbitfun.mobile.core.feature.account.AccountUiState
import com.openbitfun.mobile.core.feature.connection.ConnectionPhase
import com.openbitfun.mobile.core.feature.connection.RemoteControlPresenter
import com.openbitfun.mobile.core.feature.layout.AdaptiveLayoutInput
import com.openbitfun.mobile.core.feature.layout.SettingsPlacementPolicy
import com.openbitfun.mobile.core.feature.layout.SettingsSheetKind
import com.openbitfun.mobile.core.feature.session.*
import java.io.File
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DeviceModelSettingsTest {
    @get:Rule val rule = createComposeRule()

    @Test fun connectedDeviceOwnsTheRolePickerAndShowsTheConfirmedValue() {
        val desktopId = "account-desktop-1"
        val desktopName = "Account desktop 1"
        val settingsWidth = mutableStateOf<Int?>(null)
        val models = mutableStateOf(DeviceModelDefaultsUiState(DeviceModelAvailability.UNSUPPORTED))
        val calls = mutableListOf<Pair<String, RemoteSessionIntent>>()
        val primary = DeviceModelChoiceUi("sonnet", "claude-sonnet-4-5", "anthropic · 200k")
        val fast = DeviceModelChoiceUi("mini", "gpt-5-mini", "openai · 128k")
        val gemini = DeviceModelChoiceUi("gemini", "gemini-2.5-flash", "google · 1000k")
        val vision = DeviceModelChoiceUi("vision", "vision-preview", "openbitfun · 64k")
        val roles = listOf(
            DeviceModelRoleUi(DeviceModelRole.PRIMARY, primary, true, listOf(primary, fast, gemini)),
            DeviceModelRoleUi(DeviceModelRole.FAST, null, true, listOf(primary, fast, gemini)),
            DeviceModelRoleUi(DeviceModelRole.IMAGE_UNDERSTANDING, null, false, listOf(gemini, vision)),
        )

        rule.setContent {
            val context = LocalContext.current
            val currentConfig = LocalConfiguration.current
            val config = remember(currentConfig) { Configuration(currentConfig).apply { setLocale(Locale.SIMPLIFIED_CHINESE) } }
            val localizedContext = remember(context, config) { context.createConfigurationContext(config) }
            CompositionLocalProvider(LocalConfiguration provides config, LocalContext provides localizedContext) {
                OpenBitFunTheme(dark = false) {
                    val window = rememberWindowMetrics()
                    val placement = SettingsPlacementPolicy.resolve(AdaptiveLayoutInput(
                        viewportWidth = settingsWidth.value ?: window.widthDp, viewportHeight = window.heightDp,
                        isFolded = window.isFolded, isExpandedFoldable = window.isExpandedFoldable,
                        isHoverOperate = window.isHoverLayout, wideLayoutMatched = window.wideViewportMatched,
                        verticalCreases = window.creases, horizontalCreases = window.horizontalCreases, isRtl = false,
                    ), SettingsSheetKind.SETTINGS)
                    SettingsScreen(
                        visible = true,
                        placement = placement,
                        account = AccountUiState.Ready(
                            userId = "fixture", username = "octocat", devices = listOf(
                                AccountDeviceUi(desktopId, desktopName, online = true, lastSeenAt = null),
                                AccountDeviceUi("other", "Other desktop", online = true, lastSeenAt = null),
                            ), selectedDeviceId = desktopId, selectedDeviceName = desktopName,
                        ),
                        summary = RemoteControlPresenter.summarize(desktopId, desktopName, ConnectionPhase.CONNECTED),
                        remoteState = RemoteSessionUiState.Idle,
                        onSignIn = {}, onRefreshDevices = {}, onSelectDevice = {}, onSignOut = {},
                        onDisconnect = {}, onReconnect = {}, onSessionIntent = {}, onClose = {},
                        deviceModels = models.value,
                        onDeviceModelsIntent = { id, intent ->
                            calls += id to intent
                            when (intent) {
                                RemoteSessionIntent.OpenDeviceModelDefaults ->
                                    models.value = DeviceModelDefaultsUiState(DeviceModelAvailability.AVAILABLE, DeviceModelOperation.READY, roles,
                                        activeRole = null, hasModels = true)
                                is RemoteSessionIntent.SelectDeviceModelDefault ->
                                    models.value = models.value.copy(operation = DeviceModelOperation.SAVING, activeRole = intent.role)
                                else -> Unit
                            }
                        },
                    )
                }
            }
        }
        val entry = rule.onNodeWithTag("device-model-settings")
        rule.onAllNodesWithTag("device-model-settings").assertCountEquals(1)
        entry.performScrollTo().performClick()
        rule.waitUntil(5_000) {
            rule.onAllNodesWithText("该设备上的 OpenBitFun 版本过旧", substring = true)
                .fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithText("该设备上的 OpenBitFun 版本过旧", substring = true).assertExists()
        rule.runOnIdle { assertTrue(calls.isEmpty()) }

        rule.runOnIdle { models.value = DeviceModelDefaultsUiState(DeviceModelAvailability.AVAILABLE) }
        entry.performClick()
        rule.onNodeWithText("主力模型").assertExists()
        capture("device-model-settings.png")
        rule.onNodeWithText("多模态模型").performClick()
        rule.onNodeWithText("vision-preview", substring = true).assertExists()
        rule.onNodeWithText("gpt-5-mini", substring = true).assertDoesNotExist()
        capture("device-model-multimodal.png")

        rule.runOnIdle { settingsWidth.value = 707 }
        rule.onNodeWithTag("settings-centered-panel").assertIsDisplayed()
        rule.onNodeWithText("vision-preview", substring = true).assertExists()
        rule.runOnIdle { settingsWidth.value = 360 }
        rule.onNodeWithTag("settings-centered-panel").assertDoesNotExist()
        rule.onNodeWithText("vision-preview", substring = true).assertExists()
        rule.runOnIdle {
            assertEquals(listOf(desktopId to RemoteSessionIntent.OpenDeviceModelDefaults), calls)
            settingsWidth.value = null
        }
        rule.onNodeWithText("vision-preview", substring = true).performClick()
        rule.onNodeWithText("正在保存模型默认值").assertExists()
        rule.onNodeWithText("vision-preview", substring = true).assertDoesNotExist()
        rule.runOnIdle {
            assertEquals(desktopId to RemoteSessionIntent.SelectDeviceModelDefault(DeviceModelRole.IMAGE_UNDERSTANDING, "vision"),
                calls.last())
            models.value = models.value.copy(
                operation = DeviceModelOperation.SAVED,
                roles = roles.map { if (it.role == DeviceModelRole.IMAGE_UNDERSTANDING) it.copy(selected = vision, resolved = true) else it },
            )
        }
        rule.onNodeWithText("已更新").assertExists()
        rule.onNode(hasText("多模态模型") and hasText("vision-preview", substring = true)).assertExists()
    }

    private fun capture(name: String) {
        rule.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        File(instrumentation.targetContext.getExternalFilesDir(null), name).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
