import Foundation

// Polar 外部付费 — storefront 解析 + license key 校验的落地 (写 settings + 持久化).
// 网络细节在 PolarEntitlement; 这里管状态 + 宽限策略.
extension DataStore {

    /// 解析当前 App Store storefront 国家码, 写进 settings.appStoreCountry.
    /// 启动时调一次. 非美区/未知 → isPro 恒 true (免费全解锁).
    func refreshStorefrontCountry() async {
        guard MasoFlags.externalPaywallEnabled else { return }
        // showcase / 截图模式: 不解析 storefront → appStoreCountry 保持 nil → isPro 恒 true,
        // App Store 截图 / verify-app 里展示完整 (已解锁) 界面, 不弹付费门.
        guard ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1" else { return }
        #if DEBUG
        // 调试开关: 强制美区, 让非美区 Apple ID 也能真机预览付费墙 + 激活流程.
        if settings.debugForceUSStorefront {
            if settings.appStoreCountry != MasoFlags.usStorefrontCode {
                settings.appStoreCountry = MasoFlags.usStorefrontCode
                save()
            }
            return
        }
        #endif
        guard let code = await PolarEntitlement.currentStorefrontCountry() else { return }
        if settings.appStoreCountry != code {
            settings.appStoreCountry = code
            save()
        }
    }

    /// 用一个 key 走 Worker 校验并落地状态. 返回是否 active (给 UI 反馈).
    /// active → 存 key + 状态 + 到期 + 校验时间; not active → 清 active (但保留 key 供显示).
    /// 网络/配置失败 → 抛错 (caller 决定文案), 不动已有状态.
    @discardableResult
    func activatePolar(key: String) async throws -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let result = try await PolarEntitlement.validate(key: trimmed)
        settings.polarLicenseKey = trimmed
        settings.polarProActive = result.active
        settings.polarExpiresAt = result.expiresAt
        settings.polarValidatedAt = Date()
        save()
        return result.active
    }

    /// 重校验已存的 key (启动 / 回前台). 无 key 直接返回.
    /// 网络失败 → 保留上次状态 (离线宽限内不降级); 宽限窗外且拿不到 → 判 not active.
    func refreshPolarEntitlement() async {
        guard MasoFlags.externalPaywallEnabled,
              let key = settings.polarLicenseKey, !key.isEmpty else { return }
        do {
            let result = try await PolarEntitlement.validate(key: key)
            settings.polarProActive = result.active
            settings.polarExpiresAt = result.expiresAt
            settings.polarValidatedAt = Date()
            save()
        } catch {
            // 网络/服务挂了: 离线宽限窗内保留上次 active; 超窗则不再当 pro.
            if let last = settings.polarValidatedAt,
               Date().timeIntervalSince(last) < PolarEntitlement.offlineGrace {
                return  // 保留现状
            }
            if settings.polarProActive {
                settings.polarProActive = false
                save()
            }
        }
    }
}
