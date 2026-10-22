/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// QRCodeScannerView.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import AVFoundation
import UIKit

enum QRCodeScannerError: Error, LocalizedError {
    case captureDeviceUnavailable
    case captureSessionFailed

    var errorDescription: String? {
        switch self {
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
    /// 错误回调（仅采集设备/会话类错误；相机权限问题在页面内就地提示，不再回调给调用方）
    let onError: (Error) -> Void
    /// 关闭回调
    let onCancel: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    /// 相机授权状态。每次进入页面、回到前台都重新读取，
    /// 所以用户在系统设置里关掉相机权限后再点「扫描二维码」，会看到明确的授权提示
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// 防止重复发起系统授权弹窗
    @State private var isRequestingAccess = false

    var body: some View {
        Group {
            switch authStatus {
            case .authorized:
                scannerContent
            case .notDetermined:
                requestingContent
            case .denied, .restricted:
                permissionDeniedContent
            @unknown default:
                permissionDeniedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Scan QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { onCancel() }
                    .foregroundColor(.white)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            syncAuthorizationStatus(requestIfNeeded: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 用户去「设置」改完权限回到 App：已开启则立刻开始扫描，被关闭则就地提示
            guard newPhase == .active else { return }
            syncAuthorizationStatus(requestIfNeeded: true)
        }
    }

    /// 取景控件（仅在已授权时创建，避免权限被关闭后仍白屏无反馈）
    private var scannerContent: some View {
        QRScannerRepresentable(
            onScan: onScan,
            onError: onError
        )
        .ignoresSafeArea()
        .overlay(scanOverlay)
    }

    /// 等待系统授权结果
    private var requestingContent: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
    }

    /// 相机权限被关闭/受限时的说明 + 跳转系统设置
    private var permissionDeniedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.white.opacity(0.8))

            Text("Camera Access Required")
                .font(.headline)
                .foregroundColor(.white)

            Text("Camera access is turned off. Enable it in Settings to scan QR codes.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 32)

            Button {
                openSystemSettings()
            } label: {
                Text("Open Settings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.primaryBrandColor))
            }
            .padding(.top, 4)
        }
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

    /// 读取并同步相机授权状态；未决定时发起一次系统授权
    private func syncAuthorizationStatus(requestIfNeeded: Bool) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus != status {
            authStatus = status
        }

        guard requestIfNeeded, status == .notDetermined, !isRequestingAccess else { return }

        isRequestingAccess = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                isRequestingAccess = false
                authStatus = granted ? .authorized : .denied
            }
        }
    }

    /// 跳转系统设置页，用户可在此重新开启相机权限
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
    /// 会话是否已配置完成，避免 viewDidAppear 多次触发时重复添加 input/output
    private var isSessionConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    /// 授权判断已上移到 QRCodeScannerView（未授权时不会创建本控制器）。
    /// 这里在视图真正显示后再建会话并启动，避免在弹窗展示过程中同步回调 SwiftUI 状态。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureSessionIfNeeded()
        startRunningIfNeeded()
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }

        guard let device = AVCaptureDevice.default(for: .video) else {
            notifyFailure(QRCodeScannerError.captureDeviceUnavailable)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            guard captureSession.canAddInput(input) else {
                notifyFailure(QRCodeScannerError.captureSessionFailed)
                return
            }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(output) else {
                notifyFailure(QRCodeScannerError.captureSessionFailed)
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

            isSessionConfigured = true
        } catch {
            notifyFailure(error)
        }
    }

    private func startRunningIfNeeded() {
        guard isSessionConfigured, !captureSession.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    /// 错误统一异步回到主线程投递，避免在 SwiftUI 构建/展示阶段同步改状态导致弹窗状态错乱
    private func notifyFailure(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.scanner(self, didFail: error)
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

