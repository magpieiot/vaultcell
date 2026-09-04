/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// UIDevice+Model.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import UIKit

extension UIDevice {
    /// 设备具体型号标识符，例如 iPhone15,2、iPad13,4 等。
    /// 通过系统调用 uname 获取 machine 字段，比 model 属性更精确。
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
