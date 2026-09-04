# VaultCell - iOS密码管理器 UI/UX 设计文档

## 文档信息

| 项目 | 内容
---|---
文档名称 | VaultCell UI/UX 设计文档
文档版本 | 1.0
创建日期 | 2026-06-03
作者 | 设计团队
状态 | 初稿

---

## 1. 设计概述

### 1.1 Visual Thesis（视觉主题）
> 一款冷静、极简、安全的iOS原生密码管理应用，使用柔和的蓝紫色渐变背景配合清晰的层级和优雅的动画，让安全性在视觉上得到体现，同时保持极佳的可用性。

### 1.2 Content Plan（内容规划）
- **Hero/Onboarding**: 品牌名称 + 价值主张 + 快速创建主密码
- **Main Workspace**: 密码库列表（主工作区）
- **Detail View**: 密码详情 + 2FA信息
- **Settings**: 安全设置、备份、帮助
- **Final CTA**: 设置FaceID并开始使用

### 1.3 Interaction Thesis（交互主题）
1. 平滑的入场动画，带来安全可靠的第一印象
2. 生物识别解锁的呼吸光效，增强安全感
3. 密码复制时的微反馈和计时器，让用户安心

---

## 2. 设计系统

### 2.1 色彩系统

```swift
// Colors.swift
extension UIColor {
    static let brandPrimary = UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.00)   // #007AFF
    static let brandSecondary = UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.00) // #5856D6
    
    static let surfaceBackground = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.00) // #F2F2F7
    static let cardBackground = UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00) // #FFFFFF
    
    static let textPrimary = UIColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00) // #000000
    static let textSecondary = UIColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.00) // #8E8E93
    static let textTertiary = UIColor(red: 0.72, green: 0.72, blue: 0.75, alpha: 1.00) // #C7C7CC
    
    static let success = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.00) // #34C759
    static let warning = UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1.00) // #FF9500
    static let danger = UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1.00) // #FF3B30
}

// 渐变
extension CAGradientLayer {
    static let primaryGradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.brandPrimary.cgColor,
            UIColor.brandSecondary.cgColor
        ]
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }()
}
```

### 2.2 字体系统

```
SF Pro Display
- Title 1: 34pt, Light
- Title 2: 28pt, Regular
- Title 3: 22pt, Regular
- Headline: 17pt, Semibold
- Body: 17pt, Regular
- Callout: 16pt, Regular
- Subheadline: 15pt, Regular
- Footnote: 13pt, Regular
- Caption 1: 12pt, Regular
```

### 2.3 间距系统

```swift
extension CGFloat {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
```

### 2.4 圆角系统

```swift
extension CGFloat {
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 24
}
```

### 2.5 阴影系统

```swift
extension CALayer {
    static func shadowSmall() {
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.05
        shadowOffset = CGSize(width: 0, height: 2)
        shadowRadius = 4
    }
    
    static func shadowMedium() {
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.1
        shadowOffset = CGSize(width: 0, height: 4)
        shadowRadius = 8
    }
    
    static func shadowLarge() {
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.15
        shadowOffset = CGSize(width: 0, height: 8)
        shadowRadius = 16
    }
}
```

---

## 3. 主要界面设计

### 3.1 启动页 & 欢迎引导

#### 3.1.1 启动页 (Splash Screen)

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│                                     │
│            ┌─────────┐            │
│            │  🔐    │            │
│            │ VaultCell│            │
│            └─────────┘            │
│                                     │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

**设计说明**：
- 全屏蓝紫色渐变背景
- 居中的品牌Logo和名称
- 淡入动画，持续1.5秒
- 自动跳转至验证/创建页面

#### 3.1.2 欢迎引导 (Onboarding)

```
┌─────────────────────────────────────┐
│                                     │
│           ┌──────────┐              │
│           │          │              │
│           │  [图标]  │              │
│           │          │              │
│           └──────────┘              │
│                                     │
│      安全存储您的所有密码            │
│                                     │
│      所有密码加密存储在本地设备      │
│                                     │
│                                     │
│      ┌────────────────────────┐      │
│      │   创建主密码           │      │
│      └────────────────────────┘      │
│                                     │
│      ┌────────────────────────┐      │
│      │   从备份恢复           │      │
│      └────────────────────────┘      │
│                                     │
└─────────────────────────────────────┘
```

