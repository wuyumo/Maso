# 健身素材库调研

调研目的:给 Maso iOS 加入真实动作图片 / 动画 / 3D 模型,替换现在的 category 渐变占位。

调研时间:2026-05-15
调研范围:开源数据集、动画运行时、3D 解剖模型。

---

## 1. 动作图片 / GIF 数据集

### ⭐ 推荐:`yuhonas/free-exercise-db`

| 项 | 内容 |
|---|---|
| 仓库 | https://github.com/yuhonas/free-exercise-db |
| Star | 1.36k · 380 forks (活跃) |
| Update | 2026-04-05(每月有更新) |
| **License** | **Unlicense(公共领域)** ✓ 商用、闭源、改写、再分发,无任何限制 |
| 数据量 | 800+ 动作 |
| 格式 | JSON metadata + JPG 图(每个动作 2 帧:`0.jpg` 起始姿,`1.jpg` 终姿) |
| 字段 | name / category / equipment / primary muscles / secondary muscles / instructions |
| 中文 | ❌ 仅英文(动作名要自己翻) |
| 接入方式 | 直接读 GitHub raw URL,或下载 JSON 自己镜像到 CDN |
| Web 端现状 | 已经在用 — `/api/exercise-image?folder=...` 反代,iOS 直接吃同一份 |

**为什么推荐**:
- License 最干净 — App Store 提交、付费版、再分发都没问题
- 已被 web 端 Maso 验证过(`ExerciseImage.tsx` 双帧 cross-fade 就是接这个)
- iOS 接入零门槛 — `AsyncImage` + `TimelineView` 切两帧即可

---

### ⚠️ 可选(注意 License):`ExerciseDB`

| 项 | 内容 |
|---|---|
| 仓库 | https://github.com/ExerciseDB/exercisedb-api |
| Star | 255 · 73 forks |
| Update | 2025-11-25 |
| **License** | **AGPL-3.0** ⚠️ 是 copyleft — 用了就得开源整个 app |
| 数据量 | **11,000+ 动作**(碾压 yuhonas) |
| 格式 | JSON + 视频 / GIF / 图 |
| 中文 | ❌ |
| 接入方式 | 自建 API 或用 ascendapi.com 商业 tier |

**License 详解**:AGPL 即使 iOS app 用网络方式调用都触发开源义务(比标准 GPL 还严)。如果 Maso 计划商业化或保持闭源,**不能用**。如果 Maso 永远开源,可以用,但生态注意。

> 选这个的唯一理由是 11,000+ 这个数据量太诱人。但 800 个对健身 app 已经足够 — 大多数训练计划反复用 30-50 个核心动作。

---

### ❌ 不推荐:`hasaneyldrm/exercises-dataset`

| 项 | 内容 |
|---|---|
| 仓库 | https://github.com/hasaneyldrm/exercises-dataset |
| **License** | **无 license = 默认全部保留** ⚠️ 法律上不能用 |
| 数据量 | 433 个动作 + 动画 GIF + 双语指令 |

可惜了 — 数据质量看起来不错,有动画 GIF,但作者没加 license,法律上不能商用。可以发 issue 让作者加。

---

### 其他备选

- **`wger-project/wger`** — Self-hosted 健身平台,AGPL-3.0(同样不适合闭源)
- **buildship.com Open-Source Fitness API** — 第三方包装

---

## 2. 动画运行时

### ⭐ 推荐:Rive(对 Maso 的"训练时优先"理念最对路)

| 项 | 内容 |
|---|---|
| 官网 | https://rive.app |
| 仓库 | https://github.com/rive-app/rive-ios |
| Swift Package | `https://github.com/rive-app/rive-ios`(iOS 14+,SPM 直接装) |
| 跨端 | iOS / macOS / tvOS / visionOS 都支持 |
| **性能** | ~60 FPS(Lottie 约 17 FPS) |
| **文件大小** | `.riv` 比 `.json` 小 50-80% |
| 状态机 | ✅ 原生(state machine + 触发器) |
| 数据绑定 | ✅ 直接绑动态数据 → 动画 |
| 跟 SwiftUI 整合 | 有 `RiveViewModel` API,封装一行 |
| 编辑器 | rive.app 自带(网页 + 桌面端),学习曲线略陡 |
| 价格 | 编辑器 / 运行时免费;商业模板付费 |

**为什么对 Maso 合适**:
- 训练播放器的"组完成 ✓"、"休息倒计时"、"PR 触发小高亮"这些状态切换,用 Rive state machine 一个文件搞定,不用代码维护多套动画
- 计时倒计时是数据驱动的 → 数据绑定能力直接派上用场
- 60 FPS 在训练时屏幕上更舒服(手抖、出汗状态下流畅度感知更明显)

**风险**:
- 学习成本(团队需要懂 Rive 编辑器)
- 资源积累 — 没有像 LottieFiles 那么庞大的免费市场

