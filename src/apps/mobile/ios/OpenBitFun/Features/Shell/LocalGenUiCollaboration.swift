import AVFoundation
import CoreImage.CIFilterBuiltins
import ImageIO
import Network
import OpenBitFunMobileCore
import PhotosUI
import SwiftUI
import VisionKit

struct LocalGenUiImageRequest: Identifiable {
    let request: LocalGenUiCollaborationRequest
    let finish: (LocalGenUiCollaborationResult, String, String) -> Void
    var id: String { request.id }
}

struct LocalGenUiReceiveImage: View {
    @ObservedObject var model: MobileAppModel
    let media: LocalGenUiMedia
    let transfer: LocalGenUiImageRequest
    @State private var invite: String?
    @StateObject private var nearby = NearbyImageDiscovery()
    @State private var selectedDevice: NearbyImageDevice?
    @State private var approval: LocalGenUiNearbyApproval?
    @State private var waitingForImage = false
    @State private var inviteFailed = false
    @State private var showCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(model.localized("跨设备取材"))
                    .font(MobileDesignTypography.titleLarge.font)
                    .accessibilityIdentifier("genui-image-receive")
                Text(model.localized("请在另一台设备打开「发送图片到另一台设备」，然后在这里选择它。"))
                    .font(MobileDesignTypography.bodyMedium.font)
                    .foregroundStyle(OpenBitFunTheme.muted)
                if showCode {
                    if let invite { manualCode(invite) } else { ProgressView() }
                } else {
                    nearbySelection
                }
                Button(model.localized(showCode ? "隐藏连接码" : "使用连接码")) {
                    selectedDevice = nil
                    showCode.toggle()
                }
                Button(model.localized("关闭")) { cancel() }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(OpenBitFunTheme.page)
        .presentationDetents([.medium, .large])
        .task(id: showCode) {
            invite = nil
            if !showCode {
                nearby.browse()
                return
            }
            nearby.stopBrowsing()
            guard let address = Self.wifiAddress() else {
                transfer.finish(.unavailable, "networkUnavailable", "")
                return
            }
            let asset = try? await LocalGenUiCollaboration.shared.receive(
                media: media, request: transfer.request, address: address
            ) { text in
                MainActor.assumeIsolated { invite = text }
            }
            if let asset { await finish(asset: asset) }
            else if !Task.isCancelled { transfer.finish(.failed, "platformError", "") }
        }
        .task(id: selectedDevice) {
            guard let device = selectedDevice, !showCode else { return }
            let asset = try? await LocalGenUiCollaboration.shared.receiveNearby(
                media: media, request: transfer.request,
                address: device.address, port: Int32(device.port),
                onApproval: { pending in MainActor.assumeIsolated { approval = pending } },
                onReady: { MainActor.assumeIsolated { waitingForImage = true } }
            )
            if let asset { await finish(asset: asset) }
            else if !Task.isCancelled { inviteFailed = true }
            if !Task.isCancelled {
                approval = nil
                waitingForImage = false
                selectedDevice = nil
            }
        }
        .onDisappear {
            nearby.stopBrowsing()
            cancel()
        }
    }

    private func finish(asset: String) async {
        if Task.isCancelled {
            try? await LocalGenUiCollaboration.shared.discard(media: media, request: transfer.request, asset: asset)
        } else {
            transfer.finish(.completed, "", asset)
        }
    }

    @ViewBuilder
    private var nearbySelection: some View {
        if let approval {
            NearbyImageVerification(model: model, approval: approval) { accepted in
                approval.decide(approve: accepted)
                self.approval = nil
            }
        } else if waitingForImage {
            Text(model.localized("请求已发送。请在另一台设备取材。"))
        } else if selectedDevice != nil {
            ProgressView()
        } else {
            ForEach(nearby.devices) { device in
                Button(device.name) {
                    inviteFailed = false
                    selectedDevice = device
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("genui-nearby-device")
            }
            if nearby.devices.isEmpty {
                Text(model.localized("正在查找附近设备…")).foregroundStyle(OpenBitFunTheme.muted)
            }
            if inviteFailed { Text(model.localized("无法连接这台设备，请重试。")) }
        }
    }

    @ViewBuilder
    private func manualCode(_ invite: String) -> some View {
        Text(model.localized("两台设备连接同一网络。在另一台设备的「发送图片到另一台设备」中扫描二维码或输入连接码。"))
            .font(MobileDesignTypography.bodyMedium.font)
            .foregroundStyle(OpenBitFunTheme.muted)
        if let image = Self.qrCode(invite) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable().scaledToFit()
                .frame(width: 216, height: 216)
                .accessibilityLabel(model.localized("连接码"))
        }
        Button(model.localized("复制连接码")) {
            UIPasteboard.general.setItems([["public.utf8-plain-text": invite]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(180)])
        }
    }

    private func cancel() { transfer.finish(.cancelled, "localCancelled", "") }

    private static func qrCode(_ code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        guard let output = filter.outputImage,
              let bitmap = CIContext().createCGImage(output, from: output.extent) else { return nil }
        // The quiet zone is part of the QR raster. Keep its contrast in dark mode.
        let border: CGFloat = 4
        let edge = CGFloat(bitmap.width)
        let size = CGSize(width: edge + 2 * border, height: edge + 2 * border)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: bitmap).draw(in: CGRect(x: border, y: border, width: edge, height: edge))
        }
    }

    fileprivate static func wifiAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(first) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = ptr.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.ifa_name)
            #if targetEnvironment(simulator)
            guard name.hasPrefix("en") else { continue }
            #else
            guard name == "en0" else { continue }
            #endif
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &text, socklen_t(text.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: text)
            if LocalGenUiCollaboration.shared.localAddress(address: address) { return address }
        }
        return nil
    }
}

