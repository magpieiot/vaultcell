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
# 防止"设置中看不到 VaultGo / Final plugin count: 0"静默复发。
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

echo "[verify-entitlements] 校验必须存在的 entitlement / 能力声明 ..."

# --- 主 App ---
check "$ROOT/VaultGo/VaultGo.entitlements" \
  "com.apple.developer.authentication-services.autofill-credential-provider"
check "$ROOT/VaultGo/VaultGo.entitlements" \
  "com.apple.security.application-groups"
check "$ROOT/VaultGo/VaultGo.entitlements" \
  "keychain-access-groups"

# --- 凭据提供器扩展 ---
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "com.apple.developer.authentication-services.autofill-credential-provider"
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "com.apple.security.application-groups"
check "$ROOT/AutoFillProvider/AutoFillProvider.entitlements" \
  "keychain-access-groups"

# --- 扩展 Info.plist 的能力声明（自动填充 + 凭据交换）---
check "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:SupportsAutoFill"
check "$ROOT/AutoFillProvider/Info.plist" \
  "NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionCapabilities:SupportsCredentialExchange"

# --- 主 App Info.plist 的凭据交换活动声明 ---
check "$ROOT/VaultGo/Resources/Info.plist" \
  "NSUserActivityTypes"

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
