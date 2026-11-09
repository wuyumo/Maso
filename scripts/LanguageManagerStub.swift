import Foundation

// Linux 测试编译替身. 不要加入 Xcode target.
// 生产实现是 Maso/Data/LanguageManager.swift, 它依赖 SwiftUI.
enum LanguageManager {
    nonisolated(unsafe) static var currentLanguageCode: String = "en"
}
