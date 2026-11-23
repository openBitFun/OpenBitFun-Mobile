package com.openbitfun.mobile.app.ui.genui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.PersistableBundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaboration
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaborationRequest
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaborationResult
import com.openbitfun.mobile.core.feature.genui.LocalGenUiImageKind
import com.openbitfun.mobile.core.feature.genui.LocalGenUiMedia
import com.openbitfun.mobile.core.feature.genui.LocalGenUiNearbyApproval
import com.openbitfun.mobile.core.feature.genui.LocalGenUiNearbyUpload
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.Inet4Address

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LocalGenUiReceiveImage(
    media: LocalGenUiMedia,
    request: LocalGenUiCollaborationRequest,
    onResult: (LocalGenUiCollaborationResult, String, String) -> Unit,
) {
    val context = LocalContext.current
    val callback by rememberUpdatedState(onResult)
    var permitted by remember { mutableStateOf(context.localNetworkAllowed()) }
    var code by remember { mutableStateOf<String?>(null) }
    val nearby = remember(context) { LocalGenUiNearbyImages(context.applicationContext) }
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val foreground = lifecycle.isAtLeast(Lifecycle.State.STARTED)
    var showCode by remember { mutableStateOf(false) }
    val devices by produceState(emptyList<NsdServiceInfo>(), nearby, foreground, permitted, showCode) {
        value = emptyList()
        if (foreground && permitted && !showCode) nearby.browse().collect { value = it }
    }
    var selected by remember { mutableStateOf<NsdServiceInfo?>(null) }
    var approval by remember { mutableStateOf<LocalGenUiNearbyApproval?>(null) }
    var waitingForImage by remember { mutableStateOf(false) }
    var inviteError by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) permitted = true
        else callback(LocalGenUiCollaborationResult.UNAVAILABLE, "networkPermission", "")
    }
    LaunchedEffect(permitted, foreground, showCode) {
        if (!foreground) {
            callback(LocalGenUiCollaborationResult.CANCELLED, "localCancelled", "")
            return@LaunchedEffect
        }
        if (!permitted) {
            permission.launch(Manifest.permission.ACCESS_LOCAL_NETWORK)
            return@LaunchedEffect
        }
        code = null
        if (!showCode) return@LaunchedEffect
        val address = context.localImageAddress()
        if (address == null) {
            callback(LocalGenUiCollaborationResult.UNAVAILABLE, "networkUnavailable", "")
            return@LaunchedEffect
        }
        val asset = LocalGenUiCollaboration.receive(media, request, address) { code = it }
        if (asset == null) callback(LocalGenUiCollaborationResult.FAILED, "platformError", "")
        else callback(LocalGenUiCollaborationResult.COMPLETED, "", asset)
    }
    LaunchedEffect(selected, showCode, foreground) {
        val device = selected ?: return@LaunchedEffect
        if (showCode || !foreground) return@LaunchedEffect
        try {
            val resolved = withTimeoutOrNull(5_000) { nearby.resolve(device) }
            val asset = resolved?.let {
                LocalGenUiCollaboration.receiveNearby(
                    media, request, it.address, it.port,
                    onApproval = { pending -> approval = pending },
                    onReady = { waitingForImage = true },
                )
            }
            if (asset == null) inviteError = true
            else callback(LocalGenUiCollaborationResult.COMPLETED, "", asset)
        } finally {
            approval = null
            waitingForImage = false
            selected = null
        }
    }
    ModalBottomSheet(onDismissRequest = { callback(LocalGenUiCollaborationResult.CANCELLED, "localCancelled", "") }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.genui_image_receive), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.genui_nearby_receive_help), style = MaterialTheme.typography.bodyMedium)
            val invite = code
            if (!showCode) {
                val pending = approval
                when {
                    pending != null -> NearbyImageVerification(pending) {
                        pending.decide(it)
                        approval = null
                    }
                    waitingForImage -> Text(stringResource(R.string.genui_nearby_requested))
                    selected != null -> CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    else -> {
                        devices.forEach { device ->
                            OutlinedButton(onClick = { selected = device; inviteError = false },
                                modifier = Modifier.fillMaxWidth().testTag("genui-nearby-device")) {
                                Text(device.serviceName.take(63))
                            }
                        }
                        if (devices.isEmpty()) Text(stringResource(R.string.genui_nearby_searching))
                        if (inviteError) Text(stringResource(R.string.genui_nearby_failed))
                    }
                }
            } else if (invite == null) {
                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            }
            TextButton(onClick = {
                selected = null
                showCode = !showCode
            }) {
                Text(stringResource(if (showCode) R.string.genui_nearby_hide_code else R.string.genui_nearby_use_code))
            }
            if (showCode && invite != null) {
                Text(stringResource(R.string.genui_image_receive_help), style = MaterialTheme.typography.bodyMedium)
                val matrix = remember(invite) {
                    val size = 256
                    val cells = QRCodeWriter().encode(invite, BarcodeFormat.QR_CODE, size, size)
                    val pixels = IntArray(size * size) { index ->
                        if (cells[index % size, index / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
                    }
                    Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888).asImageBitmap()
                }
                Image(matrix, stringResource(R.string.genui_image_code), Modifier.size(216.dp))
                TextButton(onClick = { context.copyImageInvite(invite) }) { Text(stringResource(R.string.genui_image_copy)) }
            }
            TextButton(onClick = { callback(LocalGenUiCollaborationResult.CANCELLED, "localCancelled", "") }) {
                Text(stringResource(R.string.genui_image_close))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LocalGenUiSendImage(onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    val invite = remember(code) { LocalGenUiCollaboration.parse(code) }
    var sending by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Int?>(null) }
    var pendingCapture by remember { mutableStateOf<File?>(null) }
    var selection by remember { mutableStateOf<Uri?>(null) }
    val nearby = remember(context) { LocalGenUiNearbyImages(context.applicationContext) }
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val foreground = lifecycle.isAtLeast(Lifecycle.State.STARTED)
    var mayAdvertise by remember { mutableStateOf(context.localNetworkAllowed()) }
    var advertising by remember { mutableStateOf(false) }
    var approval by remember { mutableStateOf<LocalGenUiNearbyApproval?>(null) }
    var nearbyUpload by remember { mutableStateOf<LocalGenUiNearbyUpload?>(null) }
    var systemCaptureOpen by remember { mutableStateOf(false) }
    val keepListening = foreground || systemCaptureOpen
    val nearbyPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        mayAdvertise = allowed
        if (!allowed) status = R.string.genui_image_network_denied
    }
    fun choose(uri: Uri?) {
        selection = uri
        if (uri == null) {
            pendingCapture?.delete()
            pendingCapture = null
        }
    }
    LaunchedEffect(nearby, keepListening, mayAdvertise, invite == null) {
        if (!keepListening || !mayAdvertise || invite != null) return@LaunchedEffect
        val address = context.localImageAddress() ?: return@LaunchedEffect
        do {
            var registration: kotlinx.coroutines.Job? = null
            var approvedRequest = false
            try {
                LocalGenUiCollaboration.awaitNearbyUpload(address, onListening = { port ->
                    registration = launch { nearby.publish(address, port).collect { advertising = it } }
                }, onApproval = { approval = it }, onUpload = { upload ->
                    if (upload != null) {
                        approvedRequest = true
                        registration?.cancel()
                        advertising = false
                        choose(null)
                        status = null
                    }
                    nearbyUpload = upload
                })
            } finally {
                registration?.cancelAndJoin()
                advertising = false
                approval = null
                nearbyUpload = null
            }
        } while (isActive && approvedRequest)
    }

    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        systemCaptureOpen = false
        choose(uri)
    }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        systemCaptureOpen = false
        choose(if (success) pendingCapture?.let { FileProvider.getUriForFile(context, "${context.packageName}.genui-images", it) } else null)
    }
    var scanFallback by remember { mutableStateOf(false) }
    val scan = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) {
        systemCaptureOpen = false
        val image = GmsDocumentScanningResult.fromActivityResultIntent(it.data)?.pages?.firstOrNull()?.imageUri
        if (image != null) choose(image) else scanFallback = true
    }
    fun openCamera() {
        try {
            val folder = File(context.cacheDir, "genui-capture").apply { mkdirs() }
            pendingCapture?.delete()
            val file = File.createTempFile("photo-", ".jpg", folder)
            pendingCapture = file
            systemCaptureOpen = true
            photo.launch(FileProvider.getUriForFile(context, "${context.packageName}.genui-images", file))
        } catch (_: Exception) {
            systemCaptureOpen = false
            choose(null)
            status = R.string.genui_image_source_failed
        }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) openCamera() else status = R.string.genui_image_camera_denied
    }
    LaunchedEffect(scanFallback) {
        if (!scanFallback) return@LaunchedEffect
        scanFallback = false
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            openCamera()
        } else {
            cameraPermission.launch(Manifest.permission.CAMERA)
        }
    }
    fun send() {
        val upload = nearbyUpload
        val selectedInvite = invite
        if (upload == null && selectedInvite == null) return
        val uri = selection ?: return
        sending = true
        status = null
        scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) { readGenUiJpeg(context, uri) }
                val delivered = when {
                    bytes == null -> false
                    upload != null -> upload.submit(bytes)
                    selectedInvite != null -> LocalGenUiCollaboration.send(selectedInvite, bytes)
                    else -> false
                }
                status = if (delivered) {
                    choose(null)
                    code = ""
                    R.string.genui_image_sent
                } else R.string.genui_image_send_failed
            } finally {
                sending = false
            }
        }
    }
    val network = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) send() else status = R.string.genui_image_network_denied
    }
    DisposableEffect(Unit) {
        onDispose { pendingCapture?.delete() }
    }

    val close = {
        nearbyUpload?.cancel()
        onClose()
    }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.genui_image_send), style = MaterialTheme.typography.titleLarge)
            val pending = approval
            when {
                pending != null -> NearbyImageVerification(pending) {
                    pending.decide(it)
                    approval = null
                }
                advertising -> Text(stringResource(R.string.genui_nearby_ready), style = MaterialTheme.typography.bodyMedium)
                !mayAdvertise -> TextButton(onClick = { nearbyPermission.launch(Manifest.permission.ACCESS_LOCAL_NETWORK) }) {
                    Text(stringResource(R.string.genui_nearby_allow))
                }
            }
            OutlinedTextField(
                code, { code = it.take(160); choose(null); status = null },
                modifier = Modifier.fillMaxWidth().testTag("genui-image-invite"),
                enabled = !sending && nearbyUpload == null, singleLine = true, visualTransformation = PasswordVisualTransformation(),
                label = { Text(stringResource(R.string.genui_image_code)) },
                isError = code.isNotBlank() && invite == null,
            )
            TextButton(enabled = !sending && nearbyUpload == null, onClick = {
                val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                GmsBarcodeScanning.getClient(context, options).startScan()
                    .addOnSuccessListener { barcode ->
                        if (scope.isActive) {
                            code = barcode.rawValue.orEmpty().take(160)
                            choose(null)
                            status = null
                        }
                    }
                    .addOnFailureListener { if (scope.isActive) status = R.string.genui_image_source_failed }
            }) { Text(stringResource(R.string.genui_image_scan_code)) }
            (nearbyUpload?.kind ?: invite?.kind)?.let { kind ->
                val action = when (kind) {
                    LocalGenUiImageKind.PHOTO -> R.string.genui_image_take_photo
                    LocalGenUiImageKind.SCAN -> R.string.genui_image_scan_document
                    LocalGenUiImageKind.GALLERY -> R.string.genui_image_gallery
                }
                OutlinedButton(enabled = !sending, onClick = {
                    choose(null)
                    status = null
                    when (kind) {
                        LocalGenUiImageKind.GALLERY -> {
                            systemCaptureOpen = true
                            gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }
                        LocalGenUiImageKind.PHOTO -> {
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) openCamera()
                            else cameraPermission.launch(Manifest.permission.CAMERA)
                        }
                        LocalGenUiImageKind.SCAN -> {
                            // AOSP emulator images do not ship the Play services
                            // document-scanner backend. Use the native camera there,
                            // while real devices continue to use ML Kit's scanner.
                            if (Build.FINGERPRINT.startsWith("generic") || Build.MODEL.startsWith("sdk_") || Build.HARDWARE == "ranchu") {
                                if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                                    openCamera()
                                } else {
                                    cameraPermission.launch(Manifest.permission.CAMERA)
                                }
                            } else context.activity()?.let { activity ->
                                val options = GmsDocumentScannerOptions.Builder()
                                .setGalleryImportAllowed(false).setPageLimit(1)
                                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL).build()
                            GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                                .addOnSuccessListener {
                                    if (scope.isActive) {
                                        systemCaptureOpen = true
                                        scan.launch(IntentSenderRequest.Builder(it).build())
                                    }
                                }
                                .addOnFailureListener {
                                    if (!scope.isActive) return@addOnFailureListener
                                    // ML Kit's document scanner is delivered by Google Play services.
                                    // Keep the cross-device request usable on emulator images and
                                    // devices without that optional module by falling back to the
                                    // native camera capture path.
                                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                                        openCamera()
                                    } else {
                                        cameraPermission.launch(Manifest.permission.CAMERA)
                                    }
                                }
                            }
                        }
                    }
                }, modifier = Modifier.testTag("genui-image-source")) { Text(stringResource(action)) }
                if (selection != null) Button(enabled = !sending, onClick = {
                    if (context.localNetworkAllowed()) send() else network.launch(Manifest.permission.ACCESS_LOCAL_NETWORK)
                }) { Text(stringResource(R.string.genui_image_confirm_send)) }
            }
            if (sending) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            status?.let { Text(stringResource(it), style = MaterialTheme.typography.bodyMedium) }
            TextButton(onClick = close) { Text(stringResource(R.string.genui_image_close)) }
        }
    }
}

