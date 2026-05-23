# Exercise DB Overhaul — Plan & Schema (v1.1 — 用户拍板版)

**变更 from v1.0 draft**:
- ✅ Sub-muscle 名单 OK, 27 个不变
- ✅ Schema 加 3 个字段: `video_url`, `calories_estimate`, `danger_warnings`
- ⚠️ Anatomy 图需要**重画** (用户拍板, 接受前 4 次失败的风险)
- ✅ 缺图 fallback: Placeholder + category icon

---



**目标**: 把现 873 动作的库扩到 ~1500, 加 2 层肌群层级 + 多维 category, Hevy 命名风格, 兼容现有图片素材.

**Driver**: 上 App Store 之前做完 (用户选择 II 方案).

**预估**: 6-8 个工作日 (含验证), 跑批生成阶段会用多 agent 并行加速.

---

## Phase 0 — Schema 设计 (本文)

✅ **必须先你 review 通过本文, 我才能开 Phase 1**

### 0.1 新 Exercise schema

```jsonc
{
  "id": "bench_press_barbell",         // snake_case, 全局唯一, 也是 image folder key
  "name": {
    "en": "Bench Press (Barbell)",     // Hevy 命名: 动作 + (器械)
    "zh-Hans": "卧推 (杠铃)"
  },
  "muscles": {
    "primary": [                       // 1-2 个 sub-muscle (主要发力)
      { "major": "chest", "sub": "middle_chest" }
    ],
    "secondary": [                     // 协同肌, 多个
      { "major": "shoulders", "sub": "front_delt" },
      { "major": "arms", "sub": "triceps" }
    ]
  },
  "equipment": ["barbell", "bench_flat"],     // 1-N 个
  "category": "strength",              // 7 个枚举 (见 0.4)
  "movementPattern": "push_horizontal",// 6 个枚举 (见 0.5)
  "mechanic": "compound",              // compound | isolation
  "unilateral": false,                 // 单边 | 双边
  "tempo": "strength",                 // 5 个 tempo profile (见 0.6)
  "level": "intermediate",             // beginner | intermediate | advanced
  "force": "push",                     // push | pull | static
  "imageFolder": "Barbell_Bench_Press_-_Medium-Grip",  // 旧库 fuzzy match 出的 folder, null = 缺图
  "instructions": {
    "en": ["Lie on bench...", "..."],          // 2-4 行 form cue, 不要超长 paragraph
    "zh-Hans": ["躺在卧推凳上...", "..."]
  },
  "video_url": "https://www.youtube.com/watch?v=xxx", // YouTube 链接, 国内访问问题让 v1.1 再优化
  "calories_estimate": {
    "low": 4,                                  // body weight 60kg, 10 min, kcal
    "med": 6,                                  // body weight 75kg
    "high": 9                                  // body weight 90kg+
  },
  "danger_warnings": {
    "en": ["Don't round lower back at bottom of lift."],
    "zh-Hans": ["底部不要圆背."]
  }
}
```

**注**:
- `video_url`: 优先 YouTube, 因为 free + 全球可访问 (大陆需翻墙, 但有 v1.1 时间换 bilibili / 中间代理)
- `calories_estimate`: 简化的 MET 表估算, 不是绝对值. 给 HealthKit 写入用
- `danger_warnings`: 仅初/中阶动作不容易做错的不标; 中高阶 deadlift / squat / OHP 等才标

### 0.2 肌群层级 (2 层)

**6 个 Major** (顶层 chip, BodyHint 大色块):

| Major key | 显示 EN | 显示 ZH |
|---|---|---|
| `chest` | Chest | 胸 |
| `back` | Back | 背 |
| `shoulders` | Shoulders | 肩 |
| `arms` | Arms | 臂 |
| `legs` | Legs | 腿 |
| `core` | Core | 核心 |

**27 个 Sub** (BodyHint 细分高亮 + 选动作筛选用):

