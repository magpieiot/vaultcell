/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// ReferenceDataService.swift
/// created on: 25/07/2026
/// ------------------------------------------------------------------

import Foundation
import Combine

/// 通用引用数据服务，负责 categories（分类）与 tags（标签）的加载与维护。
///
/// 设计要点：
/// - 不绑定任何具体 vault entry 类型（Password/PIN/Bankcard），
///   可被多种凭证相关视图共享，避免重复数据管理。
/// - 所有 UI 状态更新通过 @Published 属性驱动，ViewModel 订阅后自动刷新界面。
/// - 数据操作均通过 Repository 协议层完成，便于单元测试时注入 Mock 实现。
/// - 使用 @MainActor 确保所有状态变更在主线程执行，消除 UI 线程安全问题。
@MainActor
final class ReferenceDataService: ObservableObject {
    
    // MARK: - 公开状态（UI 绑定）
    
    /// 当前所有密码分类列表，按 sortOrder 升序排列
    @Published var categories: [PasswordCategory] = []
    /// 当前所有标签列表，按 sortOrder 升序排列
    @Published var tags: [Tag] = []
    /// 数据是否正在加载中，UI 可据此显示加载指示器
    @Published var isLoading: Bool = false
    /// 最近一次操作的错误信息，为 nil 时表示无错误
    @Published var errorMessage: String?
    
    // MARK: - 私有依赖
    
    /// 分类数据持久化仓库（协议类型，支持依赖注入）
    private let categoryRepository: CategoryRepositoryProtocol
    /// 标签数据持久化仓库（协议类型，支持依赖注入）
    private let tagRepository: TagRepositoryProtocol
    
    // MARK: - 初始化
    
    /// 初始化引用数据服务
    /// - Parameters:
    ///   - categoryRepository: 分类仓库实现，默认使用 CategoryRepository()
    ///   - tagRepository: 标签仓库实现，默认使用 TagRepository()
    init(
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        tagRepository: TagRepositoryProtocol = TagRepository()
    ) {
        self.categoryRepository = categoryRepository
        self.tagRepository = tagRepository
    }
    
    // MARK: - 数据加载
    
