import AVFoundation
import SwiftUI

/// The island's Mirror page: a live, mirrored front-camera preview. The camera runs only while this page is open.
struct IslandCameraView: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
            case .notDetermined:
                message("Check yourself before a call", button: "Turn On Camera") {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            default:
                message("Camera access is off for DevIsland", button: "Open Camera Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "web.camera").font(.system(size: 24))
            Text(text).font(.system(size: 12.5, weight: .semibold))
            Button(button, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandPane()
    }
}

private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ view: PreviewView, context: Context) {}
    static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.stop() }
}

private final class PreviewView: NSView {
    private let session = AVCaptureSession()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer = preview
        if let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.sessionPreset = .high
            session.addInput(input)
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        nonisolated(unsafe) let session = session // AVCaptureSession is meant to be started and stopped off the main thread
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    required init?(coder: NSCoder) { nil }

    func stop() {
        nonisolated(unsafe) let session = session // AVCaptureSession is meant to be started and stopped off the main thread
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}