**设计说明**：
- 垂直居中布局
- 极简的大标题
- 简短的价值主张描述（不超过2行）
- 两个主要操作按钮，创建按钮为主按钮

---

### 3.2 主密码创建/验证界面

#### 3.2.1 创建主密码

```
┌─────────────────────────────────────┐
│  ←                                  │
│                                     │
│      创建主密码                      │
│                                     │
│      ┌────────────────────────┐      │
│      │                        │      │
│      │  主密码               │      │
│      │  [输入框]             │      │
│      │                        │      │
│      └────────────────────────┘      │
│                                     │
│      ┌────────────────────────┐      │
│      │                        │      │
│      │  确认密码             │      │
│      │  [输入框]             │      │
│      │                        │      │
│      └────────────────────────┘      │
│                                     │
│      密码强度: ██████░░░░          │
│      提示: 使用8位以上组合密码       │
│                                     │
│      ┌────────────────────────┐      │
│      │   继续                 │      │
│      └────────────────────────┘      │
│                                     │
└─────────────────────────────────────┘
```

**交互**：
- 实时密码强度指示器（颜色随强度变化）
- 密码可见/隐藏切换
- 两次密码一致性检查
- 键盘上方的完成按钮

#### 3.2.2 生物识别验证

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│                                     │
│            ┌───────┐              │
│            │  ⚪   │  ← 呼吸光效   │
│            │ FaceID│              │
│            └───────┘              │
│                                     │
│      使用面容ID或主密码解锁         │
│                                     │
│                                     │
│      ┌────────────────────────┐      │
│      │   输入主密码           │      │
│      └────────────────────────┘      │
│                                     │
└─────────────────────────────────────┘
```

**交互**：
- Face ID图标呼吸动画（淡入淡出）
- 验证成功 → 缩放并淡入内容
- 验证失败 → 轻微震动 + 红色提示

---

### 3.3 主界面 - 密码库

#### 3.3.1 密码列表 (Password List)

```
┌─────────────────────────────────────┐
│  VaultCell                    ⚙️     │
├─────────────────────────────────────┤
│  🔍  搜索密码或网站…              │
├─────────────────────────────────────┤
│  全部  社交  工作  金融  购物    │
├─────────────────────────────────────┤
│  ⭐ Google                        │
│     user@gmail.com              │
│     ●●●●●●●●●●●●  [复制]      │
├─────────────────────────────────────┤
│  🏦 中国银行                        │
│     user@bank.com                │
│     ●●●●●●●●●●●●  [复制]      │
├─────────────────────────────────────┤
│  🛒 淘宝                          │
│     taobao_user                 │
│     ●●●●●●●●●●●●  [复制]      │
├─────────────────────────────────────┤
│  💬 微信                          │
│     wechat_user                 │
│     ●●●●●●●●●●●●  [复制]      │
├─────────────────────────────────────┤
│                                     │
│               +                     │
│                                     │
└─────────────────────────────────────┘
```

**设计说明**：
- 卡片式布局但无边框（只带细微阴影）
- 每个条目包含：网站图标、名称、用户名、密码蒙版
- 快速复制按钮
- 分类标签水平滚动
- 底部浮动"添加"按钮（蓝色渐变）

**交互动画**：
- 左滑显示操作：编辑、删除
- 右滑显示：收藏标记
- 点击条目：平滑推送到详情页
- 长按条目：多选模式 + 震动反馈

#### 3.3.2 密码详情 (Password Detail)

```
┌─────────────────────────────────────┐
│  ←  密码详情              编辑  ⋯  │
├─────────────────────────────────────┤
│                                     │
│            🌐 Google              │
│                                     │
├─────────────────────────────────────┤
│  网站名                             │
│  Google                          📋│
├─────────────────────────────────────┤
│  网址                               │
│  https://google.com               📋│
├─────────────────────────────────────┤
│  用户名                             │
│  user@gmail.com                   📋│
├─────────────────────────────────────┤
│  密码                               │
│  ●●●●●●●●●●●●  👁  📋  🔄        │
│  强度: ██████████ 非常强          │
├─────────────────────────────────────┤
│  双因素认证                         │
│  ┌──────────────────────────────┐  │
│  │  2FA: TOTP应用 [已启用] ✓  │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  备注                               │
│  这是主要工作账号                    │
├─────────────────────────────────────┤
│  标签                               │
│  [工作]  [重要]                    │
├─────────────────────────────────────┤
│  创建: 2026-01-15 · 更新: 03-20  │
└─────────────────────────────────────┘
```

**交互**：
- 点击密码显示明文（3秒后自动隐藏）
- 点击复制按钮 → Toast提示 + 震动反馈
- 点击👁切换可见性
- 点击🔄打开密码生成器
- 滚动查看更多内容

---

### 3.4 密码生成器

#### 3.4.1 生成器主界面

```
┌─────────────────────────────────────┐
│  ←  密码生成器                      │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Kj#9mP$2xLqW8nF           │  │
│  │  ●●●●●●●●●●●●●●●●          │  │
│  └──────────────────────────────┘  │
│                                     │
│  强度: ████████████ 非常强          │
│                                     │
│  📋  复制                🔄  刷新   │
│                                     │
├─────────────────────────────────────┤
│  长度: 16 [──────────●───────]   │
├─────────────────────────────────────┤
│  字符类型                          │
│  ☑  大写字母 (A-Z)                 │
│  ☑  小写字母 (a-z)                 │
│  ☑  数字 (0-9)                     │
│  ☑  特殊符号 (!@#$%^&*)            │
├─────────────────────────────────────┤
│  高级选项                          │
│  ☑  排除相似字符 (0OIl1)         │
│  ☐  排除特定字符: _______          │
│  ☐  保存为预设                    │
├─────────────────────────────────────┤
│  预设模板                          │
│  [强密码] [PIN码] [密码短语]        │
└─────────────────────────────────────┘
```

**交互**：
- 生成密码时的平滑变换动画
- 滑块拖动实时更新长度
- 切换选项即时更新密码
- 复制成功 → 弹出Toast + 震动

---

### 3.5 双因素认证 (2FA)

#### 3.5.1 2FA 审计概览

```
┌─────────────────────────────────────┐
│  2FA 安全审计                   📊  │
├─────────────────────────────────────┤
│  ┌──────────────────────────────┐  │
│  │  安全评分: 78 / 100        │  │
│  │  等级: 良好 ⭐⭐⭐⭐       │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  统计                              │
│  总2FA: 42  ·  已验证: 40        │
│  类型分布: TOTP 25 · 短信8 …     │
├─────────────────────────────────────┤
│  建议改进                          │
│  ⚠️  8个账户使用短信2FA → 升级TOTP  │
│  ⚠️  GitHub 2FA类型未知 → 确认    │
│  📅  5个账户超过90天未验证        │
├─────────────────────────────────────┤
│  2FA 账户列表                      │
│  ┌──────────────────────────────┐  │
│  │ Google [TOTP] ✓            │  │
│  ├──────────────────────────────┤  │
│  │ 中国银行 [短信] ⚠️            │  │
│  ├──────────────────────────────┤  │
│  │ GitHub [未检测] ❓            │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

---

### 3.6 设置界面

```
┌─────────────────────────────────────┐
│  ←  设置                          │
├─────────────────────────────────────┤
│  安全设置                          │
│  ┌──────────────────────────────┐  │
│  │ 🔒  主密码                    │  │
│  │ 🧬  生物识别 [已开启]        │  │
│  │ ⏱  自动锁定: 30秒            │  │
│  │ 📋  剪贴板: 60秒后清除         │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  数据管理                          │
│  ┌──────────────────────────────┐  │
│  │ 📤  创建加密备份              │  │
│  │ 📥  从备份恢复               │  │
│  │ 🔄  导入密码                 │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  外观                              │
│  ┌──────────────────────────────┐  │
│  │ 🌓  深色模式 [跟随系统]      │  │
│  │ Aa   字体大小: 标准          │  │
│  └──────────────────────────────┘  │
├─────────────────────────────────────┤
│  关于                              │
│  ┌──────────────────────────────┐  │
│  │ ❓  帮助与反馈               │  │
│  │ 📄  隐私政策                 │  │
│  │ 🔤  关于 VaultCell            │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

---

## 4. 交互系统

### 4.1 导航模式

| 导航类型 | 用途 | 实现方式
---|---|---
标签栏导航 | 主要功能间切换 | TabView (5个图标)
推送导航 | 查看详情、编辑 | NavigationStack
模态弹窗 | 新增、设置 | sheet
全屏模态 | 引导、验证 | fullScreenCover

### 4.2 手势操作

| 手势 | 场景 | 响应
---|---|---
左滑条目 | 密码列表 | 显示编辑/删除操作
右滑条目 | 密码列表 | 快速收藏/取消收藏
长按条目 | 密码列表 | 进入多选模式
下拉列表 | 密码列表 | 显示搜索栏 + 刷新
捏合缩放 | 详情页 | (保留用于未来功能)

### 4.3 动画系统

#### 4.3.1 入场动画

```swift
// 使用Spring动画
withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
    // 内容淡入 + 轻微上移
}
```

#### 4.3.2 生物识别动画

```swift
// 呼吸效果
struct BreathingCircle: View {
    @State private var isBreathing = false
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 100, height: 100)
            .scaleEffect(isBreathing ? 1.2 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                isBreathing = true
            }
    }
}
```

#### 4.3.3 反馈动画

```swift
// Toast提示
struct ToastView: View {
    let message: String
    @State private var isVisible = false
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(.radiusMd)
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(y: isVisible ? 0 : -20)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        isVisible = false
                    }
                }
            }
    }
}
```

---

## 5. 适配与可访问性

### 5.1 暗黑模式

- 颜色自动翻转
- 增加对比度
- 保持品牌蓝色不变
- 阴影相应调整

### 5.2 动态类型

```swift
// 支持动态类型
Text("标题")
    .font(.title)
    .font(.system(size: 34, relativeTo: .title))
