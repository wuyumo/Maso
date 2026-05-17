# Pre-Deploy Checklist

部署到 App Store / TestFlight 之前**必须**逐条恢复以下临时关掉 / 简化的逻辑.
不恢复会导致付费体系失效或行为不符合产品设计.

---

## 🔴 P0 (必须恢复, 否则商业模式失效)

### 1. Plan 上限 paywall — `RootView.handleNewPlan`
- **位置**: `Maso/Views/RootView.swift` `handleNewPlan()` 函数
- **TAG**: `TODO[deploy-restore-paywall]`
- **背景**: 测试阶段关掉了"free 用户 plan ≥ 3 时弹 paywall"的检查,
  让测试时能无限新建. 不恢复 → free 用户可以白嫖, 撞不到付费墙.
- **如何恢复**: 取消那 4 行注释:
  ```swift
  if !data.settings.isPro && data.plans.count >= FreeLimit.maxPlans {
      paywallPresented = true
      return
  }
  ```

---

## 🟡 P1 (建议恢复, 但不致命)

### 2. CloudKit / iCloud 同步 — Pro 卖点兑现
- **位置**: `Maso/Data/PersistenceController.swift` (currently file-based local-only)
- **TAG**: `TODO[deploy-cloudkit-sync]`
- **背景**: 现在数据持久化只走 `Documents/maso-data.json` 本地. 设备迁移走 iOS 标准 iCloud Backup
  流程(用户买新机一次性恢复). **但多设备实时同步**(iPhone + iPad 同账号活跃用)还不行.
  METADATA.md 在 Pro 描述里已经列了 `iCloud sync across devices`, 不做就是空头承诺 →
  用户投诉 / 退款风险.
- **推荐方案**: iCloud Drive ubiquity container (file-based sync)
  - 改动小: PersistenceController.currentURL 加一段判断, ~30 行代码
  - 跟现有 JSON 文件方案无缝接驳, 不用 SwiftData refactor
  - 同步延迟 10s-2min (文件级), 用户感知够好
  - 隐私品牌不变: 用的是用户自己的 iCloud, App Store 隐私标签仍然是 "Data Not Collected"
- **完整步骤**: 见 `docs/cloudkit-todo.md`
- **总工程量**: Apple Developer Console 配置 30 分钟 + 代码改 1 天 + 测试 1 天 ≈ 2-3 天上线
- **依赖**: 付费 Apple Developer Program ($99/yr) — CloudKit 不能用免费开发者账号

### 3. AI API key 必须迁移到后端代理
- **位置**: `Maso/Data/AIWorkoutService.swift` + `Maso/Secrets.xcconfig`
- **TAG**: `TODO[deploy-backend-proxy]`
- **背景**: 现在 DeepSeek API key 走 `Maso/Secrets.xcconfig` 注入到 Info.plist
  (build-time hardcoded). 反编译 `.ipa` 可以拿到 key, 恶意用户可以拿你的 key
  调 DeepSeek 刷账单 / 滥用. 上 App Store 后必须**搭一个后端代理**:
  - iOS app 调 `https://api.maso.app/v1/ai/workout` 这种 Maso 自己 endpoint
  - 后端用 user_id / receipt 鉴权 (验证 Pro 订阅有效)
  - 后端转发请求到 DeepSeek (key 在后端 ENV var, 客户端拿不到)
  - 推荐部署: Cloudflare Workers (免费 100K req/day) / Vercel (免费 hobby tier) / Fly.io
- **如何做**:
  1. 搭最简单 proxy (Hono / Express on Cloudflare Workers, ~50 行代码)
  2. 把 `https://api.deepseek.com/v1/chat/completions` 替换成 `https://your-proxy.com/...`
  3. 客户端 Authorization header 改成 receipt token / Maso 自家 JWT
  4. **删除** `Maso/Secrets.xcconfig` 里的 key (留空)
  5. 测试 Pro 用户能调通, 非 Pro 用户被后端拒

---

## ⚙️ 其它 deploy 前提醒

- [ ] **API key 移除 hardcoded**: 确认 `Maso/Data/AIWorkoutService.swift` 没有 hardcoded key.
      用户 key 走 `@AppStorage("maso.anthropicAPIKey")`, prototype 阶段够用;
      production 应升级到 Keychain Services API.
- [ ] **HealthKit privacy strings**: 确认 `project.yml` 里 NSHealthShareUsageDescription / NSHealthUpdateUsageDescription 文案对外向用户清晰且合规.
- [ ] **FormSubmit endpoint**: 确认 wuyumoawuyumo@gmail.com 已经通过 FormSubmit 激活邮件
      (第一次提交反馈会触发激活邮件, 点了之后才正式可用).
- [ ] **Anthropic API 费用**: 上 production 后日活上来, 监控 Claude API 月度账单.
- [ ] **App Store metadata**: 准备 12 语言 description, screenshots, App icon 1024×1024 (已就绪),
      privacy policy URL.
- [ ] **TestFlight 内部测试 → 外部 beta → 全量上架**: 三阶段循序渐进.
- [ ] **Provisioning profile**: 切换 development → distribution (App Store 发布版).
