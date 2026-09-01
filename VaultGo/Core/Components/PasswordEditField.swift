/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// PasswordEditField.swift
/// created on: 11/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit

struct PasswordEditField: View {
    let placeholder: String
    @Binding var text: String
    var revealDuration: TimeInterval = 2.0

    @State private var isRevealed = false
    @State private var revealTrigger = 0
    @StateObject private var generator = PasswordGeneratorService()

    init(_ placeholder: String = "Password", text: Binding<String>, revealDuration: TimeInterval = 2.0) {
        self.placeholder = placeholder
        self._text = text
        self.revealDuration = revealDuration
    }

    var body: some View {
        HStack(spacing: 10) {
            DelayedSecureTextField(
                placeholder: placeholder,
                text: $text,
                isRevealed: $isRevealed,
                revealDuration: revealDuration,
                revealTrigger: revealTrigger
            )
            .frame(height: 48)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Button {
                generator.generatePassword()
                text = generator.generatedPassword
                revealTrigger &+= 1
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        //.padding(.horizontal, 12)
        //.background(Color(.secondarySystemBackground))
        //.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DelayedSecureTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    let revealDuration: TimeInterval
    let revealTrigger: Int

    func makeUIView(context: Context) -> UITextField {
        let view = UITextField()
        view.placeholder = placeholder
        view.text = text
        // 不使用 .password：避免系统识别为登录表单，在离开/提交页面时弹出"保存密码"提示
        view.textContentType = .oneTimeCode
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.borderStyle = .none
        view.clearButtonMode = .never
        view.isSecureTextEntry = true
        view.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return view
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.applySecureState(to: uiView)
        context.coordinator.applyRevealTrigger(to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: DelayedSecureTextField
        private var workItem: DispatchWorkItem?
        private var isTemporarilyRevealed = false
        private var lastRevealTrigger: Int = 0

        init(parent: DelayedSecureTextField) {
            self.parent = parent
            self.lastRevealTrigger = parent.revealTrigger
        }

        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""

            guard !parent.isRevealed else { return }
            temporarilyReveal(sender)
        }

        func applyRevealTrigger(to textField: UITextField) {
            guard parent.revealTrigger != lastRevealTrigger else { return }
            lastRevealTrigger = parent.revealTrigger

            guard !parent.isRevealed else { return }
            temporarilyReveal(textField)
        }

        func applySecureState(to textField: UITextField) {
            if parent.isRevealed {
                workItem?.cancel()
                workItem = nil
                isTemporarilyRevealed = false
                setSecure(false, textField: textField)
                return
            }

            if isTemporarilyRevealed {
                setSecure(false, textField: textField)
            } else {
                setSecure(true, textField: textField)
            }
        }

        private func temporarilyReveal(_ textField: UITextField) {
            workItem?.cancel()
            isTemporarilyRevealed = true
            setSecure(false, textField: textField)

            let item = DispatchWorkItem { [weak self, weak textField] in
                guard let self, let textField else { return }
                self.isTemporarilyRevealed = false
                guard !self.parent.isRevealed else { return }
                self.setSecure(true, textField: textField)
            }

            workItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + parent.revealDuration, execute: item)
        }

        private func setSecure(_ secure: Bool, textField: UITextField) {
            guard textField.isSecureTextEntry != secure else { return }

            let currentText = textField.text
            let currentSelectedRange = textField.selectedTextRange

            textField.isSecureTextEntry = secure
            textField.text = currentText
            if let currentSelectedRange {
                textField.selectedTextRange = currentSelectedRange
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var password = "Abc123!@#"

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                PasswordEditField("访问密码", text: $password, revealDuration: 2.0)
                Text(password)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