struct LocalGenUiSendImage: View {
    private enum Capture: String, Identifiable {
        case code, camera, document
        var id: String { rawValue }
    }

    @ObservedObject var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    @State private var capture: Capture?
    @State private var photoItem: PhotosPickerItem?
    @State private var galleryOpen = false
    @State private var photo: UIImage?
    @State private var sending: Task<Void, Never>?
    @State private var status: String?
    @StateObject private var nearby = NearbyImageDiscovery()
    @State private var nearbyApproval: LocalGenUiNearbyApproval?
    @State private var nearbyUpload: LocalGenUiNearbyUpload?

    private var mayAdvertise: Bool {
        (scenePhase != .background || galleryOpen || capture == .camera || capture == .document) &&
            LocalGenUiCollaboration.shared.parse(invite: code) == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(model.localized("发送图片到另一台设备")).font(MobileDesignTypography.titleLarge.font)
                if let approval = nearbyApproval {
                    NearbyImageVerification(model: model, approval: approval) { accepted in
                        approval.decide(approve: accepted)
                        nearbyApproval = nil
                    }
                } else if nearby.advertised {
                    Text(model.localized("正在等待附近设备发来取材请求。"))
                        .font(MobileDesignTypography.bodyMedium.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                }
                SecureField(model.localized("连接码"), text: Binding(
                    get: { code },
                    set: { code = $0; status = nil }
                ))
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("genui-image-invite")
                    .disabled(sending != nil || nearbyUpload != nil)
                if DataScannerViewController.isSupported {
                    Button(model.localized("扫描连接码")) { openScanner() }.disabled(sending != nil || nearbyUpload != nil)
                }
                let invite = LocalGenUiCollaboration.shared.parse(invite: code)
                if let kind = nearbyUpload?.kind ?? invite?.kind {
                    source(kind).disabled(sending != nil)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 120)
                        Button { send(invite, nearbyUpload, photo) } label: {
                            Text(model.localized("发送选中的图片"))
                                .foregroundStyle(MobileDesignColors.contentOnAction)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MobileDesignColors.primaryAction)
                        .disabled(sending != nil)
                    }
                } else if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(model.localized("连接码无效。")).foregroundStyle(OpenBitFunTheme.muted)
                }
                if sending != nil { ProgressView() }
                if let status { Text(model.localized(status)) }
                Button(model.localized("关闭")) { dismiss() }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(OpenBitFunTheme.ink)
        .background(OpenBitFunTheme.page)
        .presentationDetents([.medium, .large])
        .sheet(item: $capture) { mode in
            Group {
                switch mode {
                case .camera:
                    GenUiPhotoCamera { image in capture = nil; photo = image }
                case .document:
                    GenUiDocumentCamera { image in capture = nil; photo = image }
                case .code:
                    GenUiInviteScanner { text in capture = nil; code = text; status = nil }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(model.localized("关闭")) { capture = nil }.padding(12)
                    Spacer()
                }
                .background(OpenBitFunTheme.page)
            }
        }
        .onChange(of: code) { _ in
            photoItem = nil
            photo = nil
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            let data = try? await photoItem.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            photo = data.flatMap(Self.decode)
            status = photo == nil ? "无法读取所选图片。" : nil
        }
        .task(id: mayAdvertise) {
            guard mayAdvertise, let address = LocalGenUiReceiveImage.wifiAddress() else { return }
            defer {
                nearby.stopAdvertising()
                nearbyApproval = nil
            }
            var approvedRequest = false
            repeat {
                approvedRequest = false
                _ = try? await LocalGenUiCollaboration.shared.awaitNearbyUpload(
                    address: address, onListening: { port in
                        MainActor.assumeIsolated { nearby.advertise(address: address, port: port.int32Value) }
                    }, onApproval: { approval in
                        MainActor.assumeIsolated { nearbyApproval = approval }
                    }, onUpload: { upload in
                        MainActor.assumeIsolated {
                            if upload != nil {
                                approvedRequest = true
                                nearby.stopAdvertising()
                                photoItem = nil
                                photo = nil
                                status = nil
                            }
                            nearbyUpload = upload
                        }
                    }
                )
            } while approvedRequest && !Task.isCancelled
        }
        .photosPicker(isPresented: $galleryOpen, selection: $photoItem, matching: .images)
        .onDisappear {
            nearbyUpload?.cancel()
            sending?.cancel()
        }
    }

    @ViewBuilder
    private func source(_ kind: LocalGenUiImageKind) -> some View {
        switch kind {
        case .gallery:
            Button(model.localized("从图库选择")) { galleryOpen = true }
        case .photo:
            Button(model.localized("拍照")) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { capture = .camera }
                else { status = "无法打开相机或扫描器。" }
            }
        case .scan:
            Button(model.localized("扫描文档")) {
                if VNDocumentCameraViewController.isSupported { capture = .document }
                else { status = "无法打开相机或扫描器。" }
            }
        }
    }

    private func openScanner() {
        Task { @MainActor in
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            if DataScannerViewController.isAvailable { capture = .code }
            else { status = "无法打开相机或扫描器。" }
        }
    }

    private func send(_ invite: LocalGenUiImageInvite?, _ upload: LocalGenUiNearbyUpload?, _ photo: UIImage) {
        status = nil
        sending = Task { @MainActor in
            defer { sending = nil }
            guard let bytes = Self.jpeg(photo) else { status = "无法读取所选图片。"; return }
            let value = KotlinByteArray(size: Int32(bytes.count))
            for (index, byte) in bytes.enumerated() { value.set(index: Int32(index), value: Int8(bitPattern: byte)) }
            let sent: Bool
            if let upload {
                sent = (try? await upload.submit(bytes: value)) == true
            } else if let invite {
                sent = (try? await LocalGenUiCollaboration.shared.send(invite: invite, bytes: value)) == true
            } else {
                return
            }
            guard !Task.isCancelled else { return }
            if sent {
                self.photo = nil
                self.code = ""
                status = "图片已送达。"
            } else { status = "未确认送达。请检查网络和连接码。" }
        }
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private static func jpeg(_ image: UIImage) -> Data? {
        let edge = max(image.size.width, image.size.height)
        guard edge > 0 else { return nil }
        let scale = min(1, 1600 / edge)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.85, 0.70, 0.55] {
            if let jpeg = resized.jpegData(compressionQuality: quality),
               jpeg.count <= LocalGenUiCollaboration.shared.MAX_IMAGE_BYTES { return jpeg }
        }
        return nil
    }
}

