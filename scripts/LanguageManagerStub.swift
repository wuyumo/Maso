import Foundation

/// 测试替身. 生产代码用 Maso/Data/LanguageManager.swift (依赖 SwiftUI, Linux 上不编译).
enum LanguageManager {
    nonisolated(unsafe) static var currentLanguageCode: String = "en"
}
