/// ------------------------------------------------------------------
/// Copyright © 2026 Gavan Wang. All rights reserved.
/// Project: VaultCell
/// VaultSearchView.swift
/// created on: 08/07/2026
/// ------------------------------------------------------------------

import SwiftUI

struct VaultSearchView: View {
    @StateObject private var viewModel: VaultSearchViewModel
    @FocusState private var isSearchFocused: Bool

    init(listViewModel: VaultListViewModel) {
        _viewModel = StateObject(wrappedValue: VaultSearchViewModel(listViewModel: listViewModel))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                content
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(SearchBackground())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .preference(key: TabBarVisibilityKey.self, value: true)
        .task {
            isSearchFocused = true
            await viewModel.loadItemsIfNeeded()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(isSearchFocused ? .primaryBrandColor : .secondary)

            TextField("Search passwords, PINs, bank cards...", text: $viewModel.query)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    viewModel.commitSearch()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.7))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSearchFocused ? Color.primaryBrandColor : Color.clear, lineWidth: 2)
        }
        .shadow(color: isSearchFocused ? .primaryBrandColor.opacity(0.12) : .clear, radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.query.isEmpty {
            historySection
        } else if viewModel.isLoading {
            loadingView
        } else if viewModel.results.isEmpty {
            noResultsView
        } else {
            resultsList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBrandColor))
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            // 渐变图标圆，复用 Onboarding 语言
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.primaryBrandColor.opacity(0.15), .clear]),
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.primaryBrandColor, .secondaryBrandColor]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: .primaryBrandColor.opacity(0.3), radius: 14, y: 8)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("No Results Found")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Try a different keyword or check your spelling.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Search History")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if !viewModel.history.isEmpty {
                    Button("Clear") {
                        viewModel.clearHistory()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.errorColor)
                }
            }
            .padding(.top, 8)

            if viewModel.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No Search History")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                // 胶囊标签式历史
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.history, id: \.self) { query in
                        historyTag(for: query)
                    }
                }
            }
        }
    }

    private func historyTag(for query: String) -> some View {
        Button {
            viewModel.selectHistory(query)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(query)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeHistory(query)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Search Results

    private var resultsList: some View {
        LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
            ForEach(viewModel.groupedResults, id: \.type) { group in
                Section {
                    ForEach(group.items) { item in
                        resultRow(for: item)
                    }
                } header: {
                    resultHeader(for: group)
                }
            }
        }
        .padding(.top, 8)
    }

    private func resultHeader(for group: (type: VaultItemType, items: [VaultItem])) -> some View {
        HStack {
            Image(systemName: group.type.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryBrandColor)

            Text(group.type.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)

            Spacer()

            Text("\(group.items.count)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primaryBrandColor.opacity(0.8)))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func resultRow(for item: VaultItem) -> some View {
        Button {
            viewModel.listViewModel.openDetail(for: item)
        } label: {
            VaultItemRow(item: item, category: viewModel.listViewModel.category(for: item.categoryID))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 浅色柔和背景

private struct SearchBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.99, green: 0.995, blue: 1.0),
                Color.primaryBrandColor.opacity(0.08),
                Color.secondaryBrandColor.opacity(0.05),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Helpers

private extension VaultItemType {
    var displayName: String {
        switch self {
        case .password:
            return String(localized: "Password")
        case .pincode:
            return String(localized: "Pincode")
        case .bankcard:
            return String(localized: "BankCard")
        }
    }

    var iconName: String {
        switch self {
        case .password:
            return "key.horizontal.fill"
        case .pincode:
            return "lock.fill"
        case .bankcard:
            return "creditcard.fill"
        }
    }
}

private extension View {
    func applyScrollDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *) {
            return self.scrollDismissesKeyboard(.interactively)
        } else {
            return self
        }
    }
}
