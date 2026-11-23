import AVFoundation
import OpenBitFunMobileCore
import SwiftUI
import Vision

@MainActor
final class LocalGenUiCamera: ObservableObject {
    @Published private(set) var presenting = false
    @Published private(set) var active = false
    private let capture = GenUiPoseCapture()
    private var task: Task<Void, Never>?
    private var wanted = false

    func setWanted(
        _ visible: Bool, report: @escaping (LocalGenUiCameraStatus) -> Void,
        pose: @escaping ([LocalGenUiPosePoint]) -> Void
    ) {
        guard visible != wanted else { return }
        wanted = visible
        task?.cancel()
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            presenting = wanted
            active = false
            guard wanted else { return }
            guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil else {
                report(.unavailable)
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break
            case .notDetermined:
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed else { report(.denied); return }
            default:
                report(.denied)
                return
            }
            for attempt in 0..<3 {
                guard !Task.isCancelled else { return }
                report(.starting)
                for await event in capture.events() {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .active:
                        active = true
                        report(.active)
                    case .pose(let points):
                        pose(points)
                    case .unavailable:
                        report(.unavailable)
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                active = false
                report(.failed)
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(1200)) }
            }
        }
    }

    func stop() {
        setWanted(false, report: { _ in }, pose: { _ in })
    }

    func cameraView() -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = capture.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.orientationChanged = { [weak capture] orientation in
            capture?.setOrientation(orientation)
        }
        return view
    }
}

struct LocalGenUiCameraPreview: View {
    let camera: LocalGenUiCamera
    let landscape: Bool
    let compact: Bool
    let label: String

    var body: some View {
        let short = compact ? MobileDesignGeometry.genuiCameraCompactShortEdge : MobileDesignGeometry.genuiCameraShortEdge
        let long = compact ? MobileDesignGeometry.genuiCameraCompactLongEdge : MobileDesignGeometry.genuiCameraLongEdge
        let inset = compact ? MobileDesignGeometry.genuiCameraCompactLabelInset : MobileDesignGeometry.genuiCameraLabelInset
        let shape = RoundedRectangle(cornerRadius: compact
            ? MobileDesignGeometry.genuiCameraCompactRadius : MobileDesignGeometry.genuiCameraRadius)
        ZStack(alignment: .bottom) {
            MobileDesignColors.mediaBackground
            CameraPreview(camera: camera).accessibilityHidden(true)
            if camera.active {
                Text(verbatim: label)
                    .font(MobileDesignTypography.labelSmall.font)
                    .lineLimit(1)
                    .foregroundStyle(MobileDesignColors.contentOnAction)
                    .padding(.horizontal, inset)
                    .padding(.vertical, MobileDesignGeometry.genuiCameraLabelVerticalPadding)
                    .background(MobileDesignColors.toastBackground,
                                in: RoundedRectangle(cornerRadius: MobileDesignGeometry.genuiCameraLabelRadius))
                    .padding(.bottom, inset)
            }
        }
        .frame(width: landscape ? long : short, height: landscape ? short : long)
        .clipShape(shape)
        .overlay(shape.strokeBorder(MobileDesignColors.line, lineWidth: 1))
        .allowsHitTesting(false)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let camera: LocalGenUiCamera
    func makeUIView(context: Context) -> CameraPreviewView { camera.cameraView() }
    func updateUIView(_ view: CameraPreviewView, context: Context) { view.setNeedsLayout() }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var orientationChanged: ((AVCaptureVideoOrientation) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let orientation: AVCaptureVideoOrientation
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        default: orientation = .portrait
        }
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        orientationChanged?(orientation)
    }
}

/** The capture queue owns the session, the detector and all video buffers. */
private final class GenUiPoseCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event {
        case active
        case pose([LocalGenUiPosePoint])
        case unavailable
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "openbitfun.genui.pose")
    private let detector = VNDetectHumanBodyPoseRequest()
    private var lastFrame = -Double.infinity
    private var orientation = AVCaptureVideoOrientation.portrait
    private var continuation: AsyncStream<Event>.Continuation?
    private var captureID: UUID?
    private var observers: [NSObjectProtocol] = []

    func events() -> AsyncStream<Event> {
        AsyncStream { stream in
            let id = UUID()
            queue.async { self.start(id, stream) }
            stream.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    if self.captureID == id { self.stop() }
                }
            }
        }
    }

    func setOrientation(_ next: AVCaptureVideoOrientation) {
        queue.async {
            guard self.orientation != next else { return }
            self.orientation = next
            guard let output = self.session.outputs.first as? AVCaptureVideoDataOutput else { return }
            self.configure(output)
        }
    }

    private func start(_ id: UUID, _ stream: AsyncStream<Event>.Continuation) {
        stop()
        guard let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            stream.yield(.unavailable)
            stream.finish()
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: front) else {
            stream.finish()
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            stream.finish()
            return
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            stream.finish()
            return
        }
        session.addOutput(output)
        configure(output)
        session.commitConfiguration()
        captureID = id
        continuation = stream
        lastFrame = -Double.infinity
        observers = [.AVCaptureSessionRuntimeError, .AVCaptureSessionWasInterrupted].map { name in
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                queue.async {
                    guard self.captureID == id else { return }
                    self.stop()
                }
            }
        }
        session.startRunning()
        if session.isRunning { stream.yield(.active) }
        else { stop() }
    }

    private func configure(_ output: AVCaptureVideoDataOutput) {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    private func stop() {
        captureID = nil
        continuation?.finish()
        continuation = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if session.isRunning { session.stopRunning() }
        guard !session.inputs.isEmpty || !session.outputs.isEmpty else { return }
        session.beginConfiguration()
        session.outputs.forEach(session.removeOutput)
        session.inputs.forEach(session.removeInput)
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let continuation, let image = CMSampleBufferGetImageBuffer(sample) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.2 else { return }
        lastFrame = now
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up)
        guard (try? handler.perform([detector])) != nil else { return }
        let width = Double(CVPixelBufferGetWidth(image))
        let height = Double(CVPixelBufferGetHeight(image))
        let joints = try? detector.results?.first?.recognizedPoints(.all)
        let points = Self.joints.compactMap { joint, label -> LocalGenUiPosePoint? in
            guard let point = joints?[joint] else { return nil }
            return LocalGenUiPosePoint(
                joint: label, x: Double(point.location.x) * width, y: Double(point.location.y) * height,
                confidence: Double(point.confidence)
            )
        }
        continuation.yield(.pose(points))
    }

    private static let joints: [(VNHumanBodyPoseObservation.JointName, LocalGenUiPoseJoint)] = [
        (.nose, .nose), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip)
    ]
}
