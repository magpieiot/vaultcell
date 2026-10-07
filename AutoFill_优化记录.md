# AutoFill 密码填充：Review 与优化记录

> 范围：`AutoFillProvider` 扩展 + 主 App 侧 `AutoFillIdentityService` / `AppLanguage` / `KeychainService` / 2FA 仓储
> 目标：排查自动填充链路的正确性与性能问题，逐项修复并验证
> 结论：7-8 秒弹窗延迟是 **Debug 构建冷启动**（`debug.dylib` 机制）导致的开发期现象；代码层共修复 8 项问题

---

## 一、整体脉络

| 阶段 | 主题 | 产出 |
|---|---|---|
| 第一轮 | Review：3 项高优先级问题 | 删除明文密码死代码、消除跨站误填风险、统一两端域名匹配 |
| 第二轮 | 性能：首次填充 7-8 秒 | 数据库预热并行化 + 冷启动归因日志；定位为 Debug 构建冷启动 |
| 第三轮 | 收尾：4 项中低优先级问题 | 同步移出主线程、2FA 删除实现、废弃 API 迁移、扩展多语言 |

---

## 二、Review 发现清单

### 高优先级（已修复）

1. **`AutoFillKeychainService` 是死代码，且含明文密码通道**
   整个类无人调用，扩展实际通过 `AutoFillCredentialStore` 直读共享 Core Data。但它提供的 `saveCredential` 会把 `CredentialItem`（含**明文 password**）JSON 序列化后整条写进 Keychain，与项目"AES-GCM 单条解密、列表不碰密文"的设计相悖。

2. **`findCredential` 兜底逻辑存在跨站误填风险**
   用户名匹配到候选、但服务标识（域名）不匹配时，原实现 `?? candidates.first` 会静默填入第一条的密码。密码管理器宁可不填，也不能猜。

3. **主 App 与扩展的域名匹配逻辑是两份手抄副本，且已漂移**
   扩展侧 `isRegistrableDomain` 的公共后缀表缺 `or` / `ne`（主 App 侧有），注册端与匹配端判定不一致会导致"注册了但键盘建议不命中"这类难排查的错位。

### 中低优先级（已修复 4 项）

4. 大库下 identity 全量同步在主线程（`makeIdentityPlan` 用 `viewContext`）
5. 扩展 UI 文案硬编码中文（国际版也显示中文）
6. `TwoFactorRepository.delete` 空实现
7. 主 App `KeychainService.swift:162` 使用 iOS 14 已废弃的 `kSecUseAuthenticationUIFail`

### 未处理（可后续评估）

- 两处固定 350ms `Task.sleep` 改自适应重试（省每次填充 ~0.3s，有生物识别时序风险）
- 选中条目解密失败时整个列表被错误页替换（宜改为列表上叠加提示）
- `lastUsedAt` 不会被自动填充使用回写，超预算排序低估真实使用频率
- 扩展入口日志打印用户名到系统日志（隐私细节）
- `withCheckedThrowingContinuation` + `DispatchQueue.global` 包装重复 4 次，可收敛

---

## 三、关键改动与决策

### 3.1 消除明文密码通道

- 删除 `AutoFillProvider/AutoFillKeychainService.swift` 与仅服务于它的 `CredentialItem` 结构体
- `project.yml` 移除扩展对 `KeychainAccess` 的依赖（唯一使用方已删）
- `xcodegen generate` 重新生成（项目约定：不手改 pbxproj）

### 3.2 收紧匹配兜底

`findCredential` 中服务标识匹配失败时不再回退 `candidates.first`：

- 免交互路径返回 `nil` → 系统回落交互流程
- 交互路径显示"未找到该站点对应的密码"，用户可手动选择

### 3.3 共享域名匹配

新增 `Shared/AutoFillDomainMatcher.swift`，收敛 `hostname(from:)` / `isIPv4` / `registrableDomain(of:)` / `isRegistrableDomain` / `matches(service:siteURL:)`，公共后缀表统一为
`["co","com","net","org","gov","edu","ac","or","ne"]`。

两端删除私有副本改为引用共享实现；`project.yml` 把该文件同时编入 `VaultCell` 和 `AutoFillProvider` 两个 target。

### 3.4 性能归因（核心结论）

在三个入口加了"**距进程启动 X 秒**"日志（sysctl `KERN_PROC` 读取进程创建时刻），实测数据：

