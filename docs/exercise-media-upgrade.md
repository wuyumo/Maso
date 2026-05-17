# 训练动图升级路径 (TODO)

## 现状 (2026-05)

- **当前来源**: [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain)
- **每动作媒体**: 2 张 JPG (`0.jpg` / `1.jpg`, 各 ~40-85KB)
- **CDN**: jsdelivr GitHub mirror, 稳定
- **渲染**: `CrossFadeFrames.swift` 两帧 cross-fade + Ken Burns 微动 (scale ±1% / offset ±1pt)
- **节奏**: 1.5s 周期, 0.5s 过渡
- **法律状态**: ✅ 完全干净 (public domain), 无 attribution / 无 license viral 风险

## 为什么不直接升级到"真视频/GIF"

调研结论 (2026-05): **干净免费可商用的真"短视频/GIF"数据集不存在**.

| 候选 | 评估 |
|---|---|
| [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset) | ❌ "educational and non-commercial only" |
| [exercisedb-pro/exercisedb-dataset (WorkoutX)](https://github.com/exercisedb-pro/exercisedb-dataset) | 💰 一次性付费购买, perpetual commercial license |
| [ExerciseDB API](https://github.com/ExerciseDB/exercisedb-api) | ❌ AGPL-3.0 (闭源 app viral 风险) |
| [BodyIQDB](https://github.com/BodyIQDB/workout-exercise-animation-dataset) | ❌ AGPL-3.0 + 付费购买 |
| [wger](https://github.com/wger-project/wger) | ❌ AGPL-3.0 + CC-BY-SA (viral) |
| [MuscleWiki API](https://api.musclewiki.com/documentation) | 💰 付费 API (MP4 stream) |
| [YMove](https://ymove.app/exercise-api) | 💰 $19-299/mo (Starter 带水印) |
| [Pexels Video API](https://www.pexels.com/api/) | ⚠️ 通用 fitness 素材, 不按动作分类, 不能 1:1 替换具体动作 |

## Fallback 升级方案 (有商业化需求再启动)

### Plan B: WorkoutX 一次性付费购买 + 自托管

**何时启动**: 产品付费用户达到 ~100 / 月营收 > $200 时, 这笔投入回本

**步骤**:
1. 在 [exercisedbpro.com](https://github.com/exercisedb-pro/exercisedb-dataset) 走 Gumroad 一次性付费 (~$50-100, 待确认)
2. 下载 1,300+ GIF + 元数据 JSON
3. 自托管到 Cloudflare R2 / Vercel Blob (~$5/mo CDN), URL pattern e.g.
   `https://cdn.maso.app/exercises/{folder}/anim.gif`
4. Maso 端改动:
   - 在 `Data/ExerciseLibrary.swift` 的 `ExerciseImageURL` 加 `.gif(folder:)` 方法
   - 新建 `Views/Components/AnimatedGifView.swift` 用 [SDWebImageSwiftUI](https://github.com/SDWebImage/SDWebImageSwiftUI) 渲染 GIF
   - SPM 加 SDWebImage / SDWebImageSwiftUI 依赖
   - `CrossFadeFrames` 改成 conditional 渲染 — 有 GIF 走 AnimatedGifView, 没 GIF fallback yuhonas 双帧 cross-fade
   - 用 yuhonas 的 exercise.id ↔ WorkoutX folder 映射表 (新建 `exercise-gif-map.json`)
5. 渐进迁移: 先迁高频 100 个动作 (覆盖 80% 用户使用), 剩余继续 yuhonas

**风险点**:
- WorkoutX 元数据可能跟 yuhonas 的 exercise.id 对不上 — 要建映射表
- GIF 文件比 JPG 大 (~500KB-2MB), CDN 流量成本翻倍
- iOS SDWebImage 增加 ~2MB 二进制 + 启动时间影响

### Plan C: 自建 GIF (从 yuhonas 2 帧用 AI morph 生成中间帧)

**何时启动**: WorkoutX 价格不合算 / 想保持 public domain 状态时

**步骤**:
1. build-time 脚本: 用 [Real-CUGAN](https://github.com/bilibili/ailab) / [FILM](https://github.com/google-research/frame-interpolation) 在 yuhonas 0.jpg + 1.jpg 间插值生成 6-8 中间帧
2. 把 10 帧合成成 GIF (`ffmpeg` palette + dither)
3. 上传到 self-hosted CDN
4. iOS 同 Plan B 的 SDWebImageSwiftUI 接入

**风险**:
- AI 插值出来的中间帧可能不真实 (人体姿势会扭曲), 不一定比 cross-fade 好
- 873 动作 × 10 帧 × ~80KB = ~700MB 总素材
- 工程量大 (一次性脚本 + Q/A 全部动作)

## 实施优先级

- **现在**: 维持 Plan A (yuhonas + cross-fade + Ken Burns 微动) — 已上线
- **6 个月后回头看**: 用户对动图质量的反馈是否还有 pain → 决定是否走 Plan B
- **Plan C 仅作技术备选**: 工程复杂度高, 不轻易启动
