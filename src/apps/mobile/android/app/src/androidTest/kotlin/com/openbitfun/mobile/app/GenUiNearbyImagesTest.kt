package com.openbitfun.mobile.app

import android.Manifest
import android.app.Application
import android.app.Instrumentation
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.SystemClock
import android.provider.MediaStore
import android.view.InputDevice
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewModelScope
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.openbitfun.mobile.app.ui.genui.LocalGenUiDialog
import com.openbitfun.mobile.app.ui.genui.LocalGenUiModel
import com.openbitfun.mobile.app.ui.genui.LocalGenUiNearbyImages
import com.openbitfun.mobile.app.ui.genui.LocalGenUiSendImage
import com.openbitfun.mobile.app.ui.genui.localImageAddress
import com.openbitfun.mobile.app.ui.theme.OpenBitFunTheme
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaboration
import com.openbitfun.mobile.core.feature.genui.LocalGenUiIntent
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.json.JSONObject

@SdkSuppress(minSdkVersion = 37)
class GenUiNearbyImagesTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun senderPublishesAnIpv4EndpointWhileOnScreen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue(ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED)
        val showing = mutableStateOf(true)
        compose.setContent {
            OpenBitFunTheme(dark = false) {
                if (showing.value) LocalGenUiSendImage { showing.value = false }
            }
        }
        val discovery = LocalGenUiNearbyImages(context)
        val peer = runBlocking {
            withTimeout(20_000) {
                val devices = discovery.browse().first { it.isNotEmpty() }
                checkNotNull(discovery.resolve(devices.first()))
            }
        }
        assertEquals(context.localImageAddress(), peer.address)
        assertTrue(peer.port in 1024..65535)
        compose.runOnIdle { showing.value = false }
    }

    @Test
    fun sendGalleryImageToNearbySimulator() {
        sendImageToNearbySimulator(useCamera = false)
    }

    @Test
    fun sendCameraImageToNearbySimulator() {
        sendImageToNearbySimulator(useCamera = true, useScan = false)
    }

    @Test
    fun sendScanImageToNearbySimulator() {
        sendImageToNearbySimulator(useCamera = false, useScan = true)
    }

    private fun sendImageToNearbySimulator(useCamera: Boolean, useScan: Boolean = false) {
        val instrument = InstrumentationRegistry.getInstrumentation()
        assumeTrue(InstrumentationRegistry.getArguments().getString("genuiNearbyBridge") == "true")
        val context = instrument.targetContext
        assertEquals(PackageManager.PERMISSION_GRANTED,
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_LOCAL_NETWORK))
        if (useCamera || useScan) {
            instrument.uiAutomation.adoptShellPermissionIdentity("android.permission.GRANT_RUNTIME_PERMISSIONS")
            try {
                instrument.uiAutomation.executeShellCommand("pm grant ${context.packageName} ${Manifest.permission.CAMERA}").close()
            } finally {
                instrument.uiAutomation.dropShellPermissionIdentity()
            }
        }
        val media = context.contentResolver
        val uri = checkNotNull(media.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "OpenBitFun Nearby QA.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/OpenBitFun Nearby QA")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }))
        val destination = checkNotNull(context.getExternalFilesDir(null))
        val endpoint = File(destination, "genui-nearby-endpoint.txt")
        endpoint.delete()
        try {
            val bitmap = Bitmap.createBitmap(480, 300, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).apply {
                drawColor(Color.rgb(232, 243, 248))
                val brush = Paint(Paint.ANTI_ALIAS_FLAG)
                brush.color = Color.rgb(35, 132, 137)
                drawCircle(152f, 150f, 88f, brush)
                brush.color = Color.rgb(230, 145, 59)
                drawRect(260f, 72f, 416f, 228f, brush)
            }
            checkNotNull(media.openOutputStream(uri)).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            media.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)

            compose.setContent { OpenBitFunTheme(dark = false) { LocalGenUiSendImage {} } }
            val discovery = LocalGenUiNearbyImages(context)
            val peer = runBlocking {
                withTimeout(20_000) {
                    val devices = discovery.browse().first { it.isNotEmpty() }
                    checkNotNull(discovery.resolve(devices.first()))
                }
            }
            endpoint.writeText("${peer.address} ${peer.port}\n")

            val approve = context.getString(R.string.genui_nearby_confirm)
            compose.waitUntil(timeoutMillis = 90_000) {
                compose.onAllNodes(hasText(approve)).fetchSemanticsNodes().isNotEmpty()
            }
            screenshot(destination, "genui-nearby-confirmation.png")
            compose.onNodeWithText(approve).performClick()
            val gallery = context.getString(when {
                useCamera -> R.string.genui_image_take_photo
                useScan -> R.string.genui_image_scan_document
                else -> R.string.genui_image_gallery
            })
            compose.waitUntil(timeoutMillis = 12_000) {
                compose.onAllNodes(hasText(gallery)).fetchSemanticsNodes().isNotEmpty() &&
                    runCatching { compose.onNodeWithTag("genui-image-source").fetchSemanticsNode(); true }.getOrDefault(false)
            }
            compose.onNodeWithTag("genui-image-source").performClick()

            fun pickControl(vararg names: String) {
                var control: AccessibilityNodeInfo? = null
                compose.waitUntil(timeoutMillis = 12_000) {
                    control = instrument.uiAutomation.rootInActiveWindow?.findLabel(names.toSet())
                    control != null
                }
                assertTrue(checkNotNull(control).click())
            }
            if (useCamera || useScan) {
                if (useScan) {
                    var cancelScanner: AccessibilityNodeInfo? = null
                    compose.waitUntil(timeoutMillis = 5_000) {
                        cancelScanner = instrument.uiAutomation.rootInActiveWindow?.findLabel(setOf("Cancel", "取消"))
                        cancelScanner != null || instrument.uiAutomation.rootInActiveWindow?.packageName?.toString() == "com.android.camera2"
                    }
                    cancelScanner?.let { assertTrue(it.click()) }
                }
                compose.waitUntil(timeoutMillis = 15_000) {
                    instrument.uiAutomation.rootInActiveWindow?.packageName?.toString() == "com.android.camera2"
                }
                pickControl("Shutter")
                compose.waitUntil(timeoutMillis = 15_000) {
                    instrument.uiAutomation.rootInActiveWindow?.findLabel(setOf("Done", "完成")) != null
                }
                pickControl("Done", "完成")
            } else {
                pickControl("Collections", "合集", "相册")
                pickControl("From this device", "来自此设备")
                pickControl("OpenBitFun Nearby QA")
                var photo: AccessibilityNodeInfo? = null
                compose.waitUntil(timeoutMillis = 15_000) {
                    photo = instrument.uiAutomation.rootInActiveWindow?.firstPhoto()
                    photo != null
                }
                assertTrue(checkNotNull(photo).click())
            }
            val send = context.getString(R.string.genui_image_confirm_send)
            var doneTapped = false
            compose.waitUntil(timeoutMillis = 12_000) {
                val picker = instrument.uiAutomation.rootInActiveWindow
                if (!doneTapped && picker?.packageName != context.packageName) {
                    doneTapped = picker?.findLabel(setOf("Done", "完成"))?.click() == true
                }
                compose.onAllNodes(hasText(send)).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty()
            }
            compose.onNodeWithText(send).performClick()
            val sent = context.getString(R.string.genui_image_sent)
            compose.waitUntil(timeoutMillis = 15_000) {
                compose.onAllNodes(hasText(sent)).fetchSemanticsNodes().isNotEmpty()
            }
            screenshot(destination, "genui-nearby-delivered.png")
        } finally {
            endpoint.delete()
            media.delete(uri, null, null)
        }
    }

    @Test
    fun receiveGalleryImageFromNearbySimulator() {
        val arguments = InstrumentationRegistry.getArguments()
        val peerName = arguments.getString("genuiNearbyIosSender").orEmpty()
        assumeTrue(peerName.isNotEmpty())
        val bridgePort = arguments.getString("genuiNearbyReversePort")?.toInt()
        require(bridgePort == null || bridgePort in 1024..65535)

        val instrument = InstrumentationRegistry.getInstrumentation()
        val context = instrument.targetContext
        assertEquals(PackageManager.PERMISSION_GRANTED,
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_LOCAL_NETWORK))
        val destination = checkNotNull(context.getExternalFilesDir(null))
        val model = LocalGenUiModel(context.applicationContext as Application)
        val showing = mutableStateOf(true)
        val fixtureEndpoint = "http://127.0.0.1:39172"
        val fixtureModel = "parity-fixture"

        try {
            compose.setContent { OpenBitFunTheme(dark = false) { if (showing.value) LocalGenUiDialog(model = model) {} } }
            compose.waitUntil(10_000) { !model.store.state.value.loading }
            compose.onNodeWithTag("local-genui-new-session").performClick()
            compose.waitUntil(10_000) { model.store.state.value.selectedSession != null }
            val profile = model.store.state.value.models.firstOrNull {
                it.endpoint == fixtureEndpoint && it.model == fixtureModel && it.hasStoredKey
            }
            model.store.dispatch(if (profile == null) {
                LocalGenUiIntent.SaveModel(null, "Nearby QA", fixtureEndpoint, fixtureModel, "local-test-key", true)
            } else LocalGenUiIntent.SelectModel(profile.id))
            compose.waitUntil(10_000) {
                val state = model.store.state.value
                state.models.any { it.id == state.selectedModelId && it.endpoint == fixtureEndpoint && it.model == fixtureModel }
            }

            val prompt = "DeviceImageParityFixture"
            compose.onNodeWithTag("local-genui-composer").performTextReplacement(prompt)
            compose.waitUntil(10_000) { model.store.state.value.draft == prompt }
            val accepted = model.store.state.value.draftAcceptedSerial
            compose.onNodeWithContentDescription(context.getString(R.string.genui_send)).performClick()
            compose.waitUntil(10_000) { model.store.state.value.draftAcceptedSerial > accepted }
            compose.waitUntil(35_000) {
                val state = model.store.state.value
                state.failure != null || state.openApp?.let { !it.checking && !it.streaming } == true
            }
            assertEquals(null, model.store.state.value.failure)
            val choice = setOf("选择其他设备的图片")
            compose.waitUntil(10_000) { instrument.uiAutomation.rootInActiveWindow?.findLabel(choice) != null }

            bridgePort?.let { IosSimulatorRelay(context, peerName, it) }.use {
                // Wait for the WebView entrance animation and checking-to-live layout change.
                instrument.uiAutomation.waitForIdle(1_200, 8_000)
                val receive = context.getString(R.string.genui_image_receive)
                fun tapGalleryChoice() {
                    val button = checkNotNull(instrument.uiAutomation.rootInActiveWindow?.findLabel(choice))
                    instrument.tap(button)
                }
                tapGalleryChoice()
                try {
                    compose.waitUntil(2_500) { compose.onAllNodes(hasText(receive)).fetchSemanticsNodes().isNotEmpty() }
                } catch (_: ComposeTimeoutException) {
                    tapGalleryChoice()
                }
                compose.waitUntil(10_000) { compose.onAllNodes(hasText(receive)).fetchSemanticsNodes().isNotEmpty() }
                compose.waitUntil(20_000) { compose.onAllNodes(hasText(peerName)).fetchSemanticsNodes().isNotEmpty() }
                compose.onNodeWithText(peerName).performClick()
                val approve = context.getString(R.string.genui_nearby_confirm)
                compose.waitUntil(12_000) { compose.onAllNodes(hasText(approve)).fetchSemanticsNodes().isNotEmpty() }
                screenshot(destination, "genui-nearby-reverse-confirmation.png")
                compose.onNodeWithText(approve).performClick()

                compose.waitUntil(65_000) { (model.store.state.value.openApp?.stateRevision ?: 0) > 0 }
            }
            val received = checkNotNull(model.store.state.value.openApp)
            val asset = Uri.parse(JSONObject(received.stateJson).getString("imported"))
            assertEquals("genui-assets.openbitfun.invalid", asset.host)
            val image = runBlocking { model.media.readCollaboration(checkNotNull(asset.encodedPath), received.id) }
            assertEquals("image/jpeg", image?.mimeType)
            val jpeg = checkNotNull(image).bytes
            val bitmap = checkNotNull(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
            bitmap.recycle()

            val photo = setOf("Image received from another device", "从其他设备接收的图片")
            compose.waitUntil(10_000) { instrument.uiAutomation.rootInActiveWindow?.findLabel(photo) != null }
            compose.onNodeWithContentDescription(context.getString(R.string.miniapps_back)).performClick()
            compose.onNodeWithTag("local-genui-app-card").performClick()
            compose.waitUntil(10_000) { instrument.uiAutomation.rootInActiveWindow?.findLabel(photo) != null }
            assertEquals(received.stateJson, model.store.state.value.openApp?.stateJson)
            instrument.uiAutomation.waitForIdle(1_200, 8_000)
            screenshot(destination, "genui-nearby-reverse-reopened.png")
        } catch (error: Throwable) {
            runCatching { screenshot(destination, "genui-nearby-reverse-failure.png") }
            throw error
        } finally {
            compose.runOnIdle { showing.value = false }
            model.viewModelScope.cancel()
            model.media.close()
        }
    }

    private fun screenshot(directory: File, name: String) {
        val screenshot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(directory, name).outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        screenshot.recycle()
    }

    private fun AccessibilityNodeInfo.firstPhoto(): AccessibilityNodeInfo? {
        val bounds = Rect().also(::getBoundsInScreen)
        val description = contentDescription?.toString().orEmpty()
        val thumbnail = viewIdResourceName?.endsWith(":id/icon_thumbnail") == true
        if (isVisibleToUser && bounds.width() > 80 && bounds.height() > 80 &&
            (thumbnail || description.contains("Photo taken", ignoreCase = true) || description.contains("拍摄的照片"))
        ) return this
        for (index in 0 until childCount) {
            getChild(index)?.firstPhoto()?.let { return it }
        }
        return null
    }

    private fun AccessibilityNodeInfo.findLabel(labels: Set<String>): AccessibilityNodeInfo? {
        if (isVisibleToUser && (text?.toString() in labels || contentDescription?.toString() in labels)) return this
        for (index in 0 until childCount) {
            getChild(index)?.findLabel(labels)?.let { return it }
        }
        return null
    }

    private fun AccessibilityNodeInfo.click(): Boolean =
        generateSequence(this) { it.parent }.firstOrNull { it.isClickable }
            ?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true

    private fun Instrumentation.tap(node: AccessibilityNodeInfo) {
        val bounds = Rect().also(node::getBoundsInScreen)
        val start = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(start, SystemClock.uptimeMillis(), action,
                bounds.exactCenterX(), bounds.exactCenterY(), 0)
            try {
                event.source = InputDevice.SOURCE_TOUCHSCREEN
                assertTrue(uiAutomation.injectInputEvent(event, true))
            } finally {
                event.recycle()
            }
        }
    }
}

