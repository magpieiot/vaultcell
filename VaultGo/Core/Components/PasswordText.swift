/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// PasswordText.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 密码文本显示控件
/// 类似 Text，但按字符类型（字母 / 数字 / 符号）分别着色。
///
/// 用法：
/// ```swift
/// PasswordText("Abc123!@#")
/// PasswordText("Abc123!@#", size: 20)
///     .letterColor(.white)
///     .digitColor(.yellow)
///     .symbolColor(.pink)
///     .backgroundColor(Color.black)
/// ```
struct PasswordText: View {
    private let password: String
    private var uiFont: Font
    private var uiSize: CGFloat?
    private var letterColor: Color
    private var digitColor: Color
    private var symbolColor: Color
    private var backgroundColor: Color

    init(
        _ password: String,
        font: Font = .system(.body, design: .monospaced),
        size: CGFloat? = nil,
        letterColor: Color = .white,
        digitColor: Color = .yellow,
        symbolColor: Color = .pink,
        backgroundColor: Color = .clear
    ) {
        self.password = password
        self.uiFont = font
        self.uiSize = size
        self.letterColor = letterColor
        self.digitColor = digitColor
        self.symbolColor = symbolColor
        self.backgroundColor = backgroundColor
    }

    private var displayFont: Font {
        if let uiSize {
            return .system(size: uiSize, design: .monospaced)
        }
        return uiFont
    }

    private var attributedPassword: AttributedString {
        var result = AttributedString()
        for char in password {
            var attributedChar = AttributedString(String(char))
            attributedChar.foregroundColor = color(for: char)
            result.append(attributedChar)
        }
        return result
    }

    private func color(for char: Character) -> Color {
        if char.isLetter {
            return letterColor
        } else if char.isNumber {
            return digitColor
        } else {
            return symbolColor
        }
    }

    var body: some View {
        Text(attributedPassword)
            .font(displayFont)
            .background(backgroundColor)
    }
}

// MARK: - 链式修饰符

extension PasswordText {
    func font(_ font: Font) -> PasswordText {
        var copy = self
        copy.uiFont = font
        return copy
    }

    func size(_ size: CGFloat) -> PasswordText {
        var copy = self
        copy.uiSize = size
        return copy
    }

    func letterColor(_ color: Color) -> PasswordText {
        var copy = self
        copy.letterColor = color
        return copy
    }

    func digitColor(_ color: Color) -> PasswordText {
        var copy = self
        copy.digitColor = color
        return copy
    }

    func symbolColor(_ color: Color) -> PasswordText {
        var copy = self
        copy.symbolColor = color
        return copy
    }

    func backgroundColor(_ color: Color) -> PasswordText {
        var copy = self
        copy.backgroundColor = color
        return copy
    }
}

// MARK: - 预览

#Preview("默认配色") {
    PasswordText("Abc123!@#XyZ")
        .padding()
}

#Preview("自定义配色") {
    VStack(spacing: 16) {
        PasswordText("P@ssw0rd!2024", size: 24)
            .letterColor(.white)
            .digitColor(Color.successColor)
            .symbolColor(Color.errorColor)

        PasswordText("aB3$kL9*mN", size: 18)
            .letterColor(Color.primaryBrandColor)
            .digitColor(Color.warningColor)
            .symbolColor(Color.secondaryBrandColor)

        PasswordText("ZxCv1234!@#$", size: 32)
            .letterColor(.white)
            .digitColor(.yellow)
            .symbolColor(.pink)
            .backgroundColor(Color.black.opacity(0.8))
    }
    .padding()
}

#Preview("暗色模式") {
    VStack(spacing: 16) {
        PasswordText("SecureP@ss1", size: 22)
        PasswordText("Hello#World42", size: 16)
    }
    .padding()
    .preferredColorScheme(.dark)
}