    /// 加载所有分类数据
    ///
    /// 流程：
    /// 1. 确保默认分类已存在（首次启动或数据缺失时自动补齐）
    /// 2. 从仓库获取全部分类
    /// 3. 按 sortOrder 升序排序后更新 categories 数组
    func loadCategories() async {
        do {
            // 确保系统默认分类存在，防止首次启动时列表为空
            try await categoryRepository.ensureDefaults()
            // 拉取全部自定义+系统分类
            let fetched = try await categoryRepository.fetchAll()
            // 按排序权重升序排列，保证 UI 显示顺序一致
            categories = fetched.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 加载所有标签数据
    ///
    /// 流程同 loadCategories，先补齐默认标签，再拉取并排序。
    func loadTags() async {
        do {
            // 确保系统默认标签存在
            try await tagRepository.ensureDefaults()
            // 拉取全部标签
            let fetched = try await tagRepository.fetchAll()
            // 按排序权重升序排列
            tags = fetched.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 并行重新加载分类和标签
    ///
    /// 使用 Swift 结构化并发（async let）同时发起两个加载请求，
    /// 比串行调用 loadCategories + loadTags 节省约一半等待时间。
    func reloadAll() async {
        // async let 并发启动两个子任务
        async let cat: () = loadCategories()
        async let tag: () = loadTags()
        // 等待两者都完成后才返回
        _ = await (cat, tag)
    }
    
    // MARK: - 分类查询
    
    /// 根据分类 ID 查找对应分类
    /// - Parameter categoryID: 分类的唯一标识符
    /// - Returns: 匹配的分类对象，未找到则返回 nil
    func category(for categoryID: UUID) -> PasswordCategory? {
        categories.first { $0.id == categoryID }
    }
    
    // MARK: - 分类增删改
    
    /// 新增自定义分类
    ///
    /// 新增的分类 isSystem 标记为 false，sortOrder 基于当前已有分类数量自动递增。
    ///
    /// - Parameters:
    ///   - name: 分类名称
    ///   - icon: SF Symbol 图标名，默认 "folder.fill"
    ///   - hexColor: 分类颜色（16进制字符串），默认 "#8E8E93"（系统灰色）
    func addCategory(name: String, icon: String = "folder.fill", hexColor: String = "#8E8E93") async {
        // 构建新的分类对象，sortOrder 按尾部追加
        let newCategory = PasswordCategory(
            name: name,
            icon: icon,
            hexColor: hexColor,
            isSystem: false,
            sortOrder: Int32(categories.count)
        )
        do {
            // 先写入仓库确保持久化成功
            try await categoryRepository.create(newCategory)
            // 持久化成功后再更新内存数组
            categories.append(newCategory)
            categories.sort { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 重命名分类（不允许修改系统分类）
    ///
    /// - Parameters:
    ///   - category: 待重命名的分类
    ///   - newName: 新名称
    func renameCategory(_ category: PasswordCategory, to newName: String) async {
        // 系统分类受保护，不允许重命名
        guard !category.isSystem else { return }
        // 复制分类对象并修改名称和时间戳
        var updated = category
        updated.name = newName
        updated.updatedAt = Date()
        do {
            // 先更新持久化仓库
            try await categoryRepository.update(updated)
            // 仓库更新成功后再更新内存数组中的对应项
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 删除分类
    ///
    /// 删除前会校验该分类不是系统分类。
    /// 注意：删除分类后，原本属于该分类的 entry 的重新分配由调用方
    /// （持有 entry 仓库的 ViewModel）负责处理。
    ///
    /// - Parameters:
    ///   - categoryID: 待删除的分类 ID
    ///   - reassignTo: 将该分类下的 entry 迁移到的目标分类 ID，默认使用系统默认分类
    func deleteCategory(_ categoryID: UUID, reassignTo targetCategoryID: UUID? = nil) async {
        // 校验分类存在且非系统分类
        guard let category = categories.first(where: { $0.id == categoryID }), !category.isSystem else { return }
        // 确定迁移目标：用户指定 > 系统默认分类
        let targetID = targetCategoryID ?? PasswordCategory.defaultCategoryID
        do {
            // 从仓库中删除
            try await categoryRepository.delete(categoryID)
            // 从内存数组中移除
            categories.removeAll { $0.id == categoryID }
            // 注意：entry 的重新分配由调用方负责，这里仅保留 targetID 供调用方使用
            _ = targetID
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - 分类排序
    
    /// 按给定顺序持久化分类的排序
    ///
    /// 传入重新排序后的完整分类数组，方法会重新分配每个分类的 sortOrder
    /// 并逐个更新到仓库中。
    ///
    /// - Parameter reordered: 用户重新排序后的分类数组（包含所有分类）
    func reorderCategories(_ reordered: [PasswordCategory]) async {
        var newCategories: [PasswordCategory] = []
        let now = Date()
        // 遍历重排后的数组，按索引顺序重新分配 sortOrder
        for (index, var category) in reordered.enumerated() {
            category.sortOrder = Int32(index)
            category.updatedAt = now
            newCategories.append(category)
        }
        do {
            // 逐个持久化更新到仓库
            for category in newCategories {
                try await categoryRepository.update(category)
            }
            // 仓库更新成功后，更新内存数组（确保排序一致）
            categories = newCategories.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 更新单个分类的名称、图标、颜色
    ///
    /// 系统分类受保护，调用此方法会被静默忽略。
    ///
    /// - Parameters:
    ///   - category: 待更新的分类对象
    ///   - name: 新名称
    ///   - icon: 新图标（SF Symbol 名称）
    ///   - hexColor: 新颜色（16进制字符串）
    func updateCategory(_ category: PasswordCategory, name: String, icon: String, hexColor: String) async {
        // 系统分类不允许修改
        guard !category.isSystem else { return }
        // 构建更新后的分类对象
        var updated = category
        updated.name = name
        updated.icon = icon
        updated.hexColor = hexColor
        updated.updatedAt = Date()
        do {
            // 先持久化到仓库
            try await categoryRepository.update(updated)
            // 再更新内存数组
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - 标签增删
    
    /// 新增标签
    ///
    /// 创建前会执行以下校验：
    /// 1. 去除首尾空白字符后不能为空
    /// 2. 不区分大小写检查是否已存在同名标签，避免重复创建
    ///
    /// - Parameters:
    ///   - name: 标签名称
    ///   - hexColor: 标签颜色，不传则根据名称自动生成
    func addTag(name: String, hexColor: String? = nil) async {
        // 去除首尾空白
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空字符串直接返回，不创建
        guard !trimmed.isEmpty else { return }

        // 不区分大小写检查是否已存在同名标签
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // 标签已存在，跳过创建
            _ = existing
            return
        }

        // 构建新标签对象，sortOrder 按尾部追加
        let color = hexColor ?? tagColor(for: trimmed)
        let newTag = Tag(name: trimmed, hexColor: color, sortOrder: Int32(tags.count))
        do {
            // 先持久化到仓库
            try await tagRepository.create(newTag)
            // 再更新内存数组并排序
            tags.append(newTag)
            tags.sort { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 删除指定标签
    /// - Parameter tagID: 待删除的标签 ID
    func removeTag(_ tagID: UUID) async {
        do {
            // 从仓库中删除
            try await tagRepository.delete(tagID)
            // 从内存数组中同步移除
            tags.removeAll { $0.id == tagID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 确保一批标签名称在仓库中存在（不存在则自动创建）
    ///
    /// 用于 entry 录入/编辑场景：用户输入了一些标签名，需要保证它们
    /// 在系统中存在后才能建立关联。
    ///
    /// - Parameter names: 标签名称列表
    /// - Returns: 已存在或新创建的标签对象数组；出错时返回空数组
    func ensureTagsExist(names: [String]) async -> [Tag] {
        do {
            // 调用仓库方法，不存在的标签会自动创建
            let ensured = try await tagRepository.ensureTagsExist(names: names)
            // 重新加载标签列表以保持内存数据同步
            await loadTags()
            return ensured
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