| Major | Sub key | EN | ZH |
|---|---|---|---|
| chest | `upper_chest` | Upper Chest | 上胸 |
| chest | `middle_chest` | Middle Chest | 中胸 |
| chest | `lower_chest` | Lower Chest | 下胸 |
| back | `lats` | Lats | 背阔肌 |
| back | `traps_upper` | Upper Traps | 上斜方肌 |
| back | `traps_middle` | Middle Traps | 中斜方肌 |
| back | `traps_lower` | Lower Traps | 下斜方肌 |
| back | `rhomboids` | Rhomboids | 菱形肌 |
| back | `lower_back` | Lower Back | 下背 (竖脊肌) |
| back | `rear_delt` | Rear Delts | 后束三角肌 |
| shoulders | `front_delt` | Front Delts | 前束三角肌 |
| shoulders | `side_delt` | Side Delts | 中束三角肌 |
| shoulders | `rear_delt_alt` | (alias of back.rear_delt) | (背肌 rear_delt 别名) |
| arms | `biceps` | Biceps | 肱二头肌 |
| arms | `triceps` | Triceps | 肱三头肌 |
| arms | `forearms` | Forearms | 前臂 |
| arms | `brachialis` | Brachialis | 肱肌 |
| legs | `quads` | Quadriceps | 股四头肌 |
| legs | `hamstrings` | Hamstrings | 腘绳肌 |
| legs | `glutes` | Glutes | 臀大肌 |
| legs | `glutes_med` | Glute Medius | 臀中肌 |
| legs | `calves` | Calves | 小腿 |
| legs | `adductors` | Adductors | 内收肌 |
| legs | `abductors` | Abductors | 外展肌 |
| legs | `tibialis` | Tibialis | 胫骨前肌 |
| core | `abs_upper` | Upper Abs | 上腹 |
| core | `abs_lower` | Lower Abs | 下腹 |
| core | `obliques` | Obliques | 腹斜肌 |
| core | `transverse` | Transverse Abdominis | 腹横肌 |

**包含关系**: 选 `middle_chest` 同时算选 `chest` (向上传递). MuscleSelector 体现这点 — 点 `chest` chip 默认包含全部 3 个 sub.

### 0.3 Equipment (更细化, ~25 个)

```
body_only, barbell, dumbbell, kettlebell, ez_curl_bar, trap_bar,
cable, machine_selectorized, machine_plate, smith_machine,
bench_flat, bench_incline, bench_decline, preacher_bench, ab_bench,
pull_up_bar, dip_station, parallettes, rings, trx,
medicine_ball, exercise_ball, foam_roller, resistance_band, ankle_strap,
plyo_box, sled, landmine, battle_rope, jump_rope, rowing_machine
```

(数字现在 31, 会按实际需要增减)

### 0.4 Category (主类别, 7 个)

```
strength            // 力量训练 (大多数)
hypertrophy_focus   // 偏增肌 (高量低强度变体)
cardio              // 有氧
stretching          // 拉伸
mobility            // 关节灵活性 (跟 stretching 区分: mobility 是 active, stretching 是 static)
plyometric          // 爆发力
calisthenics        // 自重训练 (单独标, 跟 body_only equipment 区分: 这是动作类型, 不是器械)
```

### 0.5 Movement Pattern (动作模式, 6 个)

```
push_horizontal     // 平推 (Bench Press, Push-Up)
push_vertical       // 上推 (OHP, Pike Push-Up)
pull_horizontal     // 平拉 (Bent-Over Row, Cable Row)
pull_vertical       // 下拉 (Pull-Up, Lat Pulldown)
hinge               // 髋铰链 (Deadlift, RDL, Good Morning)
squat               // 蹲 (Squat, Lunge, Step-Up)
```

特殊情况:
- 单关节 isolation 动作 (Bicep Curl, Lateral Raise) → `null`
- 拉伸 / 有氧 → `null`

### 0.6 Tempo Profile (5 个)

```
strength    // 1-5 reps, max effort
hypertrophy // 6-12 reps, 中等强度
endurance   // 15+ reps, 轻量
explosive   // plyo, 速度优先
isometric   // hold, no rep count
```

### 0.7 Hevy 命名规则 (codified)

**英文**:
- `<Movement>` (主流默认器械, 通常不标) — `Bench Press`, `Squat`, `Deadlift`
- `<Movement> (<Equipment>)` — `Bench Press (Dumbbell)`, `Squat (Goblet)`
- `<Modifier> <Movement>` (+ optional equipment) — `Incline Bench Press`, `Bulgarian Split Squat`, `Sumo Deadlift`
- 单边 / 单边器械 后缀: `(Single Arm)`, `(Single Leg)` — `Row (Dumbbell, Single Arm)`
- 角度修饰: `Incline`, `Decline`, `Flat`, `Seated`, `Standing`, `Lying`

**中文** (zh-Hans):
- 基础动作直译: `卧推`, `深蹲`, `硬拉`, `推举`, `划船`, `下拉`, `引体向上`
- 器械后缀用 `(器械中文)`: `卧推 (哑铃)`, `深蹲 (高脚杯)`, `硬拉 (相扑)`
- 角度修饰用前缀: `上斜`, `下斜`, `平`, `坐姿`, `站姿`, `俯卧`
- 单边: `(单边)`, `(单腿)`

**词典** (en → zh) — 至少 covers 这些, 跑批前我会全列出:
```
Bench Press → 卧推
Squat → 深蹲
Deadlift → 硬拉
Row → 划船
Pull-Up → 引体向上
Push-Up → 俯卧撑
Lunge → 弓步
Curl → 弯举
Press → 推举
Raise → 侧平举 (lateral) / 前平举 (front) / 反向飞鸟 (rear)
Fly → 飞鸟
Extension → 伸展
Crunch → 卷腹
Plank → 平板支撑
```

