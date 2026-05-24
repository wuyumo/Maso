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

    /// 全 app 的"当前语言 code"统一入口 — 替代散落各处的 `Bundle.main.preferredLocalizations.first`.
    /// 原因: preferredLocalizations 是 launch-time 缓存, 用户在 app 内切换语言后不更新, 导致
    /// Exercise.displayName / instructions / dangerWarnings 等运行时读到的还是老语言.
    ///
    /// `nonisolated(unsafe)` 缓存版 — 让 Exercise.displayName 等 non-MainActor 计算属性
    /// 也能直接读. 写入只走 MainActor (applyToBundle), 读是非阻塞的指针/值 copy.
    nonisolated(unsafe) static var currentLanguageCode: String = {
        // 启动时从 UserDefaults 读, 没有就用系统
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = SupportedLanguage(rawValue: raw) {
            return lang.rawValue
        }
        return Locale.preferredLanguages.first.map { code -> String in
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") || lower.hasPrefix("zh-sg") { return "zh-Hans" }
            if lower.hasPrefix("zh") { return "zh-Hant" }
            if lower.hasPrefix("pt") { return "pt-BR" }
            for l in SupportedLanguage.allCases where lower.hasPrefix(l.rawValue.lowercased()) {
                return l.rawValue
            }
            return "en"
        } ?? "en"
    }()

    /// 同上, 但给 DateFormatter / NumberFormatter 用的 Locale 实例.
    nonisolated static var currentLocale: Locale {
        Locale(identifier: currentLanguageCode)
    }

    // nonisolated 因为 currentLanguageCode 的 lazy initializer (nonisolated context) 也读它.
    nonisolated private static let storageKey = "maso.selectedLanguage"

    private init() {
        // 从 UserDefaults 读上次选择
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let lang = SupportedLanguage(rawValue: raw) {
            self.selectedLanguage = lang
        }
        // 不管用户有没有显式选 (selectedLanguage 可能为 nil), 都 apply 一次 ——
        // 这样 bundle swizzle 在 app 启动后立刻生效, Text("...") 第一帧就走 effectiveLanguage 而不是
        // Bundle.main 默认 lookup. 走 didSet 路径会再 persist 一次冗余, 所以手动调.
        applyToBundle()
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
        // 0. 更新 non-isolated 缓存 — 让 Exercise.displayName 等不在 MainActor 上的 getter 立刻读到新值
        Self.currentLanguageCode = code
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
//
// 跟"重启 app + AppleLanguages"相比, 这套方案的好处是 SwiftUI Text 实时切, 不需重启.
//
// 实现方式 (2026-05-23 改): 之前用 `object_setClass(Bundle.main, LocalizedBundle.self)` 走
// 整类换 (class swizzling). 在某些 iOS 版本上 Bundle.main 实际是 __NSCFBundle (CFBundleRef
// bridge), re-class 后 Foundation 内部 cast 不一致, 导致 localizedString override 不生效,
// 用户切了语言但 UI 完全没变.
//
// 现在改成 method exchange (objc_runtime method_exchangeImplementations): 直接把
// NSBundle 的 `localizedStringForKey:value:table:` 实现跟我们写的 `mp_localizedStringForKey:...`
// 互换. 这是 Foundation runtime 级 swap, 任何 NSBundle 子类 (包括 __NSCFBundle) 都会经过.
//
// 副作用: 全 Bundle 都会被 swap, 不只 Bundle.main. 但我们写的 impl 只在 main 上读
// languageBundle, 其它 bundle 走 fallback 调用原方法, 行为等价.
final class LocalizedBundle {
    private static var languageBundle: Bundle?
    /// method exchange 只跑一次的标记 — 再次调 applyLanguage 只更新 languageBundle, 不重复 swap.
    private static var didSwap = false

    static func applyLanguage(_ langCode: String) {
        if !didSwap {
            swizzleLocalizedString()
            didSwap = true
        }
        // 找到对应语言的 .lproj 子 bundle
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            languageBundle = bundle
        } else {
            languageBundle = nil
        }
    }

    /// 给 swizzled method 用的 hook — main bundle 走 languageBundle, 其它 bundle 走原 impl.
    /// 因为 method exchange 是把 original ↔ swizzled 互换, 这里调"swizzled" 等价于调 original.
    @objc fileprivate static func handleLocalizedString(
        for bundle: Bundle,
        key: String,
        value: String?,
        table: String?
    ) -> String {
        // 只 hook main bundle. 其它 bundle (e.g. 第三方 SDK 自带的) 直接走原查表.
        if bundle === Bundle.main, let lang = languageBundle {
            return lang.localizedString(forKey: key, value: value, table: table)
        }
        // 否则调原方法 (swap 后 mp_localizedStringForKey 等于原 localizedString)
        return bundle.mp_localizedString(forKey: key, value: value, table: table)
    }

    private static func swizzleLocalizedString() {
        let cls: AnyClass = Bundle.self
        let original = #selector(Bundle.localizedString(forKey:value:table:))
        let swizzled = #selector(Bundle.mp_localizedString(forKey:value:table:))
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let swizzledMethod = class_getInstanceMethod(cls, swizzled) else {
            assertionFailure("LocalizedBundle: failed to grab methods for swizzle")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// Bundle 扩展 — 提供 method exchange 用的 selector.
// swizzle 后:
//   - `localizedString(forKey:value:table:)` (原方法名) → 跑下面 mp_ 的实现 → 经 LocalizedBundle 路由
//   - `mp_localizedString(forKey:value:table:)`         → 跑原实现 (恢复用)
private extension Bundle {
    @objc func mp_localizedString(forKey key: String, value: String?, table: String?) -> String {
        // swap 之后, "mp_localizedString" 这个 method 持有的是 ORIGINAL localizedString impl.
        // 而 "localizedString" 持有的是这段代码 — 所以走 LocalizedBundle 路由.
        LocalizedBundle.handleLocalizedString(for: self, key: key, value: value, table: table)
    }
}
