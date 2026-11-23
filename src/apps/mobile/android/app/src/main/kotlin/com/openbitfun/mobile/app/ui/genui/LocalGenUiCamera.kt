package com.openbitfun.mobile.app.ui.genui

import android.Manifest
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.Surface
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.Observer
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as Geometry
import com.openbitfun.mobile.app.ui.theme.openBitFunColors
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCameraStatus
import com.openbitfun.mobile.core.feature.genui.LocalGenUiPoseJoint
import com.openbitfun.mobile.core.feature.genui.LocalGenUiPosePoint
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay

@Composable
internal fun LocalGenUiCamera(
    subscribed: Boolean,
    wanted: Boolean,
    landscape: Boolean,
    compact: Boolean,
    onStatus: (LocalGenUiCameraStatus) -> Unit,
    onPose: (List<LocalGenUiPosePoint>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val supported = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_FRONT)
    }
    var prompted by remember { mutableStateOf(false) }
    var permissionPending by remember { mutableStateOf(false) }
    var granted by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        permissionPending = false
        granted = allowed
    }
    LaunchedEffect(subscribed, wanted, permissionPending) {
        if (!subscribed && !permissionPending) prompted = false
        if (!wanted || !supported || permissionPending) return@LaunchedEffect
        granted = ContextCompat.checkSelfPermission(context, CAMERA_PERMISSION) == PackageManager.PERMISSION_GRANTED
        if (!granted && !prompted) {
            prompted = true
            permissionPending = true
            launcher.launch(CAMERA_PERMISSION)
        }
    }
    if (!wanted) return
    val colors = openBitFunColors
    val line = if (MaterialTheme.colorScheme.background.luminance() > 0.5f) {
        MobileDesignColors.Light.Line
    } else MobileDesignColors.Dark.Line
    val shortEdge = if (compact) Geometry.GenuiCameraCompactShortEdge else Geometry.GenuiCameraShortEdge
    val longEdge = if (compact) Geometry.GenuiCameraCompactLongEdge else Geometry.GenuiCameraLongEdge
    val radius = if (compact) Geometry.GenuiCameraCompactRadius else Geometry.GenuiCameraRadius
    val labelInset = if (compact) Geometry.GenuiCameraCompactLabelInset else Geometry.GenuiCameraLabelInset
    val label = stringResource(R.string.genui_camera_on)
    val shape = RoundedCornerShape(radius)
    var active by remember { mutableStateOf(false) }
    val preview = remember(context) {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val status by rememberUpdatedState(onStatus)
    val pose by rememberUpdatedState(onPose)
    LaunchedEffect(preview, owner, supported, granted, prompted, permissionPending, landscape) {
        if (!supported) {
            status(LocalGenUiCameraStatus.UNAVAILABLE)
            return@LaunchedEffect
        }
        if (!granted) {
            if (prompted && !permissionPending) status(LocalGenUiCameraStatus.DENIED)
            return@LaunchedEffect
        }
        try {
            repeat(3) { attempt ->
                status(LocalGenUiCameraStatus.STARTING)
                try {
                    capture(preview, owner, { value ->
                        active = value == LocalGenUiCameraStatus.ACTIVE
                        status(value)
                    }, { pose(it) })
                    return@LaunchedEffect
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    active = false
                    status(LocalGenUiCameraStatus.FAILED)
                    if (attempt < 2) delay(1200)
                }
            }
        } finally {
            active = false
        }
    }
    Box(
        modifier
            .size(if (landscape) longEdge else shortEdge, if (landscape) shortEdge else longEdge)
            .clip(shape)
            .background(colors.mediaBackground)
            .border(1.dp, line, shape),
        contentAlignment = Alignment.BottomCenter,
    ) {
        AndroidView(factory = { preview }, modifier = Modifier.fillMaxSize())
        if (active) Text(
            label,
            Modifier.padding(bottom = labelInset)
                .background(colors.toastBackground, RoundedCornerShape(Geometry.GenuiCameraLabelRadius))
                .padding(horizontal = labelInset, vertical = Geometry.GenuiCameraLabelVerticalPadding),
            color = MobileDesignColors.Light.ContentOnAction,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
        )
    }
}

private const val CAMERA_PERMISSION = Manifest.permission.CAMERA

