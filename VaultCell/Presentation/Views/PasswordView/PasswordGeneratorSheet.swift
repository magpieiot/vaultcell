/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordGeneratorSheet.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI


struct PasswordGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var generatedPassword: String
    @StateObject private var service = PasswordGeneratorService()
    
    var body: some View {
        NavigationStack {
            PasswordGeneratorView(service: service)
                .navigationTitle("Generate Password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Use") {
                            generatedPassword = service.generatedPassword
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}
