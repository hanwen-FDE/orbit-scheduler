import SwiftUI
import UIKit

/// 预置图标切换（iOS 原生 alternate icons）
enum IconService {
    struct PresetIcon {
        let name: String   // Info.plist 里注册的图标名（nil 表示主图标）
        let title: String
        let color1: Color  // 预览用渐变色
        let color2: Color
    }

    static let allIcons: [PresetIcon] = [
        .init(name: "AppIcon", title: "星轨蓝", color1: Color(red: 0.07, green: 0.18, blue: 0.36), color2: Color(red: 0.22, green: 0.75, blue: 0.84)),
        .init(name: "OrbitViolet", title: "紫罗兰", color1: Color(red: 0.30, green: 0.11, blue: 0.58), color2: Color(red: 0.65, green: 0.55, blue: 0.98)),
        .init(name: "OrbitGreen", title: "青碧", color1: Color(red: 0.02, green: 0.37, blue: 0.27), color2: Color(red: 0.20, green: 0.83, blue: 0.60)),
        .init(name: "OrbitOrange", title: "曙光", color1: Color(red: 0.57, green: 0.25, blue: 0.05), color2: Color(red: 0.98, green: 0.57, blue: 0.24)),
        .init(name: "OrbitPink", title: "桃粉", color1: Color(red: 0.51, green: 0.14, blue: 0.35), color2: Color(red: 0.96, green: 0.45, blue: 0.71)),
        .init(name: "OrbitMono", title: "月岩", color1: Color(red: 0.09, green: 0.12, blue: 0.18), color2: Color(red: 0.58, green: 0.64, blue: 0.72)),
    ]

    /// 切换图标；name == "AppIcon" 表示恢复主图标
    static func apply(_ name: String) {
        let target = name == "AppIcon" ? nil : name
        UIApplication.shared.setAlternateIconName(target) { _ in }
    }

    /// 抽屉里的图标预览
    static func previewImage(named name: String) -> Image {
        Image(name == "AppIcon" ? "IconClassic" : name)
    }
}
