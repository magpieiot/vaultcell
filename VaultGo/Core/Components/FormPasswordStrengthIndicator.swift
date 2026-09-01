/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// FormPasswordStrengthIndicator.swift
/// created on: 11/06/2026
/// ------------------------------------------------------------------

//
//  FormPasswordStrengthIndicator.swift
//  VaultGo
//
//  Created by gavanwang on 2026/6/11.
//
import SwiftUI

struct FormPasswordStrengthIndicator: View {
    let strength: PasswordStrength
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(index <= strength.rawValue ? strengthColor : Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                }
            }
            
            Text("Password strength: \(strength.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    var strengthColor: Color {
        switch strength {
        case .veryWeak, .weak: return .red
        case .medium: return .yellow
        case .strong, .veryStrong: return .green
        }
    }
}
