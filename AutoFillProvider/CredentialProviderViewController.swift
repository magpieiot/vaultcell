/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// CredentialProviderViewController.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import AuthenticationServices
import UIKit
import SwiftUI

@available(iOS 17.0, *)
class CredentialProviderViewController: ASCredentialProviderViewController {
    
    private var hostingController: UIHostingController<CredentialListView>?
    
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let rootView = CredentialListView(
            serviceIdentifiers: serviceIdentifiers,
            onSelect: { [weak self] credential in
                self?.provideCredential(credential)
            },
            onCancel: { [weak self] in
                self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
            }
        )
        
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController
        
        addChild(hostingController)
        guard let hostView = hostingController.view else {
            return
        }
        hostView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostView)
        
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
    
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        // 无用户交互提供凭证
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // 尝试使用生物识别
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解锁密码库") { success, error in
                if success {
                    // 获取凭证并提供
                    if let credential = self.findCredential(for: credentialRequest) {
                        self.provideCredential(credential)
                    } else {
                        self.extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
                    }
                } else {
                    // 需要用户交互
                    self.extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
                }
            }
        } else {
            self.extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
        }
    }
    
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        // 准备提供凭证的界面
        let credential = findCredential(for: credentialRequest)
        if let credential = credential {
            provideCredential(credential)
        } else {
            self.extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
        }
    }
    
    override func prepareInterfaceForExtensionConfiguration() {
        // 配置扩展
    }
    
    private func provideCredential(_ credential: ASPasswordCredential) {
        self.extensionContext.completeRequest(withSelectedCredential: credential)
    }
    
    private func findCredential(for request: ASCredentialRequest) -> ASPasswordCredential? {
        // 从Keychain查找匹配的凭证
        
        // 查找对应的密码
        // 这里应该从共享的Keychain或App Group中获取
        return nil
    }
}

@available(iOS 17.0, *)
struct CredentialListView: View {
    let serviceIdentifiers: [ASCredentialServiceIdentifier]
    let onSelect: (ASPasswordCredential) -> Void
    let onCancel: () -> Void
    
    @State private var credentials: [CredentialItem] = []
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List(filteredCredentials) { credential in
                Button(action: {
                    selectCredential(credential)
                }) {
                    HStack(spacing: 0.0) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading) {
                            Text(credential.siteName)
                                .font(.headline)
                            
                            Text(credential.username)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "搜索密码")
            .navigationTitle("选择密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
            .onAppear {
                loadCredentials()
            }
        }
    }
    
    private var filteredCredentials: [CredentialItem] {
        if searchText.isEmpty {
            return credentials
        } else {
            return credentials.filter { credential in
                credential.siteName.localizedCaseInsensitiveContains(searchText) ||
                credential.username.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func loadCredentials() {
        // 从Keychain或App Group加载凭证
    }
    
    private func selectCredential(_ credential: CredentialItem) {
        let passwordCredential = ASPasswordCredential(
            user: credential.username,
            password: credential.password
        )
        onSelect(passwordCredential)
    }
}

struct CredentialItem: Identifiable, Codable {
    let id: UUID
    let siteName: String
    let siteURL: String
    let username: String
    let password: String
}

import LocalAuthentication