private struct GenUiPhotoCamera: UIViewControllerRepresentable {
    let finished: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finished: (UIImage?) -> Void
        init(_ finished: @escaping (UIImage?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finished(info[.originalImage] as? UIImage)
        }
    }
}

private struct GenUiDocumentCamera: UIViewControllerRepresentable {
    let finished: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let finished: (UIImage?) -> Void
        init(_ finished: @escaping (UIImage?) -> Void) { self.finished = finished }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finished(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { finished(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            finished(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
    }
}

private struct GenUiInviteScanner: UIViewControllerRepresentable {
    let found: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])])
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        init(_ found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in addedItems {
                if let code = barcode.payloadStringValue, LocalGenUiCollaboration.shared.parse(invite: code) != nil {
                    scanner.stopScanning()
                    found(code)
                    break
                }
            }
        }
    }
}

private struct NearbyImageDevice: Hashable, Identifiable {
    let name: String
    let address: String
    let port: Int
    var id: String { "\(address):\(port)" }
}

@MainActor
private final class NearbyImageDiscovery: NSObject, ObservableObject, NetServiceDelegate {
    @Published private(set) var devices: [NearbyImageDevice] = []
    @Published private(set) var advertised = false
    private var browser: NWBrowser?
    private var publication: NetService?

    func browse() {
        stopBrowsing()
        let type = LocalGenUiCollaboration.shared.NEARBY_SERVICE_TYPE
        let query = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
        browser = query
        query.browseResultsChangedHandler = { [weak self, weak query] results, _ in
            Task { @MainActor [weak self, weak query] in
                guard let self, let query, browser === query else { return }
                var candidates: [String: NearbyImageDevice] = [:]
                for result in results {
                    guard case let .service(name, _, _, _) = result.endpoint,
                          case let .bonjour(txt) = result.metadata,
                          case let .string(address)? = txt.getEntry(for: "ip"),
                          LocalGenUiCollaboration.shared.localAddress(address: address),
                          case let .string(portText)? = txt.getEntry(for: "port"),
                          let port = Int(portText), (1024...65535).contains(port) else { continue }
                    let device = NearbyImageDevice(name: String(name.prefix(63)), address: address, port: port)
                    candidates[device.id] = device
                }
                devices = Array(candidates.values.sorted { $0.name < $1.name }.prefix(32))
            }
        }
        query.start(queue: .main)
    }

