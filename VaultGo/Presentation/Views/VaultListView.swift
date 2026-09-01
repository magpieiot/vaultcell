import SwiftUI

enum VaultListFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case password = "password"
    case pincode = "pincode"
    case bankcard = "bankcard"
    //case wifikey = "wifikey"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .password:
            return String(localized: "Password")
        case .pincode:
            return String(localized: "Pincode")
        case .bankcard:
            return String(localized: "BankCard")
        //case .wifikey:
        //    return "WiFiKey"
        }
    }

    /// 该过滤项对应的 VaultItemType 集合（.all 表示不限制类型）
    var itemTypes: Set<VaultItemType> {
        switch self {
        case .all:
            return Set(VaultItemType.allCases)
        case .password:
            return [.password]
        case .pincode:
            return [.pincode]
        case .bankcard:
            return [.bankcard]
        }
    }

    /// 根据已选类型集合匹配对应的过滤项；匹配不到（如自定义组合）时返回 nil
    static func filter(matching types: Set<VaultItemType>) -> VaultListFilter? {
        allCases.first { $0.itemTypes == types }
    }
}

@MainActor
struct VaultListView: View {
    //@StateObject private var viewModel: VaultListViewModel

    @State private var showingLoadError = false

    /// 是否允许左滑条目显示 Delete 按钮（在设置中切换）
    @AppStorage(VaultKey.allowSwipeDeleteInVaultList) private var allowSwipeDeleteInVaultList = true

    @EnvironmentObject var viewModel: VaultListViewModel

    private let securityAuditService = VaultSecurityAuditService()