// Mirror one encrypted connection through adb reverse on isolated emulators.
private class IosSimulatorRelay(context: Context, name: String, reversePort: Int) : AutoCloseable {
    private val address = checkNotNull(context.localImageAddress())
    private val nsd = checkNotNull(context.getSystemService(NsdManager::class.java))
    private val server = ServerSocket(0, 1, InetAddress.getByName(address)).apply { soTimeout = 40_000 }
    private val ready = CompletableDeferred<Unit>()
    private val registration = object : NsdManager.RegistrationListener {
        override fun onServiceRegistered(info: NsdServiceInfo) { ready.complete(Unit) }
        override fun onRegistrationFailed(info: NsdServiceInfo, error: Int) {
            ready.completeExceptionally(IllegalStateException("Simulator NSD registration failed ($error)"))
        }
        override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
        override fun onUnregistrationFailed(info: NsdServiceInfo, error: Int) = Unit
    }
    private val sender = Socket()
    @Volatile private var receiver: Socket? = null

    init {
        try {
            nsd.registerService(NsdServiceInfo().apply {
                serviceName = name
                serviceType = "${LocalGenUiCollaboration.NEARBY_SERVICE_TYPE}."
                port = server.localPort
                setAttribute("ip", address)
                setAttribute("port", port.toString())
            }, NsdManager.PROTOCOL_DNS_SD, registration)
            runBlocking { withTimeout(12_000) { ready.await() } }
            thread(name = "genui-ios-simulator-relay", isDaemon = true) {
                runCatching {
                    server.accept().use { client ->
                        receiver = client
                        sender.connect(InetSocketAddress("127.0.0.1", reversePort), 5_000)
                        val upstream = thread(name = "genui-ios-simulator-upstream", isDaemon = true) {
                            runCatching { forward(client, sender) }
                        }
                        forward(sender, client)
                        upstream.join(3_000)
                    }
                }.onFailure { if (!server.isClosed) System.err.println("Simulator relay failed: ${it.message}") }
            }
        } catch (error: Exception) {
            close()
            throw error
        }
    }

    private fun forward(source: Socket, destination: Socket) {
        source.getInputStream().copyTo(destination.getOutputStream())
        destination.shutdownOutput()
    }

    override fun close() {
        runCatching { nsd.unregisterService(registration) }
        server.close()
        sender.close()
        receiver?.close()
    }
}