    func advertise(address: String, port: Int32) {
        stopAdvertising()
        let type = LocalGenUiCollaboration.shared.NEARBY_SERVICE_TYPE + "."
        let service = NetService(domain: "local.", type: type, name: UIDevice.current.model, port: port)
        service.delegate = self
        service.setTXTRecord(NWTXTRecord(["ip": address, "port": String(port)]).data)
        publication = service
        service.publish()
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        devices = []
    }

    func stopAdvertising() {
        publication?.stop()
        publication = nil
        advertised = false
    }

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        Task { @MainActor [weak self] in
            if self?.publication === sender { self?.advertised = true }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Task { @MainActor [weak self] in
            if self?.publication === sender { self?.stopAdvertising() }
        }
    }
}

private struct NearbyImageVerification: View {
    @ObservedObject var model: MobileAppModel
    let approval: LocalGenUiNearbyApproval
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(model.localizedFormat("%@。请核对两台设备显示的验证码。", model.localized(operation)))
                .font(MobileDesignTypography.bodyMedium.font)
            Text(approval.code)
                .font(MobileDesignTypography.titleLarge.font.monospaced())
                .accessibilityIdentifier("genui-nearby-verification")
            HStack(spacing: 8) {
                Button(model.localized("取消")) { onDecision(false) }
                Button { onDecision(true) } label: {
                    Text(model.localized("验证码一致"))
                        .foregroundStyle(MobileDesignColors.contentOnAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(MobileDesignColors.primaryAction)
            }
        }
    }

    private var operation: String {
        switch approval.kind {
        case .photo: return "拍照"
        case .scan: return "扫描文档"
        case .gallery: return "从图库选择"
        }
    }
}