    private var securityAudit: VaultSecurityAudit {
        securityAuditService.calculate(entries: viewModel.passwordEntriesForAudit)
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Vault")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: viewModel.searchQuery) { _, newValue in
                    Task {
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await viewModel.loadItems()
                        } else {
                            await viewModel.searchItems()
                        }
                    }
                }
                .onChange(of: viewModel.errorMessage) { _, newValue in
                    showingLoadError = (newValue != nil)
                }
                .alert("Loading Failed", isPresented: $showingLoadError) {
                    Button("OK", role: .cancel) {
                        showingLoadError = false
                    }
                    Button("Clear") {
                        viewModel.errorMessage = nil
                        showingLoadError = false
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }

                .toolbar {
                    toolbarContent
                }
                .navigationDestination(item: $viewModel.selectedDestination) { destination in
                    destinationView(for: destination)
                }
        }
    }

    private var mainContent: some View {
        ZStack {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading...")
            } else if viewModel.items.isEmpty {
                VaultEmptyStateView()
            } else {
                // 只要存在条目就始终渲染列表（含过滤器 StatBar header），
                // 过滤结果为空时在列表内展示无结果提示，保证过滤器仍可操作。
                vaultListContent
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink {
                SecurityScoreDetailView(viewModel: viewModel, audit: securityAudit)
            } label: {
                SecurityScoreBadge(score: securityAudit.vaultScore)
            }
            .buttonStyle(.borderedProminent)  // 自带填充背景
            .buttonBorderShape(.capsule)
            .tint(SecurityScoreBadge.backgroundColor(for: securityAudit.vaultScore))
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            NavigationLink {
                VaultSearchView(listViewModel: viewModel)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
            }
        }
    }

    private var vaultListContent: some View {
        List {

            Section {
                if viewModel.filteredItems.isEmpty {
                    VaultNoResultsView()
                } else {
                    ForEach(viewModel.filteredItems) { item in
                        Button {
                            ///
                            viewModel.openDetail(for: item)
                        } label: {
                            VaultItemRow(item: item, category: viewModel.category(for: item.categoryID))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                            Button {
                                Task { await viewModel.toggleFavorite(item) }
                            } label: {
                                Label(
                                    item.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: item.isFavorite ? "star.slash" : "star")
                            }
                            .tint(item.isFavorite ? .secondary : .yellow)

                            if allowSwipeDeleteInVaultList {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            } header: {
                vaultStatBarSection
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
    }

    /// 排序菜单：字段（创建时间 / 更新时间 / 标题）+ 升降序，与过滤器并行生效
    private var sortMenu: some View {
        let isSortActive = viewModel.sortField != .updatedAt || viewModel.sortAscending != false

        return Menu {
            Picker("Sort By", selection: $viewModel.sortField) {
                Label("Created Date", systemImage: "calendar")
                    .tag(VaultSortField.createdAt)
                Label("Updated Date", systemImage: "clock")
                    .tag(VaultSortField.updatedAt)
                Label("Title", systemImage: "textformat")
                    .tag(VaultSortField.title)
            }

            Divider()

            Picker("Order", selection: $viewModel.sortAscending) {
                Label("Ascending", systemImage: "arrow.up")
                    .tag(true)
                Label("Descending", systemImage: "arrow.down")
                    .tag(false)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title)
                .foregroundColor(isSortActive ? Color.blue : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // 与上方工具带背景保持一致（模仿 vaultStatBarSection 的 systemBackground）
                .background(Color(.systemBackground).opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    /// 条目统计：全部/密码/PIN/银行卡数量
    private var itemCounts: (total: Int, password: Int, pincode: Int, bankcard: Int) {
        var password = 0
        var pincode = 0
        var bankcard = 0
        for item in viewModel.items {
            switch item {
            case .password: password += 1
            case .pincode: pincode += 1
            case .bankcard: bankcard += 1
            }
        }
        return (password + pincode + bankcard, password, pincode, bankcard)
    }

    /// 顶部工具带：横向滚动的统计过滤胶囊 + 悬浮在右侧的排序按钮（ZStack 叠放）。
    /// 作为 section header 随列表滚动，plain 样式下 sticky 吸附在导航栏下缘。
    private var vaultStatBarSection: some View {
        ZStack(alignment: .trailing) {
            VaultStatBar(
                counts: itemCounts,
                currentFilter: VaultListFilter.filter(matching: viewModel.selectedTypes) ?? .all,
                onSelect: { filter in
                    viewModel.selectedTypes = filter.itemTypes
                }
            )
            // 为右侧悬浮按钮留出空间，避免胶囊被遮挡
            //.padding(.trailing, 48)

            sortMenu
        }
        .listRowSeparator(.hidden)
        // 不透明背景：plain 样式 header 默认透明，sticky 时
        // 滚动内容会从胶囊间隙透出，这里整行铺底色遮住。
        .listRowBackground(Color(.systemBackground))
        // 与导航栏的间距由系统默认控制；如需压缩可把 top 改为负值。
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    /*
    private var vaultSummarySection: some View {
        HStack(spacing: 12) {
            Button {
                // 打开安全审核详情
                print("Open Security Issues View")
            } label: {
                SecretCardView(
                    secretScore: securityAudit.vaultScore, note: "Security Score", height: 120
                )
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                HCardView(
                    title: "\(viewModel.filteredItems.count)",
                    desc: "Entries",
                    height: 56,
                    backgroundColor: Color.mistyBlueBackground,
                    titleColor: Color.mistyBlueForeground
                )

                HCardView(
                    title: "\(viewModel.filteredItems.count)",
                    desc: "Entries",
                    height: 56,
                    backgroundColor: Color.mistyBlueBackground,
                    titleColor: Color.mistyBlueForeground
                )

            }
            .frame(maxWidth: .infinity)

        }
        .padding(.horizontal, 16)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
    }
    */

    @ViewBuilder
    private func destinationView(for destination: VaultDestination) -> some View {
        switch destination {
        case .passwordDetail(let id):
            if let entry = passwordEntry(for: id) {
                PasswordDetailView(entry: entry, viewModel: viewModel, audit: securityAudit)
            } else {
                VaultPlaceholderDetailView(title: "Password")
            }
        case .pincodeDetail(let id):
            if let entry = pincodeEntry(for: id) {
                PincodeDetailView(
                    entry: entry,
                    onUpdate: { [weak viewModel] updatedEntry in
                        await viewModel?.updatePincodeItem(updatedEntry)
                    },
                    onDelete: { [weak viewModel] deletedEntry in
                        await viewModel?.deletePincodeItem(deletedEntry)
                    },
                    tagSelection: viewModel.tagSelection,
                    referenceData: viewModel.referenceData
                )
            } else {
                VaultPlaceholderDetailView(title: "Pincode")
            }
        case .bankcardDetail(let id):
            if let entry = bankcardEntry(for: id) {
                BankcardDetailView(
                    entry: entry,
                    categories: viewModel.categories,
                    onUpdate: { [weak viewModel] updatedEntry in
                        await viewModel?.updateBankcardItem(updatedEntry)
                    },
                    onDelete: { [weak viewModel] deletedEntry in
                        await viewModel?.deleteBankcardItem(deletedEntry)
                    },
                    referenceData: viewModel.referenceData
                )
            } else {
                VaultPlaceholderDetailView(title: "BankCard")
            }
        }
    }

    private func passwordEntry(for id: UUID) -> PasswordEntry? {
        for item in viewModel.items {
            guard item.id == id else { continue }
            if case .password(let entry) = item {
                return entry
            }
        }
        return nil
    }

    private func pincodeEntry(for id: UUID) -> PincodeEntry? {
        for item in viewModel.items {
            guard item.id == id else { continue }
            if case .pincode(let entry) = item {
                return entry
            }
        }
        return nil
    }

    private func bankcardEntry(for id: UUID) -> BankcardEntry? {
        for item in viewModel.items {
            guard item.id == id else { continue }
            if case .bankcard(let entry) = item {
                return entry
            }
        }
        return nil
    }
}

// MARK: - 安全评分徽标
/// 颜色规则与 SecretCardView 保持一致：分数越高越绿，越低越红
private struct SecurityScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(Self.clampedScore(score))")
            .font(.title3.bold())
            .foregroundColor(Self.titleColor(for: score))
        //·.padding(.horizontal, 8)
        //.padding(.vertical, 4)
        //.background(Capsule().fill(Self.backgroundColor(for: score)))
    }

    static func clampedScore(_ score: Int) -> Int {
        min(max(score, 0), 100)
    }

    static func hue(for score: Int) -> Double {
        0.33 * (Double(clampedScore(score)) / 100)
    }

    static func backgroundColor(for score: Int) -> Color {
        Color(hue: hue(for: score), saturation: 0.22, brightness: 0.95)
    }

    static func titleColor(for score: Int) -> Color {
        Color(hue: hue(for: score), saturation: 0.72, brightness: 0.68)
    }
}

private struct VaultEmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "No Items Yet",
            systemImage: "tray",
            description: Text("Use the create flow to add your first vault item.")
        )
    }
}

private struct VaultNoResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Matching Items")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Try a different search or adjust your filters.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

private struct VaultFilterHeader: View {
    @ObservedObject var viewModel: VaultListViewModel

    /// 当前生效的过滤项：始终与 viewModel.selectedTypes 保持同步（如 clearFilters 后回到 .all）
    private var currentFilter: VaultListFilter {
        VaultListFilter.filter(matching: viewModel.selectedTypes) ?? .all
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VaultListFilter.allCases) { filter in
                    filterChip(for: filter)
                }
            }
        }
    }

    /// 单个过滤胶囊按钮：点击后更新 viewModel.selectedTypes 触发列表过滤
    private func filterChip(for filter: VaultListFilter) -> some View {
        let isSelected = currentFilter == filter
        return Button {
            viewModel.selectedTypes = filter.itemTypes
        } label: {
            Text(filter.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 单行横向统计条：图标 + 数量，点击胶囊即过滤（概览即导航）
private struct VaultStatBar: View {
    let counts: (total: Int, password: Int, pincode: Int, bankcard: Int)
    let currentFilter: VaultListFilter
    let onSelect: (VaultListFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statChip(
                    filter: .all, icon: "lock.shield.fill", count: counts.total,
                    color: .primaryBrandColor)
                statChip(
                    filter: .password, icon: "key.horizontal.fill", count: counts.password,
                    color: .blue)
                statChip(
                    filter: .pincode, icon: "number.square.fill", count: counts.pincode,
                    color: .orange)
                statChip(
                    filter: .bankcard, icon: "creditcard.fill", count: counts.bankcard,
                    color: .green)
            }
        }
        //.padding(.top, -8)
    }

    /// 单个统计胶囊：选中态与列表过滤器保持一致
    private func statChip(
        filter: VaultListFilter, icon: String, count: Int, color: Color
    ) -> some View {
        let isSelected = currentFilter == filter
        return Button {
            onSelect(filter)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : color)
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(filter.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected ? Color.blue : Color(.secondarySystemBackground))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct VaultItemRow: View {
    let item: VaultItem
    let category: PasswordCategory?

    private var accentColor: Color {
        switch item {
        case .password:
            return .blue
        case .pincode:
            return .orange
        case .bankcard:
            return .green
        }
    }

    private var categoryName: String {
        category?.name ?? "Other"
    }

    private var typeLabel: String {
        switch item.type {
        case .password:
            return "Login"
        case .pincode:
            return "Pincode"
        case .bankcard:
            return "Card"
        }
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }

                    Spacer()

                    Text(categoryName)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .symbolRenderingMode(.hierarchical)
                        .background(category?.backgroundColor ?? Color.secondary.opacity(0.12))
                        .foregroundColor(category?.tintColor)
                        .clipShape(Capsule())
                }

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                /*
                HStack(spacing: 6) {
                    Text(typeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.12))
                        .foregroundColor(accentColor)
                        .clipShape(Capsule())

                    Text(categoryName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                */
            }

            //Spacer(minLength: 12)
        }
        //.padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Icon View
    private var iconView: some View {
        HStack {
            switch item.type {
            case .password:
                if let bundledIconName = bundledIconName {
                    Image(bundledIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // 缓存优先：本地缓存 → 远程加载并落盘 → 分类图标占位
                    CachedIconView(
                        urlString: item.icon ?? item.siteURL,
                        placeholderSystemName: category?.icon ?? "folder.fill",
                        placeholderColor: category?.tintColor ?? .blue
                    )
                }
            case .pincode:
                Image(systemName: "number.square.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            case .bankcard:
                Image("Custom.Bankcard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            // 1. 如果站点名称能匹配到本地预制资源，则优先显示本地图标；
            // 2. 否则尝试使用 entry.icon 里的远程地址加载；
            // 3. 如果远程图也不可用，则回退到分类默认图标。

        }
        .frame(width: 36, height: 36)
        //.background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private var bundledIconName: String? {
        // 通过站点名和本地资源名做大小写不敏感匹配，
        // 例如 "GitHub" / "github" 都可以命中同一个内置资源。
        // 先在 international 列表匹配，未命中再回退到中国版列表，
        // 例如 "微信" / "支付宝" 也能显示内置图标。
        famousApps.first(where: { $0.title.caseInsensitiveCompare(item.title) == .orderedSame })?
            .icon
            ?? famousAppsCn.first(where: {
                $0.title.caseInsensitiveCompare(item.title) == .orderedSame
            })?
            .icon
    }
}

private struct VaultPlaceholderDetailView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("\(title) Detail")
                .font(.title3)
                .fontWeight(.semibold)
            Text("This detail page is not connected yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
