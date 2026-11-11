/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ThirdPartyLoginView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

struct ThirdPartyLoginView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .radiusXl) {
                    // 说明卡片
                    infoCard

                    // OAuth服务列表
                    servicesSection

                    // 已连接的服务
                    connectedServicesSection
                }
                .padding()
            }
            .navigationTitle("Third-Party Login")
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: .radiusMd) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Third-Party Credentials")
                    .font(.headline)
            }

            Text(
                "Securely manage your third-party service credentials via OAuth 2.0 — no manual password entry needed."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        //.background(Color(.systemBackground))
        .cornerRadius(.radiusLg)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: .radiusMd) {
            Text("Supported Platforms")
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: .radiusMd
            ) {
                OAuthServiceButton(name: "Google", icon: "globe", color: .secondary)
                OAuthServiceButton(
                    name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", color: .secondary)
                OAuthServiceButton(name: "Apple", icon: "apple.logo", color: .secondary)
                OAuthServiceButton(name: "Microsoft", icon: "square.grid.2x2", color: .secondary)
                OAuthServiceButton(name: "Facebook", icon: "person.2.fill", color: .secondary)
                OAuthServiceButton(name: "Twitter", icon: "at", color: .secondary)
            }
        }
    }

    private var connectedServicesSection: some View {
        VStack(alignment: .leading, spacing: .radiusMd) {
            Text("Connected Services")
                .font(.headline)

            // 已连接的服务列表
            VStack(spacing: .radiusMd) {
                ConnectedServiceRow(
                    name: "Google",
                    email: "user@gmail.com",
                    icon: "globe",
                    color: .secondary
                )

                ConnectedServiceRow(
                    name: "GitHub",
                    email: "username",
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: .secondary
                )
            }
        }
    }
}

struct OAuthServiceButton: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        Button(action: {}) {
            VStack(spacing: .radiusSm) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(color)

                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .radiusLg)
            //.background(Color(.systemBackground))
            .cornerRadius(.radiusMd)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ConnectedServiceRow: View {
    let name: String
    let email: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: .radiusMd) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: .radiusSm) {
                Text(name)
                    .font(.headline)

                Text(email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {}) {
                Text("Disconnect")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        //.background(Color(.systemBackground))
        .cornerRadius(.radiusMd)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}
