/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AddPasswordTitleView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 新增密码标题视图
struct AddPasswordTitleView: View {
    @ObservedObject var formModel: PasswordFormModel
    @ObservedObject var viewModel: VaultListViewModel

    // 用于 OAuth 跳转到更多详情页时显式注入 toast 环境对象（导航 destination 在嵌套 TabView 下环境传播不稳定）
    let toastCenter: ToastCenter

    // App Store 应用库（建议列表在输入时的主要数据源）
    @EnvironmentObject var appState: AppState

    // Next 按钮是否可用：当“手动输入非空”或“已选择图标”时为 true
    @State private var isEnabledNextButton = false
    @State private var showCategoryPicker = false

    // 输入焦点：用于在聚焦标题 / URL 时收起分类与收藏栏
    @FocusState private var focusedField: FocusedField?

    // 建议模式开关：独立于输入焦点，避免覆盖层接管输入时模式状态抖动
    @State private var isSuggestionMode = false

    // 建议模式输入框焦点：覆盖层自带输入框，出现后自动聚焦弹出键盘
    @FocusState private var suggestionFieldFocused: Bool

    // OAuth 选择状态（从 AddPasswordDetailView 合并而来）
    @State private var oauth: OAuthProviderConfig = .init()
    // 点击 OAuth 条目后跳转更多详情页
    @State private var showNextPage = false

    @Environment(\.dismiss) private var dismiss

    /// 可聚焦的输入框类型
    private enum FocusedField {
        case title
        case url
    }