@Composable
private fun NearbyImageVerification(approval: LocalGenUiNearbyApproval, onDecision: (Boolean) -> Unit) {
    val operation = when (approval.kind) {
        LocalGenUiImageKind.PHOTO -> R.string.genui_image_take_photo
        LocalGenUiImageKind.SCAN -> R.string.genui_image_scan_document
        LocalGenUiImageKind.GALLERY -> R.string.genui_image_gallery
    }
    Text(stringResource(R.string.genui_nearby_verify, stringResource(operation)), style = MaterialTheme.typography.bodyMedium)
    Text(approval.code, style = MaterialTheme.typography.titleLarge, modifier = Modifier.testTag("genui-nearby-verification"))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = { onDecision(false) }) { Text(stringResource(R.string.genui_nearby_decline)) }
        Button(onClick = { onDecision(true) }) { Text(stringResource(R.string.genui_nearby_confirm)) }
    }
}

private fun Context.localNetworkAllowed() = Build.VERSION.SDK_INT < 37 ||
    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED

internal fun Context.localImageAddress(): String? {
    val manager = getSystemService(ConnectivityManager::class.java) ?: return null
    val active = manager.activeNetwork ?: return null
    val capabilities = manager.getNetworkCapabilities(active) ?: return null
    if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
        !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    ) return null
    return manager.getLinkProperties(active)?.linkAddresses.orEmpty().asSequence()
        .mapNotNull { (it.address as? Inet4Address)?.hostAddress }
        .firstOrNull(LocalGenUiCollaboration::localAddress)
}