---

### Lottie(传统选择)

| 项 | 内容 |
|---|---|
| 仓库 | https://github.com/airbnb/lottie-ios |
| Swift Package | `https://github.com/airbnb/lottie-spm` |
| 来源 | Airbnb 出品, 跨端事实标准 |
| 编辑器 | Adobe After Effects + Bodymovin 插件 |
| **性能** | ~17 FPS 重负载下 |
| 状态机 | dotLottie 2025 年新加,但不如 Rive 原生 |
| **生态** | 巨大 — [LottieFiles 上有海量免费健身动画](https://lottiefiles.com/free-animations/fitness) |

**选 Lottie 的场景**:
- 团队已用 AE,有现成工作流
- 主要做"装饰性"动画(欢迎页、空状态),不需要响应数据
- 想拿 LottieFiles 现成包

**Maso 现实选择**:
- 如果只是为了**给训练完成屏 / Onboarding 加几个动画**,Lottie 够用且 LottieFiles 有现成包
- 如果想做**真正的交互式数据动画**(训练时实时反馈),选 Rive

---

### 第三选项:SwiftUI 内建动画

不依赖外部 lib — `withAnimation`、`TimelineView`、`Canvas` 已经能做不少东西。Maso 当前的 BodyHint 就是纯 SwiftUI Canvas。

**适用**:
- 极简动画(透明度、缩放、位移)
- 想保持 0 第三方依赖

不适用:复杂关键帧、状态机、骨骼动画。

---

## 3. 3D 人体 / 解剖模型

### ⭐ 推荐:Z-Anatomy(开源)

| 项 | 内容 |
|---|---|
| 官网 | https://www.z-anatomy.com/ |
| itch.io | https://lluisv.itch.io/z-anatomy |
| **License** | **CC BY-SA 4.0** — 署名 + 派生作品同协议开源 |
| 内容 | 骨骼 / 肌肉 / 血管 / 神经 (分层) |
| 格式 | Blender 文件(`.blend`); 可导出 USDZ / OBJ / FBX |
| 数据源 | 基于 BodyParts3D(日本生命科学数据库,公共领域) |

**接入流程**:
1. 下载 `.blend`
2. 在 Blender 里挑出需要的 mesh(肌肉单元 / 主要骨骼)
3. 导出为 `.usdz`(iOS 原生格式,Quick Look 即可看)
4. 用 `RealityKit` 加载 + 动画 muscle 高亮

**License 注意**:
- ✅ 可以用于商业 app
- ⚠️ 必须**署名**(在 about / credits 里挂作者 Gauthier Kervyn 和 BodyParts3D)
- ⚠️ **SA(Share-Alike)** — 如果对模型做了修改并分发,衍生品需要同协议(CC BY-SA)。**只是引用不修改**则不触发 SA;如果想自己改 mesh 又不想公开衍生品,这一条要谨慎。

---

### Sketchfab(单点采购)

| 项 | 内容 |
|---|---|
| 官网 | https://sketchfab.com/tags/anatomy-muscle |
| License | 看每个模型 — CC-BY 免费,Editorial 付费 |
| 格式 | 通常 GLB / FBX,需要转 USDZ |

**适用**:挑选某几块单独的肌肉 / 骨头 mesh,不想拉整个 Z-Anatomy。

---

### Meshy.ai(AI 生成)

| 项 | 内容 |
|---|---|
| 官网 | https://www.meshy.ai/tags/muscle |
| License | 看具体生成 |
| 输出 | 包含 USDZ |

**适用**:做风格化非写实人物(比如卡通版健身教练)。不适合解剖精度。

---

### iOS 3D 渲染层选择

无论选哪个数据源,iOS 这边技术栈:

| 框架 | 用法 | 复杂度 |
|---|---|---|
| **RealityKit**(iOS 13+) | `RealityView { content in ... }` SwiftUI 原生,Apple 主推 | ⭐ |
| **SceneKit**(iOS 8+,老但稳) | `SCNView` + `SCNScene` | ⭐⭐ |
| **Quick Look 3D**(零代码) | `.usdz` 文件直接 `ARQuickLookView` 即可旋转预览 | ⭐(最简) |

对 Maso 来说,**Quick Look 3D 看肌肉**就足够 90% 的场景 — 用户点一下进入全屏 3D 视图,旋转看肌肉。**RealityView** 适合做内嵌的"今日肌群"动效。

---

## 4. 综合推荐路径(我的建议)

如果让我选一条最经济的路径:

### Phase 1(本周)— 2 天内做完

1. **接入 `yuhonas/free-exercise-db`**:
   - 写一个 Swift 类型 `ExerciseLibrary`,镜像 800 个动作元数据到 app bundle 里(json 约 200KB,gzip 后更小)
   - `ExerciseImage` 接 GitHub raw URL → `AsyncImage` 加载 0.jpg / 1.jpg
   - 用 `TimelineView` 每秒切换两帧做 cross-fade(跟 web 端一致)
   - 中文动作名:用现有的 28 个内置动作 + LLM 批量翻译剩余 770 个(JSON 文件)

### Phase 2(下周)— 2-3 天

2. **加 Lottie 做 onboarding / 完成屏**:
   - 装 `lottie-ios` SPM 包
   - 从 LottieFiles 挑 5-8 个免费健身动画(欢迎、完成、空状态、设置图标)
   - 这部分要的是"装饰",Lottie 生态最快

### Phase 3(下个月)— 1-2 周

3. **可选 Rive 替换核心训练动画**:
   - 训练播放器的进度条 / 主按钮 / 完成屏 → Rive 状态机
   - 数据绑定到 `TrainingSessionStore`
   - 这部分能让训练时的"反馈感"上一个台阶

### Phase 4(以后)

4. **可选 Z-Anatomy 3D 模型**:
   - 选若干主要肌群导出 USDZ
   - 在 Library 页给每个动作页加一个 "查看 3D 肌群" 入口
   - 第 1 期可以只做 Quick Look 弹层,不需要自己绘制

---

## 5. License 风险矩阵(决策前必看)

| 资源 | License | 商用闭源 | 必须署名 | 必须开源衍生 |
|---|---|:-:|:-:|:-:|
| **yuhonas free-exercise-db** | Unlicense | ✅ | ❌ | ❌ |
| ExerciseDB | AGPL-3.0 | ❌ | — | ✅ 整 app |
| hasaneyldrm exercises-dataset | None | ❌ | — | — |
| wger | AGPL-3.0 | ❌ | — | ✅ |
| **Rive runtime** | MIT | ✅ | ❌ | ❌ |
| **Lottie runtime** | Apache 2.0 | ✅ | ❌ | ❌ |
| Lottie animations (LottieFiles) | 看具体 | 看协议 | 通常 ✅ | ❌ |
| **Z-Anatomy** | CC BY-SA 4.0 | ✅ | ✅ | ✅(若修改后分发) |
| Sketchfab models | 看模型 | 看协议 | 通常 ✅ | 通常 ❌ |

> **结论**:免费 + 商用闭源 + 无衍生开源义务的组合 = `yuhonas` + `Rive`/`Lottie` 运行时 + LottieFiles 免费包(检查每个的协议)。Z-Anatomy 也 OK,只要不修改 mesh 后再分发。

---

## 6. 你需要做的决策

请挑一条,我去落地:

**A. 最稳健**:Phase 1(yuhonas 图片)→ 先把现在的渐变占位换成真实双帧动图,不上动画 / 3D,验证视觉效果后再扩展。

**B. 平衡**:Phase 1 + Phase 2(yuhonas 图 + Lottie 装饰动画)。这是大多数主流健身 app 的实际做法。

**C. 激进**:Phase 1 + Phase 3(yuhonas 图 + Rive 状态机)。视觉效果最强,但需要团队学一下 Rive 编辑器。

**D. 全套**:Phase 1 + 2 + 3 + 4。最完整但开发周期 4-6 周。

**E. 自定义**:你说哪个组合,我去做。

---

## Sources

- [yuhonas/free-exercise-db (Unlicense, 800 exercises)](https://github.com/yuhonas/free-exercise-db)
- [Free Exercise DB browseable frontend](https://yuhonas.github.io/free-exercise-db/)
- [ExerciseDB API (AGPL-3.0, 11k+ exercises)](https://github.com/ExerciseDB/exercisedb-api)
- [hasaneyldrm/exercises-dataset (no license)](https://github.com/hasaneyldrm/exercises-dataset)
- [wger fitness platform](https://github.com/wger-project/wger)
- [Rive iOS SDK](https://github.com/rive-app/rive-ios)
- [Rive vs Lottie 2026 comparison](https://www.rivemasterclass.com/blog/rive-vs-lottie-in-20260why-interactive-logic-data-binding-scripting-make-rive-the-future-of-ui-animation)
- [Callstack Lottie vs Rive benchmark](https://www.callstack.com/blog/lottie-vs-rive-optimizing-mobile-app-animation)
- [LottieFiles fitness animations](https://lottiefiles.com/free-animations/fitness)
- [Z-Anatomy open source 3D atlas](https://www.z-anatomy.com/)
- [Z-Anatomy on itch.io (CC BY-SA 4.0)](https://lluisv.itch.io/z-anatomy)
- [Sketchfab anatomy-muscle tag](https://sketchfab.com/tags/anatomy-muscle)
- [Meshy.ai muscle models](https://www.meshy.ai/tags/muscle)
- [Apple Quick Look for 3D content](https://developer.apple.com/augmented-reality/quick-look/)