    var body: some View {
        // Password Form
        // 注意：Form 内容结构必须保持稳定（titleInputSection 始终保留），
        // 否则切换布局会销毁 TextField 视图，@FocusState 随之丢失，导致键盘无法弹出。
        Form {
            /// 标题输入框（Title / URL）——始终保留，保证 TextField 焦点与键盘稳定
            titleInputSection

            /// 分类 / 收藏：始终展示，不随焦点或输入收起
            categoryFavoriteSection
                .disabled(isTitleEmpty)

            /// 基本信息（Username / Password）——自 AddPasswordDetailView 合并
            basicInfoSection
                .disabled(isTitleEmpty)

            /// Passkey 相关条目
            /// - 仅在 Passkey 模式下展示
            /*
            passkeySection
                .disabled(isTitleEmpty)
            */

            /// OAuth 相关条目
            oauthInfoSection
                .disabled(isTitleEmpty)
        }
        .overlay(alignment: .bottom) {
            // 建议模式覆盖层：自带输入框 + 全屏建议列表，铺满键盘上方，最大化列表空间
            if isSuggestionMode {
                suggestionOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: focusedField) { _, newValue in
            // 点击 Title 输入框 → 进入建议模式（覆盖层输入框接管输入）
            if newValue == .title {
                isSuggestionMode = true
            }
        }
        .navigationDestination(isPresented: $showNextPage) {
            // 点击 OAuth 条目后进入更多详情页（保存密码）
            AddPasswordMoreDetailView(formModel: formModel, viewModel: viewModel)
                .environmentObject(toastCenter)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSuggestionMode)
        .onAppear {
            //flowModel.onCompleted = { dismiss() }
        }
    }

    /// 输入标题时的联想建议：
    /// - 输入框为空：仅展示内置常用应用（famousApps），方便快速点选
    /// - 开始输入后：主要来自 App Store 应用库（AppState.apps），补充已保存条目（按标题模糊匹配，去重）
    private var suggestions: [SuggestionItem] {
        let query = formModel.siteName.trimmingCharacters(in: .whitespacesAndNewlines)

        var seen = Set<String>()
        var results: [SuggestionItem] = []

        func append(title: String, url: String?, manualIconURL: String? = nil, categoryID: UUID?) {
            let key = title.lowercased()
            guard seen.insert(key).inserted else { return }
            results.append(
                SuggestionItem(
                    id: key, title: title, url: url ?? "", manualIconURL: manualIconURL,
                    categoryID: categoryID)
            )
        }

        if query.isEmpty {
            // 输入为空：仅展示内置常用应用（保持原有顺序）
            // 图标不在这里指定：由内置图标表按域名/标题命中，命中不了就显示字母图块
            let builtinApps = famousApps
            for app in builtinApps {
                append(title: app.title, url: app.url, categoryID: app.categoryID)
            }
            return results
        }

        // 输入后：来自统一应用目录（AppState.apps），命中标题 / 英文名 / 拼音 / 首字母 / 域名
        for app in appState.apps {
            guard app.matches(query) else { continue }
            append(
                title: app.title,
                url: app.url,
                categoryID: appCategoryID(for: app)
            )
        }

        // 补充已保存密码条目（与上面结果按标题去重）
        for item in viewModel.items {
            guard case .password(let entry) = item, !entry.siteName.isEmpty,
                entry.siteName.localizedCaseInsensitiveContains(query)
            else { continue }
            append(
                title: entry.siteName, url: entry.siteURL, manualIconURL: entry.icon,
                categoryID: entry.categoryID)
        }

        return results
    }

    /// 标题输入框（Title / URL）
    /// - 用途：用户手动输入标题（优先级：手动输入 > 图标选择 > 建议条目）
    /// - 事件：手动输入标题时，更新 Next 按钮可用状态
    private var titleInputSection: some View {
        Section {
            titleFieldRow
            urlFieldRow
        }
    }

    /// Title 输入行
    private var titleFieldRow: some View {
        HStack {
            Image(systemName: "person")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            TextField("Title", text: $formModel.siteName)
                .focused($focusedField, equals: .title)
                .onChange(of: formModel.siteName) { oldValue, newValue in
                    isEnabledNextButton = !newValue.isEmpty
                }
                .autocorrectionDisabled()
        }
    }

    /// URL 输入行
    private var urlFieldRow: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            TextField(
                "URL",
                text: Binding(
                    get: { formModel.siteURL ?? "" },
                    set: { formModel.siteURL = $0.isEmpty ? nil : $0 }
                )
            )
            .focused($focusedField, equals: .url)
            .onChange(of: formModel.siteURL) { oldValue, newValue in
                isEnabledNextButton = !(newValue ?? "").isEmpty
            }
            .textContentType(.URL)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            // Title 为空时 URL 输入框不可用
            .disabled(isTitleEmpty)
        }
    }

    /// 标题是否为空：为空时其余输入框 / 选择框均禁用
    private var isTitleEmpty: Bool {
        formModel.siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 分类 / 收藏选择栏
    /// - 用途：为条目选择分类与是否收藏
    /// - 事件：聚焦标题 / URL 或输入首个字符后，随标题区上推动画一起收起
    private var categoryFavoriteSection: some View {
        Section {
            // 分类选择器

            Picker(selection: $formModel.categoryID) {
                ForEach(viewModel.categories, id: \.id) { category in
                    Label(category.name, systemImage: category.icon)
                        .foregroundColor(Color(hex: category.hexColor))
                        .labelStyle(.titleOnly)
                        .tag(category.id)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Category")
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $formModel.isFavorite) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    Text("Favorite")
                }
            }
        }
    }

    /// 基本信息部分（自 AddPasswordDetailView 合并）
    /// 包含用户名/邮箱和密码输入字段
    private var basicInfoSection: some View {
        Section {
            HStack {
                Image(systemName: "person")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                TextField("Username / Email", text: $formModel.username)
                    .textContentType(.username)
                    // 不能用 .default：与 .textContentType(.username) 搭配时 iOS 17+ 键盘类型失效（会弹出 Emoji 键盘），改用 email 键盘
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Image(systemName: "ellipsis.rectangle")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    PasswordEditField(
                        AppLocale.string("Password"), text: $formModel.password, revealDuration: 2.0
                    )
                    // 与 PasswordEditField 内部一致：不使用 .password，避免系统弹出"保存密码"提示
                    .textContentType(.oneTimeCode)

                    // 密码强度指示器：仅在已输入内容时展示，避免空态占位
                    if !formModel.password.isEmpty {
                        FormPasswordStrengthIndicator(strength: passwordStrength)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.easeInOut(duration: 0.2), value: formModel.password.isEmpty)
        }
    }

    /// 当前输入密码的强度（与密码生成器页使用同一套评级逻辑）
    private var passwordStrength: PasswordStrength {
        PasswordStrength.calculate(for: formModel.password)
    }

    /// Passkey 相关条目（自 AddPasswordDetailView 合并）
    private var passkeySection: some View {
        Section("Or Passkey") {
            HStack {
                Image("Passkey")
                Text("Apple")
                Spacer()
                Button {
                    // Do something
                } label: {
                    Image(systemName: "chevron.right")
                }
            }

            HStack {
                Image("Passkey")
                Text("Google")
                Spacer()
                Button {
                    // Do something
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
        }
    }

    /// OAuth 相关密码条目（自 AddPasswordDetailView 合并）
    /// 包含所有与当前 OAuth 提供程序相关的密码条目
    /// 每个条目包含图标、用户名和选择按钮
    private var oauthInfoSection: some View {
        Section("Or OAuth") {
            ForEach(oauthRelatedEntries) { entry in
                HStack(alignment: .center) {
                    Image(entry.siteName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                    Text(entry.username)
                    Spacer()
                    Button {
                        oauth.providerID = entry.id
                        oauth.provider = entry.siteName
                        oauth.boundValue = entry.username
                        formModel.oAuthProvider = oauth
                        // 若用户名尚未填写，自动用 OAuth 绑定的账号回填
                        if formModel.username.isEmpty {
                            formModel.username = entry.username
                        }
                        showNextPage = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    /// OAuth 相关条目：筛选出与已知 OAuth 提供程序同名的已保存密码条目
    private var oauthRelatedEntries: [PasswordEntry] {
        let normalizedProviders = oauthProviders.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return viewModel.passwordEntriesForAudit.filter { entry in
            normalizedProviders.contains(
                entry.siteName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 建议模式覆盖层：自带 Title 输入框 + 全屏建议列表
    /// - 覆盖层铺满键盘上方全部空间，不依赖坐标测量，各机型表现一致
    /// - 输入框随覆盖层一起出现，出现后自动聚焦弹出键盘
    private var suggestionOverlay: some View {
        VStack(spacing: 0) {
            suggestionInputRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            Divider()
            suggestionList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .onAppear {
            // 覆盖层出现后自动聚焦输入框，弹出键盘
            DispatchQueue.main.async {
                suggestionFieldFocused = true
            }
        }
    }

    /// 建议模式顶部输入行：与覆盖层一体，随弹窗最大化
    /// - 事件：输入时实时过滤建议列表；点 X 退出建议模式
    private var suggestionInputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            TextField("Title", text: $formModel.siteName)
                .focused($suggestionFieldFocused, equals: true)
                .onChange(of: formModel.siteName) { oldValue, newValue in
                    isEnabledNextButton = !newValue.isEmpty
                }
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    // 采纳当前输入：退出建议模式，回到主表单界面
                    exitSuggestionMode()
                }
            Button {
                exitSuggestionMode()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// 建议条目列表（覆盖层内部，独立滚动）
    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Suggestions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if suggestions.isEmpty {
                    // 无匹配时提供"采纳当前输入"的出口：点击后退出建议模式，回到主表单界面
                    Button {
                        exitSuggestionMode()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                            Text("Use \"\(formModel.siteName)\"")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(suggestions) { suggestion in
                        Button {
                            selectSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                suggestionIcon(suggestion)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !suggestion.url.isEmpty {
                                        Text(suggestion.url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    /// 建议条目的图标：内置图标 → 缓存 → 字母图块
    ///
    /// 这里**不允许**远程抓取：建议列表随输入高频重建，若每行都联网，
    /// 既浪费流量、又等于「开关只管显示不管请求」。图标抓取统一留到条目保存之后，
    /// 由列表与详情页触发一次。
    private func suggestionIcon(_ suggestion: SuggestionItem) -> some View {
        CachedIconView(
            request: IconRequest(
                title: suggestion.title,
                siteURL: suggestion.url,
                manualIconURL: suggestion.manualIconURL
            ),
            allowsRemoteFetch: false,
            fallbackSystemName: "globe",
            placeholderColor: .blue,
            placeholderFont: .footnote
        )
        .frame(width: 28, height: 28)
        .cornerRadius(6)
    }

    /// 点击建议条目：回填标题 / URL / 分类，退出建议模式
    private func selectSuggestion(_ suggestion: SuggestionItem) {
        formModel.siteName = suggestion.title
        if !suggestion.url.isEmpty {
            formModel.siteURL = suggestion.url
        }
        if let categoryID = suggestion.categoryID {
            formModel.categoryID = categoryID
        }
        // 不再记录远程图标地址：图标改由内置图标表按域名命中，未命中时按域名抓取。
        // PasswordEntry.icon 只保留「用户手动指定的图源」，这里同步建议条目的手动画源。
        formModel.icon = suggestion.manualIconURL
        isEnabledNextButton = !formModel.siteName.isEmpty
        // 退出建议模式，让用户确认回填结果（URL 输入框恢复显示）
        exitSuggestionMode()
    }

    /// 退出建议模式：关闭覆盖层并收起键盘
    private func exitSuggestionMode() {
        isSuggestionMode = false
        suggestionFieldFocused = false
        focusedField = nil
    }

    /// 根据应用标题自动匹配对应分类
    ///
    /// systemDefaults 索引：0=Primary, 1=Finance, 2=Work, 3=Life, 4=Media
    /// 未匹配的应用统一归入 Primary 作为兜底。
    private func appCategoryID(for entry: AppCatalogEntry) -> UUID {
        switch entry.id {
        // 工作应用 → Work（索引 2）
        case "github", "linkedin", "microsoft", "slack", "ciscowebex", "webex", "zoom", "notion":
            return PasswordCategory.systemDefaults[3].id
        // 社交应用 → Life（索引 3）
        case "facebook", "instagram", "reddit", "telegram", "whatsapp", "line", "tiktok", "discord",
            "pinterest", "x", "xtwitter":
            return PasswordCategory.systemDefaults[4].id
        // 娱乐/媒体应用 → Media（索引 4）
        case "netflix", "disney", "spotify", "youtube", "wikipedia":
            return PasswordCategory.systemDefaults[5].id
        // AI 工具 → Work（索引 2）
        case "chatgpt", "claude":
            return PasswordCategory.systemDefaults[3].id
        // 商务/生活应用 → Life（索引 3）
        case "amazon", "airbnb":
            return PasswordCategory.systemDefaults[4].id
        // 未匹配的应用兜底归入 Primary（索引 0），修复此前 systemDefaults[5] 越界崩溃
        default:
            return PasswordCategory.systemDefaults[0].id
        }
    }

    //
}

/// 建议条目：用于输入标题时的联想回填
private struct SuggestionItem: Identifiable {
    let id: String  // 标题小写去重后的标识，保证列表稳定
    let title: String
    let url: String
    let manualIconURL: String?  // 用户手动指定的图源（已保存条目回填）
    let categoryID: UUID?
}


