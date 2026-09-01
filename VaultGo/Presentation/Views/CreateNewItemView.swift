//
//  CreateNewItemEntry.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/23.
//

import SwiftUI

enum PasswordType: String {
    case login, pin, card, wifi

    var title: String {
        rawValue.capitalized
    }
}

///
struct CreateNewItemView: View {
    @ObservedObject var viewModel: VaultListViewModel
    // 用于导航到更多详情页时显式注入 toast 环境对象（导航 destination 在嵌套 TabView 下环境传播不稳定）
    let toastCenter: ToastCenter
    @State private var selectedPasswordType = PasswordType.login
    @State private var showNextPage = false
    @StateObject private var passwordFormModel: PasswordFormModel
    @StateObject private var bankcardFormModel: BankcardFormModel
    @StateObject private var pincodeFormModel: PincodeFormModel

    @Environment(\.dismiss) private var dismiss

    init(viewModel: VaultListViewModel, toastCenter: ToastCenter) {
        self.viewModel = viewModel
        self.toastCenter = toastCenter
        _passwordFormModel = StateObject(wrappedValue: PasswordFormModel())
        _bankcardFormModel = StateObject(
            wrappedValue: BankcardFormModel(referenceData: viewModel.referenceData)
        )
        _pincodeFormModel = StateObject(
            wrappedValue: PincodeFormModel(referenceData: viewModel.referenceData)
        )
    }

    var body: some View {
        VStack {
            Picker("", selection: $selectedPasswordType) {
                Text(PasswordType.login.title)
                    .tag(PasswordType.login)
                Text(PasswordType.pin.title)
                    .tag(PasswordType.pin)
                Text(PasswordType.card.title)
                    .tag(PasswordType.card)
                Text(PasswordType.wifi.title)
                    .tag(PasswordType.wifi)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            .padding(.vertical, 8)

            TabView(selection: $selectedPasswordType) {
                AddPasswordTitleView(
                    formModel: passwordFormModel,
                    viewModel: viewModel,
                    toastCenter: toastCenter
                )
                .tag(PasswordType.login)

                PincodeFormView(formModel: pincodeFormModel) { entry in
                    let repo = PincodeRepository()
                    try await repo.save(entry)
                    // 记录最近使用的标签
                    TagStore.addTags(entry.tags ?? [])
                    // 保存成功后刷新主列表（列表数据 + 过滤器统计），与 Password 保存路径保持一致
                    await viewModel.loadItems()
                }
                .tag(PasswordType.pin)

                AddBankcardView(formModel: bankcardFormModel) { entry in
                    let repo = BankcardRepository()
                    try await repo.save(entry)
                    // 保存成功后刷新主列表（列表数据 + 过滤器统计），与 Password 保存路径保持一致
                    await viewModel.loadItems()
                }
                .tag(PasswordType.card)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))  // 隐藏自带的小圆点

        }
        .navigationBarTitle("New")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showNextPage) {
            AddPasswordMoreDetailView(formModel: passwordFormModel, viewModel: viewModel)
                .environmentObject(toastCenter)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                }
            }
            // TODO: 合并详情页：用户名 + 密码均非空才可进入更多详情
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        switch selectedPasswordType {
                        case .login:
                            showNextPage = true
                            break
                        case .pin:
                            let entry = pincodeFormModel.buildDraftEntry()
                            do {
                                let repo = PincodeRepository()
                                try await repo.save(entry)
                                TagStore.addTags(entry.tags ?? [])
                                await viewModel.loadItems()
                                await MainActor.run { dismiss() }
                            } catch {
                                print("Failed to save pincode: \(error)")
                            }
                            break
                        case .card:
                            let entry = bankcardFormModel.buildDraftEntry()
                            do {
                                let repo = BankcardRepository()
                                try await repo.save(entry)
                                await viewModel.loadItems()
                                await MainActor.run { dismiss() }
                            } catch {
                                print("Failed to save bankcard: \(error)")
                            }

                        default:
                            break
                        }
                    }
                } label: {
                    switch selectedPasswordType {
                    case .login:
                        Image(systemName: "arrow.right")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                    case .pin, .card, .wifi:
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                // login 页合并详情后：用户名 + 密码均非空才可进入更多详情
                .disabled(
                    selectedPasswordType == .login
                        && (passwordFormModel.username.isEmpty
                            || passwordFormModel.password.isEmpty)
                )
            }
        }
    }
}

#Preview {
    let referenceData = ReferenceDataService()
    NavigationStack {
        CreateNewItemView(
            viewModel: VaultListViewModel(referenceData: referenceData),
            toastCenter: ToastCenter()
        )
    }
}