```
AutoFill: 进入免交互路径（距进程启动 8.10s）
AutoFill: 共享数据库打开完成（0.00s）
AutoFill: Keychain 解锁失败 status=-25308        ← 首次使用的预期回落
AutoFill: 进入交互路径（距进程启动 8.39s）
AutoFill: 交互路径填充成功（解锁 0.88s，合计 0.89s）
```

**归因**：代码内耗时仅 ~1.2s；8.10s 全部落在"进程创建 → 系统第一个回调"之间，属系统侧冷启动，与业务代码无关。

**根因**：Debug 构建启用了 Xcode 的 `debug.dylib` 机制——扩展主体代码在 2.1MB 的 `AutoFillProvider.debug.dylib` 里，冷启动多一次大 dylib 加载与 fixup。Release / TestFlight 构建没有该机制。**真机 Release 实测速度正常**，问题定性完成。

并行做的两项优化（在 Release 下同样生效）：

- `AutoFillCredentialStore.warmUpDatabase()`：三个入口一进来就后台打开共享数据库，与"系统呈现面板 + Face ID"并行，日志显示数据库打开耗时 0.00s
- 修复 `persistentContainer()` 竞态：加载全程持锁（`loadPersistentStores` 同步完成），这是预热能安全并发的前提

### 3.5 identity 同步移出主线程

`makeIdentityPlan()` 拆为外层（取 `newBackgroundContext()` + `context.perform` + continuation）与内层 `buildIdentityPlan(in:budget:)`。托管对象只在所属队列访问，避免跨队列访问问题；大库下构造上万条 `ASPasswordCredentialIdentity` 不再阻塞主线程。

### 3.6 2FA 删除实现

按 ID 取 `CDTwoFactorConfig` 对象直接删除（`CDPasswordEntry.twoFactorConfigs` 为关系，`CDTwoFactorConfig.passwordEntry` 可反查父条目）；删除前记录是否为唯一配置，是则同步 `has2FA = false`；配置不存在时幂等静默返回。

### 3.7 废弃 API 迁移

`exists(for:)` 改用 `kSecUseAuthenticationContext` + `LAContext(interactionNotAllowed: true)`，语义不变（存在性检查永不弹认证 UI）。CN 构建中该警告由 2 条归零。

### 3.8 扩展多语言

- 新增 `AutoFillProvider/Localizable.xcstrings`（源语言 en，含 zh-Hans / fr / ja / de / es / ru），17 个键覆盖 UI 文案与错误描述
- 新增 `AutoFillProvider/ExtensionLanguage.swift`：从 App Group 读主 App 持久化的语言覆盖，运行时交换 `Bundle.localizedString`，使 SwiftUI 字面量与 `String(localized:)` 都走覆盖语言；未设置则跟随系统
- 三个入口首行 `ExtensionLanguage.activate()`（幂等）
- 主 App `AppLanguage.persist` 同步写一份到 App Group（**扩展进程读不到主 App 的 `UserDefaults.standard`**）；`bootstrap()` 补写历史值，保证老用户升级后扩展仍跟随已选语言

---

## 四、验证结果

- `xcodegen generate` 通过，entitlement 校验全部通过
- Debug / Debug-CN 两个 scheme 模拟器构建均 `BUILD SUCCEEDED`，无新增诊断
- 扩展产物已生成 7 个 `.lproj`（en / zh-Hans / fr / ja / de / es / ru）
- `kSecUseAuthenticationUIFail` 废弃警告归零
- 真机 Release 实测填充速度正常

---

## 五、经验要点

1. **先归因再优化**：8 秒延迟看似"代码慢"，加了进程启动基准日志后才确认是系统冷启动；没有测量手段就只能猜。
2. **Debug 构建不 representative**：性能问题必须用 Release（或 Archive）在真机验证，`debug.dylib` 机制会显著拖慢冷启动。
3. **测试时断开 Xcode**：调试器附加会改变系统对扩展进程的回收策略，测出的冷启动时间不代表真实体验。
4. **扩展与主 App 是独立进程**：`UserDefaults.standard` 不共享，任何需要跨进程读取的偏好都必须显式写 App Group。
5. **两端共享的判定逻辑必须同源**：注册端与匹配端各写一份副本时，迟早漂移；用共享文件编进两个 target。
6. **密码管理器的兜底策略要保守**：匹配不确定时宁可让用户手动选，也不要自动填入可能属于其它站点的凭据。
7. **覆盖安装不影响数据**：Debug → Release 是同 bundle ID 的普通更新，App Group 容器与 Keychain 均保留；**不要在测试前手动删除 App**（会连带清掉 App Group 容器里的数据库）。
