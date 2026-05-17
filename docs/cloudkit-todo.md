# TODO: CloudKit / iCloud 多设备同步

**状态**: 推迟到 v1.1。现在数据走 `PersistenceController` file-based,设备迁移靠 iOS iCloud Backup 标准流程。

**为什么先 ship 这版**: 80% 用户是单设备,file-based 持久化 + iCloud Backup 已经覆盖。CloudKit 解决的是"多设备实时同步"这 20% 高级场景 — 跟 Pro 订阅卖点强相关,但不影响第一波上架。

**什么时候做**: 上 App Store 之前。METADATA.md 里 Pro 已经承诺 `iCloud sync across devices`,不兑现是定时炸弹。

---

## 加 CloudKit 后用户能多出来什么

| 场景 | 现在 | 加 CloudKit 后 |
|---|---|---|
| 同时用 iPhone + iPad | ❌ 各自独立 | ✅ 一边改, 另一边几秒同步 |
| 换新手机 | ⚠️ 需要走 iCloud Backup 恢复 (装机一次性) | ✅ 任何时候装 Maso, 数据秒级到位 |
| 误删 app 重装 | ❌ 数据丢, 除非有 Export 文件 | ✅ 重装秒级恢复 |
| Apple Watch / Mac 版本 (未来) | ❌ 数据独立 | ✅ 自动跨平台共享数据 |
| 用户心理 | ⚠️ "我的训练历史只在这一台手机上" | ✅ "我的数据在 iCloud 里, 死机也不丢" |

## 推荐路径: iCloud Drive ubiquity container (文件级同步)

不走 SwiftData / CKDatabase refactor(那个工程量 1-2 周)。直接把现有 `Documents/maso-data.json` 挪到 ubiquity container,iOS 自动多设备同步文件。

工程量: **~30 行代码 + 配置**。

---

## 完整操作步骤

### Step 1: Apple Developer Console 配置 (30 分钟,你做)

**前置**: 付费 Apple Developer Program ($99/yr)。**免费开发账号不能用 CloudKit**。

#### 1.1 创建 CloudKit Container

1. 打开 https://developer.apple.com/account/resources/identifiers/list/cloudContainer
2. 顶部 dropdown 选 **CloudKit Containers**
3. 右上角 `+` → 创建新 container:
   - Description: `Maso Production`
   - Identifier: `iCloud.com.maso.app`
4. **Continue → Register**

#### 1.2 给 App ID 开 iCloud Capability

1. 切到 **Identifiers** → **App IDs** → 找到 `com.maso.app`
2. 进去, Capabilities 列表勾上 **iCloud**
3. 点 `Configure...` → 勾 **CloudKit**
4. 在 **Containers** 列表勾刚刚建的 `iCloud.com.maso.app`
5. **Save**

### Step 2: project.yml entitlements 配置 (10 分钟,我做)

```yaml
targets:
  Maso:
    entitlements:
      path: Maso/Maso.entitlements
      properties:
        com.apple.developer.healthkit: true
        # 新加 — CloudKit + iCloud Drive ubiquity
        com.apple.developer.icloud-container-identifiers:
          - iCloud.com.maso.app
        com.apple.developer.icloud-services:
          - CloudKit
          - CloudDocuments
        com.apple.developer.ubiquity-container-identifiers:
          - iCloud.com.maso.app
    info:
      properties:
        # 新加 — ubiquity container schema
        NSUbiquitousContainers:
          iCloud.com.maso.app:
            NSUbiquitousContainerIsDocumentScopePublic: false
            NSUbiquitousContainerName: Maso
            NSUbiquitousContainerSupportedFolderLevels: One
```

然后 `xcodegen` regenerate。

### Step 3: PersistenceController 改 (30 行代码,我做)

把 `currentURL` 改成动态路径:

```swift
extension PersistenceController {
    var currentURL: URL? {
        if shouldUseICloud,
           let ubiquityURL = FileManager.default.url(
               forUbiquityContainerIdentifier: "iCloud.com.maso.app"
           ) {
            let docsDir = ubiquityURL.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: docsDir, withIntermediateDirectories: true
            )
            return docsDir.appendingPathComponent("maso-data.json")
        }
        // fallback: local Documents (现在的行为)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("maso-data.json")
    }

    private var shouldUseICloud: Bool {
        UserDefaults.standard.bool(forKey: "maso.iCloudSyncEnabled")
            && FileManager.default.url(
                forUbiquityContainerIdentifier: "iCloud.com.maso.app"
            ) != nil
    }
}
```

