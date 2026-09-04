/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// PasswordGeneratorView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI
import UIKit

struct PasswordGeneratorView: View {
    @ObservedObject var service: PasswordGeneratorService
    @State private var showCopied = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                passwordDisplay
                actionButtons
                settingsSection
                Spacer()
            }
            .padding()
        }
    }
    
    private var passwordDisplay: some View {
        VStack(spacing: 16) {
            Text(service.generatedPassword)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            
            FormPasswordStrengthIndicator(strength: PasswordStrength.calculate(for: service.generatedPassword))
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: copyPassword) {
                VStack(spacing: 8) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.title2)
                    Text("Copy")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            Button(action: {
                service.generatePassword()
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                    Text("Refresh")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var settingsSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password Length")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(service.length))")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                Slider(value: $service.length, in: 8...32, step: 1) {
                    Text("Length")
                }
                .onChange(of: service.length) { _, _ in
                    service.generatePassword()
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Uppercase (A-Z)", isOn: $service.includeUppercase)
                    .onChange(of: service.includeUppercase) { _, _ in
                        service.generatePassword()
                    }
                
                Toggle("Lowercase (a-z)", isOn: $service.includeLowercase)
                    .onChange(of: service.includeLowercase) { _, _ in
                        service.generatePassword()
                    }
                
                Toggle("Numbers (0-9)", isOn: $service.includeNumbers)
                    .onChange(of: service.includeNumbers) { _, _ in
                        service.generatePassword()
                    }
                
                Toggle("Symbols (!@#$%^&*)", isOn: $service.includeSymbols)
                    .onChange(of: service.includeSymbols) { _, _ in
                        service.generatePassword()
                    }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func copyPassword() {
        UIPasteboard.general.string = service.generatedPassword
        showCopied = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}