---

## Phase 1 — 数据生成 (Claude 跑批)

我用 3 个 agent 并行, 每个负责一个肌群组 (减少冲突):

| Agent | 范围 | 估算条目 |
|---|---|---|
| Agent A | 上身 push (chest / shoulders / triceps) | 400-500 |
| Agent B | 上身 pull + back + biceps | 300-400 |
| Agent C | 下身 + core + cardio + stretching | 600-700 |

每个 agent 输出 JSON, 我合并 + 去重 + 校验.

**质量保障**:
- 每个 agent 给 Hevy/Strong 的命名样本 + 本 schema, 让它严格按格式输出
- 跑完后 schema validator (Python) 检查每条记录所有字段是否合法
- 抽样 10% 人工抽查 (你来快速过)

**预计耗时**: 6-8 小时 (3 agent 各 2-3 小时并行)

---

## Phase 2 — 跟旧库 fuzzy match (preserve images)

```python
# scripts/match_old_new_exercises.py
import json
from rapidfuzz import fuzz

old = json.load(open("Maso/Resources/exercises.json"))
new = json.load(open("Maso/Resources/exercises-new.json"))

# Normalize: lowercase, strip parens, collapse spaces
def norm(s): return ...

# For each new exercise, find best-match old by name + equipment
# threshold: 85% → 自动 match. 70-85% → 进 manual review. <70% → 无图.
```

输出:
- `match_report.json` — new_id → old_id 映射, score
- `orphaned_old.json` — 旧库里没被 new 覆盖的 (= 用户要的"列表 1")
- `missing_images_new.json` — new 里没匹配到旧图的 (= 用户要的"列表 2")

**预计耗时**: 2-3 小时 (含 manual review)

---

## Phase 3 — App 端迁移

| 文件 | 改动 |
|---|---|
| `Maso/Models/Exercise.swift` | 加 `MuscleTag { major, sub }`, `MovementPattern` enum, `Tempo` enum |
| `Maso/Models/MuscleGroup.swift` (新) | 27 个 sub-muscle, `Major.subs` 映射, `Sub.major` 反向映射 |
| `Maso/Resources/exercises.json` | 替换 |
| `Maso/Data/ExerciseLibrary.swift` | 新 parser, fallback 兼容旧 JSON 字段以防滚回 |
| `Maso/Data/Anatomy.swift` | 增加 sub-muscle polygon? (你之前拒绝重画 4 次, 这里要谨慎) |
| `Maso/Views/Components/BodyHint.swift` | sub-muscle 高亮支持 |
| `Maso/Views/Components/MuscleSelector.swift` | 2 层 picker (point Major chip 展开 sub) |
| `Maso/Views/Screens/ExerciseLibraryBrowser.swift` | filter UI 改 2 层 |
| i18n strings | ~1500 名字 × 12 语言 → 用 auto_translate.py 跑 |

**预计耗时**: 3-4 天

---

## Phase 4 — 验证 + 输出报告

- 跑 SwiftUI preview / 真机过一遍主要界面
- 抽样 100 个动作验证标签准确
- 验证图片 CDN URL 全部 200 OK
- 生成最终的两个用户要的列表:
  - `orphaned_old_exercises.md`
  - `new_exercises_missing_images.md`

**预计耗时**: 1 天

---

## ⚠️ 关键风险点

1. **Anatomy 图重画** — 你之前 4 次拒绝. 如果做 sub-muscle 高亮需要更精细的 polygon. **暂定方案**: 不重画, 用现有 polygon, 只在数据层标 sub, BodyHint 视觉上还是按 major 高亮. **你 OK 吗?**

2. **中英文翻译质量** — 1500 条 × 12 lang Claude 自动翻不会全对. 至少 zh-Hans + en 我会人工质检, 其他 10 lang 跑 auto_translate 后抽样.

3. **图片缺失率** — fuzzy match 8% 阈值估计 60-70% 能 hit, 剩下 30-40% (~500 条) 没图. 解决方案: 用 generic placeholder + category icon, 或者短期内不显示图.

4. **API 兼容** — 改 schema 会让现有用户的本地数据 broken. 需要写 migration code (`data/migrations/v1_to_v2.swift`).

---

## ✅ 你要拍的事 (开 Phase 1 前)

- [ ] **27 个 sub-muscle 名单 OK 吗?** 有没有要加 / 删 / 改的?
- [ ] **Anatomy 图风险 OK 吗?** (sub-muscle 数据层标, 视觉仍按 major 高亮 — 不重画)
- [ ] **缺图怎么办**: (a) 显示 placeholder (b) 不显示图 (c) 我可以再去找别的开源动作图库
- [ ] **schema 还有什么遗漏**? (e.g. 你要不要"难度评分" / "卡路里估算" / "动作视频 URL" 等字段?)

回完这 4 个我就开 Phase 1.