private suspend fun capture(
    view: PreviewView,
    owner: LifecycleOwner,
    status: (LocalGenUiCameraStatus) -> Unit,
    pose: (List<LocalGenUiPosePoint>) -> Unit,
) {
    val context = view.context
    val executor = ContextCompat.getMainExecutor(context)
    val future = ProcessCameraProvider.getInstance(context)
    val ready = CompletableDeferred<ProcessCameraProvider>()
    future.addListener({
        runCatching { future.get() }.fold(ready::complete, ready::completeExceptionally)
    }, executor)
    val provider = ready.await()
    val selector = CameraSelector.DEFAULT_FRONT_CAMERA
    if (!provider.hasCamera(selector)) {
        status(LocalGenUiCameraStatus.UNAVAILABLE)
        return
    }
    val rotation = view.display?.rotation ?: Surface.ROTATION_0
    val preview = Preview.Builder().setTargetRotation(rotation).build().apply {
        setSurfaceProvider(view.surfaceProvider)
    }
    val analysis = ImageAnalysis.Builder().setTargetRotation(rotation)
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
    val detector = PoseAnalysis(pose)
    val failure = CompletableDeferred<Unit>()
    val observer = Observer<CameraState> { state ->
        if (state.error != null) failure.completeExceptionally(IllegalStateException("Camera unavailable"))
        else if (state.type == CameraState.Type.OPEN) status(LocalGenUiCameraStatus.ACTIVE)
    }
    val camera = try {
        analysis.setAnalyzer(executor, detector)
        provider.bindToLifecycle(owner, selector, preview, analysis)
    } catch (error: Exception) {
        analysis.clearAnalyzer()
        detector.close()
        throw error
    }
    try {
        camera.cameraInfo.cameraState.observeForever(observer)
        failure.await()
    } finally {
        camera.cameraInfo.cameraState.removeObserver(observer)
        analysis.clearAnalyzer()
        detector.close()
        provider.unbind(preview, analysis)
    }
}

private class PoseAnalysis(private val deliver: (List<LocalGenUiPosePoint>) -> Unit) : ImageAnalysis.Analyzer {
    private val detector = PoseDetection.getClient(
        PoseDetectorOptions.Builder().setDetectorMode(PoseDetectorOptions.STREAM_MODE).build(),
    )
    private var lastFrame = Long.MIN_VALUE / 2
    private var closed = false
    private var analyzing = false

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    override fun analyze(frame: ImageProxy) {
        val now = SystemClock.elapsedRealtime()
        val image = frame.image
        if (closed || analyzing || image == null || now - lastFrame < 200) {
            frame.close()
            return
        }
        lastFrame = now
        analyzing = true
        try {
            detector.process(InputImage.fromMediaImage(image, frame.imageInfo.rotationDegrees))
                .addOnCompleteListener { task ->
                    try {
                        if (!closed && task.isSuccessful) {
                            deliver(joints.mapNotNull { (type, joint) ->
                                task.result.getPoseLandmark(type)?.let { point ->
                                    LocalGenUiPosePoint(joint, point.position.x.toDouble(), point.position.y.toDouble(),
                                        point.inFrameLikelihood.toDouble())
                                }
                            })
                        }
                    } finally {
                        frame.close()
                        analyzing = false
                        if (closed) detector.close()
                    }
                }
        } catch (_: Exception) {
            frame.close()
            analyzing = false
        }
    }

    fun close() {
        closed = true
        if (!analyzing) detector.close()
    }

    companion object {
        private val joints = listOf(
            PoseLandmark.NOSE to LocalGenUiPoseJoint.NOSE,
            PoseLandmark.LEFT_SHOULDER to LocalGenUiPoseJoint.LEFT_SHOULDER,
            PoseLandmark.RIGHT_SHOULDER to LocalGenUiPoseJoint.RIGHT_SHOULDER,
            PoseLandmark.LEFT_WRIST to LocalGenUiPoseJoint.LEFT_WRIST,
            PoseLandmark.RIGHT_WRIST to LocalGenUiPoseJoint.RIGHT_WRIST,
            PoseLandmark.LEFT_HIP to LocalGenUiPoseJoint.LEFT_HIP,
            PoseLandmark.RIGHT_HIP to LocalGenUiPoseJoint.RIGHT_HIP,
        )
    }
}
