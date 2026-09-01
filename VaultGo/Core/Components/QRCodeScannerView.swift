/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// QRCodeScannerView.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import AVFoundation

enum QRCodeScannerError: Error, LocalizedError {
    case cameraPermissionDenied
    case captureDeviceUnavailable
    case captureSessionFailed

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied: return "Camera permission denied. Enable it in Settings."
        case .captureDeviceUnavailable: return "Camera unavailable"
        case .captureSessionFailed: return "Failed to start scanning session"
        }
    }
}


/// 二维码扫描视图
/// 使用 AVFoundation AVCaptureSession 实现，兼容 iOS 15+
struct QRCodeScannerView: View {
    /// 扫描结果回调（扫到即回调并关闭）
    let onScan: (String) -> Void
    /// 错误回调
    let onError: (Error) -> Void
    /// 关闭回调
    let onCancel: () -> Void

    var body: some View {
        QRScannerRepresentable(
            onScan: onScan,
            onError: onError
        )
        .ignoresSafeArea()
        .overlay(scanOverlay)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { onCancel() }
                    .foregroundColor(.white)
            }
        }
        .navigationTitle("Scan QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// 取景框 + 提示文字
    private var scanOverlay: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primaryBrandColor, Color.secondaryBrandColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3,
                        antialiased: true
                    )
                    .frame(width: 240, height: 240)
            }
            .frame(width: 240, height: 240)

            Text("Point camera at QR code")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
    }
}

/// AVCaptureSession 包装器
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onError: (Error) -> Void

        init(onScan: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func scanner(_ scanner: ScannerViewController, didFind code: String) {
            onScan(code)
        }

        func scanner(_ scanner: ScannerViewController, didFail error: Error) {
            onError(error)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func scanner(_ scanner: ScannerViewController, didFind code: String)
    func scanner(_ scanner: ScannerViewController, didFail error: Error)
}

/// 扫码控制器：管理 AVCaptureSession
final class ScannerViewController: UIViewController {
    weak var delegate: ScannerViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.delegate?.scanner(self, didFail: QRCodeScannerError.cameraPermissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            delegate?.scanner(self, didFail: QRCodeScannerError.cameraPermissionDenied)
        @unknown default:
            delegate?.scanner(self, didFail: QRCodeScannerError.cameraPermissionDenied)
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.scanner(self, didFail: QRCodeScannerError.captureDeviceUnavailable)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            guard captureSession.canAddInput(input) else {
                delegate?.scanner(self, didFail: QRCodeScannerError.captureSessionFailed)
                return
            }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(output) else {
                delegate?.scanner(self, didFail: QRCodeScannerError.captureSessionFailed)
                return
            }
            captureSession.addOutput(output)

            output.metadataObjectTypes = [.qr]
            output.setMetadataObjectsDelegate(self, queue: .main)

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        } catch {
            delegate?.scanner(self, didFail: error)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }

        // 震动反馈
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // 停止扫描，避免重复回调
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        delegate?.scanner(self, didFind: code)
    }
}