```

### 5.3 VoiceOver

- 所有交互元素有label
- 密码条目支持 rotor导航
- 关键操作有haptic反馈

---

## 6. 图标系统

### 6.1 Tab栏图标

| 功能 | 图标
---|---
密码库 | lock.fill
验证码 | key.viewfinder
生成器 | sparkles
第三方 | person.2
设置 | gearshape

### 6.2 类别图标

| 类别 | 图标
---|---
社交 | person.2.fill
工作 | briefcase.fill
金融 | banknote.fill
购物 | cart.fill
娱乐 | gamecontroller.fill
其他 | folder.fill

---

## 7. 设计规范检查清单

- [ ] 遵循iOS Human Interface Guidelines
- [ ] 所有按钮最小点击区域 44x44pt
- [ ] 颜色对比度 >= 4.5:1
- [ ] 支持动态类型
- [ ] 支持VoiceOver完整导航
- [ ] 有haptic反馈
- [ ] 有加载状态和错误状态
- [ ] 支持暗黑模式
- [ ] 横竖屏适配
- [ ] 安全区域布局
- [ ] 无内存泄漏的动画
- [ ] 避免布局抖动

---

## 附录：SwiftUI 组件实现示例

### 密码条目组件

```swift
struct PasswordEntryRow: View {
    let entry: PasswordEntry
    
    var body: some View {
        HStack(spacing: .md) {
            AsyncImage(url: entry.iconURL) { image in
                image.resizable()
            } placeholder: {
                placeholderIcon
            }
            .frame(width: 40, height: 40)
            .cornerRadius(.radiusSm)
            
            VStack(alignment: .leading, spacing: .xs) {
                Text(entry.siteName)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                
                Text(entry.username)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Button(action: { /* 复制密码 */ }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, .sm)
    }
}
```

### 主按钮组件

```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [.brandPrimary, .brandSecondary]
                        ),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(.radiusLg)
        }
        .buttonStyle(.plain)
    }
}
```

---

**文档结束**