private fun Context.copyImageInvite(code: String) {
    val clip = ClipData.newPlainText(getString(R.string.genui_image_code), code)
    clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
    getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip)
}

private fun readGenUiJpeg(context: Context, uri: Uri): ByteArray? = runCatching {
    val resolver = context.contentResolver
    val decoded = if (Build.VERSION.SDK_INT >= 28) {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val factor = minOf(1.0, 1600.0 / maxOf(info.size.width, info.size.height))
            decoder.setTargetSize((info.size.width * factor).toInt().coerceAtLeast(1), (info.size.height * factor).toInt().coerceAtLeast(1))
        }
    } else {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val options = BitmapFactory.Options().apply {
            while (maxOf(bounds.outWidth, bounds.outHeight) / inSampleSize.coerceAtLeast(1) > 1600) {
                inSampleSize = inSampleSize.coerceAtLeast(1) * 2
            }
        }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
    }
    try {
        ByteArrayOutputStream().use { output ->
            for (quality in listOf(85, 70, 55)) {
                if (decoded.compress(Bitmap.CompressFormat.JPEG, quality, output) &&
                    output.size() <= LocalGenUiCollaboration.MAX_IMAGE_BYTES
                ) return output.toByteArray()
                output.reset()
            }
            null
        }
    } finally { decoded.recycle() }
}.getOrNull()
