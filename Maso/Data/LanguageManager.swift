import Foundation
import SwiftUI

// 支持的语言枚举 + in-app 语言切换 manager
//
// 实现思路:
//   1. 用户在 Settings 选语言 → 写 AppleLanguages 到 UserDefaults
//   2. 立刻用 LocalizedBundle wrapper 覆盖 Bundle.main 的 localizedString(...)
//   3. 触发 ObservableObject 重新发布, SwiftUI Text("...") 重新读 Localizable.strings
//   → 不需要重启 app
//
// 选语言遵循的范围: iOS 上主流的 12 种, 覆盖中国 / 东亚 / 欧美 / 中东 / 拉美 主要市场.

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case en              // English
    case zhHans = "zh-Hans"   // 简体中文
    case zhHant = "zh-Hant"   // 繁體中文
    case ja              // 日本語
    case ko              // 한국어
    case es              // Español
    case fr              // Français
    case de              // Deutsch
    case it              // Italiano
    case ptBR = "pt-BR"  // Português (Brasil)
    case ru              // Русский
    case ar              // العربية (RTL)

    var id: String { rawValue }

    /// 用户在自己的语言里看到的语言名 (永远用 native name, 跟 iOS Settings.app 一致)
    var nativeName: String {
        switch self {
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .es:     return "Español"
        case .fr:     return "Français"
        case .de:     return "Deutsch"
        case .it:     return "Italiano"
        case .ptBR:   return "Português (Brasil)"
        case .ru:     return "Русский"
        case .ar:     return "العربية"
        }
    }

    /// 英文名 — 给 system 跟 "Auto" 之外的方案用
    var englishName: String {
        switch self {
        case .en:     return "English"
        case .zhHans: return "Simplified Chinese"
        case .zhHant: return "Traditional Chinese"
        case .ja:     return "Japanese"
        case .ko:     return "Korean"
        case .es:     return "Spanish"
        case .fr:     return "French"
        case .de:     return "German"
        case .it:     return "Italian"
        case .ptBR:   return "Portuguese (Brazil)"
        case .ru:     return "Russian"
        case .ar:     return "Arabic"
        }
    }

    /// 一面国旗 emoji — 列表里加点视觉锚点
    var flag: String {
        switch self {
        case .en:     return "🇺🇸"
        case .zhHans: return "🇨🇳"
        case .zhHant: return "🇹🇼"
        case .ja:     return "🇯🇵"
        case .ko:     return "🇰🇷"
        case .es:     return "🇪🇸"
        case .fr:     return "🇫🇷"
        case .de:     return "🇩🇪"
        case .it:     return "🇮🇹"
        case .ptBR:   return "🇧🇷"
        case .ru:     return "🇷🇺"
        case .ar:     return "🇸🇦"
        }
    }
}

// MARK: - LanguageManager

@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    /// 用户当前选的语言 (nil = follow system)
    var selectedLanguage: SupportedLanguage? {
        didSet {
            persist()
            applyToBundle()
        }
    }

    /// 实际生效的语言 — selected 优先, 没选就跟随系统
    var effectiveLanguage: SupportedLanguage {
        if let s = selectedLanguage { return s }
        return Self.systemLanguage
    }

    private static let storageKey = "maso.selectedLanguage"

    private init() {
        // 从 UserDefaults 读上次选择
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let lang = SupportedLanguage(rawValue: raw) {
            self.selectedLanguage = lang
            // 不在 init 里调 didSet (Swift 行为), 手动 apply
            applyToBundle()
        }
    }

    /// 从系统当前语言推断出 SupportedLanguage (匹配不到的话默认英文)
    static var systemLanguage: SupportedLanguage {
        // Locale.preferredLanguages[0] 形如 "zh-Hans-CN" 或 "en-US"
        guard let pref = Locale.preferredLanguages.first else { return .en }
        let lower = pref.lowercased()
        // 中文 — 区分简繁
        if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") || lower.hasPrefix("zh-sg") {
            return .zhHans
        }
        if lower.hasPrefix("zh") { return .zhHant }  // 其他 zh-* 当繁体
        // 葡语 — 区分巴西
        if lower.hasPrefix("pt") { return .ptBR }
        // 普通双字母前缀匹配
        for l in SupportedLanguage.allCases {
            if lower.hasPrefix(l.rawValue.lowercased()) { return l }
            // 简易匹配: 取前 2 个字符比对
            let prefix = String(lower.prefix(2))
            if l.rawValue.lowercased().hasPrefix(prefix) { return l }
        }
        return .en
    }

    private func persist() {
        if let lang = selectedLanguage {
            UserDefaults.standard.set(lang.rawValue, forKey: Self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }

    /// 把当前 effectiveLanguage 应用到 Bundle (覆盖 SwiftUI Text 的字符串查找)
    private func applyToBundle() {
        let code = effectiveLanguage.rawValue
        // 1. 写 AppleLanguages — 让 SwiftUI Text 内部的 LocalizedStringResource
        //    在下次 app 启动时走对应 .lproj. 这是 iOS 系统级 i18n 入口.
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        // 2. 同时做 bundle swizzle, NSLocalizedString-based 调用 (formatter / helper) 立刻生效
        LocalizedBundle.applyLanguage(code)
    }

    /// 本次 session 是否已经选过语言但还没重启 — 用于 UI 提示
    /// (SwiftUI Text 的 LocalizedStringKey 在已渲染的视图上无法热更, 必须重启 app)
    var needsRestartForFullEffect: Bool {
        // 如果运行时 Locale.preferredLanguages 已经反映了 selectedLanguage, 就不需要重启
        guard let lang = selectedLanguage else { return false }
        let pref = Locale.preferredLanguages.first?.lowercased() ?? ""
        return !pref.hasPrefix(lang.rawValue.lowercased())
    }
}

// MARK: - LocalizedBundle — 运行时覆盖 main bundle 的字符串查找

/// 用 swizzle 让 Bundle.main 走我们指定的语言子 bundle
/// (跟"重启 app + AppleLanguages"相比, 这套方案的好处是 SwiftUI 实时切, 不需重启)
final class LocalizedBundle: Bundle, @unchecked Sendable {
    private static var languageBundle: Bundle?

    static func applyLanguage(_ langCode: String) {
        // 第一次调用 → swizzle Bundle.main 的 localizedString 方法
        if Bundle.main.object_isClass(of: LocalizedBundle.self) == false {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        // 找到对应语言的 .lproj 子 bundle
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            languageBundle = bundle
        } else {
            languageBundle = nil
        }
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let b = Self.languageBundle {
            return b.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

private extension NSObject {
    func object_isClass<T: AnyObject>(of type: T.Type) -> Bool {
        object_getClass(self) == type
    }
}