### Step 4: Settings 加 iCloud 同步 toggle (我做)

在 SettingsScreen 的 Backup section 加一行:

```swift
ToggleRow(
    title: "Sync across devices",
    desc: "Use your iCloud to keep plans and workouts in sync between iPhone and iPad.",
    isOn: Binding(
        get: { UserDefaults.standard.bool(forKey: "maso.iCloudSyncEnabled") },
        set: { UserDefaults.standard.set($0, forKey: "maso.iCloudSyncEnabled") }
    )
)
```

### Step 5: 监听 ubiquity 文件变化,自动 reload (我做)

用 `NSMetadataQuery` 监听 ubiquity 容器,另一台设备改了文件就 reload 内存数据:

```swift
final class iCloudWatcher: NSObject {
    private var query: NSMetadataQuery?
    var onChange: (() -> Void)?

    func start() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        q.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "maso-data.json")
        NotificationCenter.default.addObserver(
            self, selector: #selector(onUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: q
        )
        q.start()
        query = q
    }

    @objc private func onUpdate(_ note: Notification) {
        onChange?()  // DataStore reloads from PersistenceController
    }
}
```

### Step 6: 冲突处理 (我做)

iCloud Drive 文件级同步遇冲突会创建 `.icloud` 或 `.conflict` 文件。处理策略:

- 用 Snapshot.updatedAt 比对,保留最新的版本
- 训练中 (active session) 不写盘,避免训练时两台设备打架
- 检测到冲突时 → 取 max updatedAt → silent merge,不弹用户

### Step 7: 测试 (你 + 我)

1. 真机 + 模拟器登录同一 Apple ID iCloud
2. iPhone 创建一个 plan → 退后台 (触发 save)
3. 模拟器等 30s-2min → plan 应该出现
4. 反过来再测一次

如果不同步 → Console.app 过滤 "CloudDocs" 看日志。

### Step 8: 部署 schema 到生产 (上线前必做)

> ⚠️ ubiquity container 不需要这一步, 直接跳过。这一步只是 record-level CloudKit 走 SwiftData / Core Data 才用。

---

## 估算成本

| 项 | 时间 |
|---|---|
| Step 1 (Apple Developer Console) | 30 min — 你 |
| Step 2-6 (代码) | 1 天 — 我 |
| Step 7 (测试 + iterate) | 1 天 — 我 |
| **总计** | **~2-3 天上线** |

钱:
- Apple Developer Program: $99/yr (硬成本,反正你早晚要付)
- CloudKit 用户配额: 免费 1GB / 用户 — Maso 一辈子用不完
- 你作为开发者的全局配额: 10 PB 公共 + 10 TB / 月 流量,远超个人 app 需求

✅ CloudKit 本身完全免费。

---

## 决策记录

- **2026-05-16**: 用户决定先 ship file-based 版本,CloudKit 推后到 v1.1
- **触发条件**: 当出现以下任一情况时启动:
  - METADATA.md Pro 描述已经上架了 (空头承诺压力)
  - 用户反馈"两台设备数据不同步"
  - 准备做 Apple Watch / Mac companion

---

## 跟 SwiftData + CloudKit 的对比 (备用方案)

如果将来想要**真正实时**同步 (秒级而非分钟级),考虑走 SwiftData + CloudKit:

| 维度 | ubiquity container (当前推荐) | SwiftData + CloudKit |
|---|---|---|
| 改动代价 | 30 行代码 | 59 处 Plan struct 重构 → @Model class |
| 同步粒度 | 整个 JSON 文件 | 单条 record |
| 同步速度 | 10s - 2min | 几秒 |
| 冲突处理 | last-writer-wins / .conflict 文件 | 框架内置 record-level merge |
| 工程量 | 2-3 天 | 1-2 周 |
| 适合场景 | 90% 用户 (偶尔多设备) | 高频双设备活跃用户 |

**结论**: v1.1 走 ubiquity, v2+ 如果用户量起来再升级 SwiftData。
