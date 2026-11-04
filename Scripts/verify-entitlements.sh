#!/usr/bin/env bash
# ------------------------------------------------------------------
# verify-entitlements.sh
#
# xcodegen 会按 project.yml 的 `targets.*.entitlements.properties`
# 重写各 .entitlements 文件，手工直接改文件会在下次 generate 时被静默覆盖。
#
# 本脚本在 `xcodegen generate` 之后（options.postGenCommand）自动运行，
# 校验"Autofill Credential Provider"所必需的 key 是否仍然存在，
# 缺失任一 key 即打印醒目错误并以非零码退出，
# 防止"设置中看不到 VaultCell / Final plugin count: 0"静默复发。
#
# 修复方法：把缺失的 key 补进 project.yml，再重新运行 xcodegen generate。
# ------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

check() {
  local file="$1"
  local key="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$file" >/dev/null 2>&1; then
    echo "  [OK] $file : $key"
  else
    echo "  [MISSING] $file : $key"
    FAILED=1
  fi
}

# 必须存在的键，但其值必须为 false（能力位一旦为 true，系统就会派发对应请求）
check_false() {
  local file="$1"
  local key="$2"
  local value
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null)
  if [ "$value" = "false" ]; then
    echo "  [OK] $file : $key = false"
  else
    echo "  [INVALID] $file : $key = ${value:-<missing>}（必须为 false）"
    FAILED=1
  fi
}

# 必须存在且取值必须等于期望值
check_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local value
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null)
  if [ "$value" = "$expected" ]; then
    echo "  [OK] $file : $key = $expected"
  else
    echo "  [INVALID] $file : $key = ${value:-<missing>}（必须为 $expected）"
    FAILED=1
  fi
}

# 必须存在的文件（不在 plist 内的产物，例如 bundle 自带的隐私清单）
require_file() {
  local file="$1"
  if [ -f "$file" ]; then
    echo "  [OK] $file 存在"
  else
    echo "  [MISSING] $file 不存在"
    FAILED=1
  fi
}

echo "[verify-entitlements] 校验必须存在的 entitlement / 能力声明 ..."

# --- 主 App ---
check "$ROOT/VaultCell/VaultCell.entitlements" \
  "com.apple.developer.authentication-services.autofill-credential-provider"
check "$ROOT/VaultCell/VaultCell.entitlements" \
  "com.apple.security.application-groups"
check "$ROOT/VaultCell/VaultCell.entitlements" \
  "keychain-access-groups"
check "$ROOT/VaultCell/VaultCell.entitlements" \
  "com.apple.developer.icloud-services"
check "$ROOT/VaultCell/VaultCell.entitlements" \
  "com.apple.developer.icloud-container-identifiers"

# --- 凭据提供器扩展 ---
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "com.apple.developer.authentication-services.autofill-credential-provider"
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "com.apple.security.application-groups"
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "keychain-access-groups"

# --- 扩展 Info.plist 的能力声明（自动填充 + 凭据交换）---
# ⚠️ ProvidesPasswords 缺失时系统不把扩展当作密码填充提供者：
# QuickType 不出现建议、credential identity 读回为空（Apple 官方模板默认写 true）
check "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:ProvidesPasswords"
check "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:SupportsAutoFill"
check "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:SupportsCredentialExchange"

# ⚠️ ProvidesPasskeys 必须为 false：本 App 尚未实现通行密钥。
# 置 true 会让系统的 passkey 断言/注册请求派发到扩展，而扩展没有
# completeAssertionRequest / completeRegistrationRequest 的实现，
# 扫码登录（hybrid QR）会一直等不到回调 —— 表现为系统面板卡死。
check_false "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:ProvidesPasskeys"

# --- 主 App Info.plist 的凭据交换活动声明 ---
check "$ROOT/VaultCell/Resources/Info.plist" \
  "NSUserActivityTypes"

# --- 推送能力：CKSyncEngine 的 zone subscription 依赖静默推送 ---
# 取值由 APS_ENVIRONMENT 构建设置提供（Debug=development / Release=production），
# 直接写死 development 会让上架版本收不到同步通知，写死 production 则本地联调失败。
check_value "$ROOT/VaultCell/VaultCell.entitlements" \
  "aps-environment" '$(APS_ENVIRONMENT)'

# --- 隐私清单：主 App 与扩展是独立 bundle，各自都要有 ---
require_file "$ROOT/VaultCell/Resources/PrivacyInfo.xcprivacy"
require_file "$ROOT/AutoFillProvider/PrivacyInfo.xcprivacy"

# --- 打包产物检查（project.yml 改写后最容易静默退化）---
PBXPROJ="$ROOT/VaultCell.xcodeproj/project.pbxproj"

# 主 App 与扩展的资源阶段各统计一次（局限 PBXResourcesBuildPhase 段内，
# 避免把 PBXBuildFile 定义行也数进来）
privacy_count=$(
  awk '/Begin PBXResourcesBuildPhase/,/End PBXResourcesBuildPhase/' "$PBXPROJ" |
    grep -c "PrivacyInfo.xcprivacy in Resources" || true)
if [ "${privacy_count:-0}" -eq 2 ]; then
  echo "  [OK] 主 App 与扩展的资源阶段各有一份 PrivacyInfo.xcprivacy"
else
  echo "  [INVALID] PrivacyInfo.xcprivacy 应出现在 2 个资源阶段，实际 ${privacy_count:-0}（扩展缺隐私清单会触发 ITMS-91053）"
  FAILED=1
fi

if awk '/Begin PBXResourcesBuildPhase/,/End PBXResourcesBuildPhase/' "$PBXPROJ" |
  grep -q "\.md in Resources"; then
  echo "  [INVALID] 仍有 markdown 文档被打进 bundle（project.yml 的 VaultCell.sources.excludes 需包含 **/*.md）"
  FAILED=1
else
  echo "  [OK] bundle 中没有 markdown 文档"
fi

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "================================================================"
  echo " FAIL: 存在缺失的 entitlement / 能力声明 key！"
  echo " 原因：xcodegen generate 按 project.yml 重写这些配置文件，"
  echo "       手工改文件会被覆盖（本次重写后 key 已丢失）。"
  echo " 修复：把缺失 key 补进 project.yml"
  echo "       （entitlements.properties / Info.plist 相关配置），"
  echo "       然后重新运行 xcodegen generate。"
  echo "================================================================"
  exit 1
fi

echo "[verify-entitlements] 全部通过。"
