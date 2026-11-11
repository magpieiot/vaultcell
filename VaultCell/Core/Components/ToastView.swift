///------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ToastStyle.swift
/// created on: 23/06/2026
/// ------------------------------------------------------------------

import SwiftUI

// MARK: - 1. 数据模型与样式定义

/// Toast 的样式类型
enum ToastStyle {
    case success, error, warning, info
    
    var themeColor: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Toast 数据模型
struct ToastItem: Equatable {
    let id = UUID() // 确保每次创建都是唯一的，方便触发 onChange
    let message: String
    let style: ToastStyle
    let duration: Double
    /// 非 nil 时附带剪贴板清除倒计时（秒），普通提示为 nil
    let clipboardClearAfter: TimeInterval?
    let createdAt: Date

    init(message: String, style: ToastStyle = .info, duration: Double = 2.0,
         clipboardClearAfter: TimeInterval? = nil) {
        self.message = message
        self.style = style
        self.duration = duration
        self.clipboardClearAfter = clipboardClearAfter
        self.createdAt = Date()
    }

    /// 复制反馈：文案与细线进度都取自真实的剪贴板清除时长，避免各处自造提示
    static func copied(clearAfter seconds: TimeInterval) -> ToastItem {
        guard seconds > 0 else {
            return ToastItem(message: AppLocale.string("Copied"), style: .success)
        }
        let message = String(
            format: AppLocale.string("Copied · clipboard clears in %lld s"), Int(seconds))
        return ToastItem(
            message: message, style: .success, duration: 3.0, clipboardClearAfter: seconds)
    }
}

@MainActor
final class ToastCenter: ObservableObject {
    /// 全 App 共用一份：根视图、子页与模态切换时反馈不丢失
    static let shared = ToastCenter()

    @Published var toast: ToastItem?
    /// 已挂载 `toastHost` 的模态数量；大于 0 时根级显示层让位给模态内显示层
    @Published private(set) var modalHosts = 0

    func addModalHost() { modalHosts += 1 }
    func removeModalHost() { modalHosts = max(0, modalHosts - 1) }
}

// MARK: - 2. Toast UI 视图

/// Toast 的具体 UI 展现
struct ToastView: View {
    let item: ToastItem

    var body: some View {
        Group {
            if let total = item.clipboardClearAfter, total > 0 {
                clipboardBody(total: total)
            } else {
                normalBody
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial) // 原生毛玻璃效果
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 40) // 限制最大宽度，防止文字太长撑满屏幕
    }

    private var normalBody: some View {
        HStack(spacing: 12) {
            Image(systemName: item.style.icon)
                .foregroundColor(item.style.themeColor)
                .font(.title2)

            Text(item.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
    }

    /// 复制反馈：文案按秒递减，细线按真实剩余比例缩短，和剪贴板定时清除保持一致
    private func clipboardBody(total: TimeInterval) -> some View {
        TimelineView(.periodic(from: item.createdAt, by: 1)) { context in
            let remaining = max(0, total - context.date.timeIntervalSince(item.createdAt))
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: item.style.icon)
                        .foregroundColor(item.style.themeColor)
                        .font(.title2)

                    Text(String(
                        format: AppLocale.string("Copied · clipboard clears in %lld s"),
                        Int(remaining.rounded(.up))))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: proxy.size.width * min(1, remaining / total))
                    }
                }
                .frame(height: 2)
            }
        }
    }
}

// MARK: - 3. 核心逻辑修饰符 (ViewModifier)

/// 管理 Toast 显示、动画、自动消失和键盘避让的修饰符
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastItem?
    /// 已有模态显示层接管时，根级不重复渲染
    var isSuppressed: Bool = false

    @State private var dismissTask: Task<Void, Never>?
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // 如果有 toast，则显示在 ZStack 的最上层（屏幕中间）
            if let currentToast = toast, !isSuppressed {
                ToastView(item: currentToast)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(999)
                    // 键盘避让：当键盘弹起时，将 Toast 向上偏移
                    .offset(y: keyboardHeight > 0 ? -(keyboardHeight / 2.5) : 0)
                    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toast?.id)
        .onChange(of: toast) { oldValue, newValue in
            // 1. 取消之前的自动消失任务
            dismissTask?.cancel()
            
            // 2. 如果有新 toast，启动自动消失任务并触发无障碍播报
            if let value = newValue {
                // 无障碍支持：让 VoiceOver 读出提示内容；模态接管时由模态层播报
                if !isSuppressed {
                    UIAccessibility.post(notification: .announcement, argument: value.message)
                }
                
                dismissTask = Task {
                    let nanoseconds = UInt64(value.duration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    
                    if !Task.isCancelled {
                        await MainActor.run {
                            // 确保只隐藏当前的 toast
                            if toast?.id == value.id {
                                toast = nil
                            }
                        }
                    }
                }
            }
        }
        // 监听键盘弹出
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            if let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        // 监听键盘收起
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }
}

// MARK: - 4. View 扩展 (提供优雅的调用方式)

extension View {
    /// 挂载 Toast 组件
    /// - Parameter toast: 绑定的 ToastItem 状态
    /// - Returns: 添加了 Toast 功能的 View
    func toast(_ toast: Binding<ToastItem?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }

    /// WindowGroup 根级挂载：全 App 共用一份 ToastCenter
    func toastRoot(_ center: ToastCenter = .shared) -> some View {
        modifier(ToastRootModifier(center: center))
    }

    /// 模态（sheet / fullScreenCover）内容挂载：让 Toast 浮在模态之上
    func toastHost(_ center: ToastCenter = .shared) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

/// 根级显示层：模态弹出期间让位，避免同一条 Toast 出现两次
struct ToastRootModifier: ViewModifier {
    @ObservedObject var center: ToastCenter

    func body(content: Content) -> some View {
        content.modifier(
            ToastModifier(toast: $center.toast, isSuppressed: center.modalHosts > 0))
    }
}

/// 模态内显示层：出现时接管 Toast 显示，消失后交还根级
struct ToastHostModifier: ViewModifier {
    @ObservedObject var center: ToastCenter

    func body(content: Content) -> some View {
        content
            .modifier(ToastModifier(toast: $center.toast))
            .onAppear { center.addModalHost() }
            .onDisappear { center.removeModalHost() }
    }
}

// MARK: - 5. 使用示例与预览

struct ToastExampleView: View {
    @State private var currentToast: ToastItem?
    @State private var inputText: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Enter test text", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Button("Show Success Toast") {
                    currentToast = ToastItem(message: "Password saved locally!", style: .success)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("Show Error Toast") {
                    currentToast = ToastItem(message: "Network connection failed. Check your settings.", style: .error, duration: 3.0)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Button("Rapid Tap Test") {
                    // 测试连续触发时，旧的会被立刻替换并重新计时
                    currentToast = ToastItem(message: "Too many actions. Please try again later.", style: .warning, duration: 1.5)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Toast Test")
        }
        // 在根视图或需要显示 Toast 的视图上挂载修饰符
        .toast($currentToast)
    }
}

// Xcode 预览
#Preview {
    ToastExampleView()
}
