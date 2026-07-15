# Masso 产品深度调研 — 2026-07

> 方法:20 个调研 agent 并行(人群/竞品网络调研 ×2 + 代码功能盘点 ×1 + 三条 user flow 截图走查 ×3 + 综合 ×2 + 对抗复核 ×12),78 条原始发现 → 38 条综合 → 逐条代码/截图复核。
> 范围:App 版本 2.0.2 (build 20) 时点的 main 分支。截图用 showcase 种子数据。
> 状态标记:✅ = 本次已直接修复;🔶 = 需要 Yumo 拍板;📋 = 纯记录。

---

## 0. 一句话结论

产品底子很好:核心记录链路(2 tap 记一组、休息屏 UP NEXT+上次记录+Adjust)、免费档配置(盘计算器/Live Activity/Watch 镜像/恢复模型,在竞品处都是 Pro 或招牌)、反功能立场(无社交流/无连胜绑架)都是真实资产。
最大的三个坑:**①差异化故事没兑现**(首屏隆重展示肌肉恢复,但今日推荐一行都没用它);**②AI 用错了地方**(用户被验证买账的是"下次该加多重",不是"帮我生成周计划";前者恰好没有);**③视觉语言自相矛盾**(同一个品牌绿在三屏表达三种相反含义)。

---

## 1a. 目前存在的问题(按影响排序)

| # | 问题 | 证据 | 状态 |
|---|---|---|---|
| 1 | **肌肉图三屏三义**:Today 恢复图 绿=疲劳(越疲劳越亮),同屏 routine 卡 绿=今天要练,History 会话卡 绿=当时练到(还没图例)。单一品牌绿被赋予相反含义,9pt 透明度图例(1.0/0.6/0.3)肉眼难辨 | MuscleStatusOverviewCard.swift:85-88 | 🔶 系统性视觉决策 |
| 2 | **今日推荐没用恢复模型**:pickTodayPlan 是纯 LRU 轮换,零引用同屏上方的疲劳数据。「按恢复推荐」的心智被 UI 暗示了却没兑现 | RecommendedPrograms.swift:281-308;7 月审计 P1#7 未修 | 🔶 推荐算法升级 |
| 3 | **两个"开练"入口主次颠倒**:hero 位 Train the gaps 绿胶囊抢在 routine 卡播放钮之前,小屏上主 CTA 落到折叠线下 | today.png + TodayScreen.swift:134-181 | 🔶 首屏 IA |
| 4 | **「0 WEEK STREAK」踩自家红线**:连胜是 DESIGN.md 明令不做的游戏化;且口径(连续达标周)传达不了——本周练了 2 天显示 0,反激励 | progress_history.png + HistoryScreen.swift | 🔶 删指标还是换口径 |
| 5 | **语言选择器 12 选 10 死**:只打包 en+zh-Hans,选日/韩静默回落英文 | LanguagePickerSheet.swift:29 | ✅ 已修:只列已打包语言 |
| 6 | **Classics 文案指向不存在的页面**:"Open it in Routines → tap Share",现 IA 没有 Routines tab | en Localizable.strings:696 | 🔶 需定 IA 术语后统一改 |
| 7 | **AI Summary 的 Refresh 裸奔**:无冷却/无 dataHash 门,iapEnabled=false 全员 Pro,连点连发 DeepSeek 真计费,免费版零收入对冲 | AISummaryCard.swift:61-81 | 🔶 建议加 dataHash+冷却 |
| 8 | **器械筛选漏 74 个动作**:单值精确匹配 `ex.equipment == eq`,band/ez_bar/*_machine 等 21 种值在任何筛选下不可达 | ExerciseLibraryBrowser.swift:142/265 | 🔶 筛选匹配策略 |
| 9 | **本地 JSON 无云备份**:cloudkit-todo.md 自称"不兑现是定时炸弹",2.0.x 已上架仍裸奔;误删 app=历史全丢。对喊"数据归用户"的无账号 App 是最贵的理念落差 | docs/cloudkit-todo.md | 🔶 CloudKit(~30 行)|
| 10 | **DESIGN.md 与产品现实脱节**:反模式明令"不做 AI 教练聊天框",但第二 tab 就是 Coach;§3.5-3.7/§4.3-4.4/§七 描述的还是 1.x web 时代。未来任何"依文档执行"的 session 都可能砍错方向 | DESIGN.md:467 vs RootView.swift:7 | 🔶 文档大修 |
| 11 | **Workout reminders 默认开 vs「不做通知催回」红线的张力**(现实现已是温和一次性提醒,但默认 opt-out 与理念有出入,建议在 DESIGN.md 里明文划界) | SettingsScreen + DESIGN.md | 📋 |
| 12 | **虚构教练署名**:Classics 模板署名 Coach Devin/Mara/Leo,假人设背书,信任+审核双风险 | classics.png(CommunityPlans 数据) | 🔶 改成计划风格署名 |
| 13 | **免费训练选择器缺图动作霸榜**:第一屏全是绿色占位块,排序既非字母也非常用度 | free_workout.png | 🔶 排序策略 |

## 1b. 以后可能做的改进/新功能(按 用户价值×符合哲学×solo 可行性)

1. **组间渐进建议(最高优先)**——全调研唯一被真实用户反复验证"有用"的 AI:基于历史给"下次该做多重"(Dr. Muscle/Alpha Progression 靠它立住;Fitbod 的每日黑盒重排反而被弃)。Masso 的 e1RM/PR 管道已就绪,跟你记的 Pro roadmap ②(数据驱动优化建议)完全吻合。
2. **CSV/JSON 导出**——成本最低的信任杠杆,兑现"数据归用户",Strong 靠免费导出攒口碑。零红线冲突。
3. **CloudKit 无感备份**——见 1a#9,建议与开 IAP 同版上线(回填付费墙里被注释掉的 Cloud sync 卖点)。
4. **iOS Widget + Watch 表盘复杂功能**——拒绝催回通知后唯一的非侵入回访触点(pull 型展示零推送,不违宪),对冲品类 D30 留存 3-12% 的逆风。
5. **休息 ±30s 调节**——Strong/Hevy 标配,大重量组间高频刚需,改动完全局部。
6. **PR 瞬间反馈**——DESIGN.md 理念 4「PR 小高亮足够」明文许可却缺席:单次 haptic + 2 秒 toast,无累计无粒子。
7. **力量档位对照(SBD Beginner→Elite)**——e1RM 已算好、体重已收,只差一张本地系数表;呈现为事实陈述,不做升级动效。
8. **Warm-up calculator**——Strong 招牌/Hevy Pro 卖点,纯本地百分比规则。
9. **引导补问训练经验+单次时长**——现在新手和五年老炮发给 LLM 的画像一模一样;这也是新手护栏(禁高门槛动作/容量上限)的前置输入。
10. **开 IAP 前的三件套拍板**——gate 清单只锁 AI 次数/Insights Pro 卡/保存位(记录/历史/播放器零 gate);重评 3-save cap(Strong 同款被喷最狠);加 lifetime 买断档。
11. **分享物料闭环**——不建中心化市场(踩社交流红线),把分享卡做成小红书/微信群可传播的物料,分发在 app 外。
12. **把免费资产讲出来**——盘计算器/Live Activity/Watch/恢复模型这套在竞品是 Pro,现在全埋没;进 App Store 截图与文案,零代码。

## 1c. 还没被 cover 的用户需求

1. **"下次该做多重"**(见 1b#1)——价值最高的未满足需求。
2. **新手要确定感不是记录**:39% 靠预先计划获得进馆信心、52% 靠知道器械怎么用;缺两道护栏:术语白话化 + beginner 档生成 QA。
3. **逐组 RPE/RIR**(中高阶刚需 + 渐进引擎的输入)——设计上必须默认隐藏,守住"记一组 ≤2 tap"生死线。
4. **数据安全感**:换机/误删的可见保护现在为零(导出+CloudKit 双通道,缺一不可)。
5. **睡眠感知降档**:"训练 App 不知道我昨晚只睡 4 小时"是 Reddit 新兴高频抱怨;恢复模型已在首屏,只差读 HealthKit 睡眠做保守降档系数。只读睡眠一项,不做健康仪表盘。
6. **Coach 空态零示例**:0→1 生成是 aha 时刻,现在组织语言的成本全压给新用户(⚠️ 恢复 chips 会推翻你已拍板的"chips 拆除",故列这里不直接改)。
7. **动作库可发现性**:938 个动作唯一常驻入口是 Coach 左上无标签哑铃 icon,与"AI 聊天"没有心智关联。

## 1d. 已有但可能多余的功能

| 判定 | 项 | 状态 |
|---|---|---|
| 删掉 | 7 个死件:AnimeBodyView / LottieView(+Lottie SPM 依赖+lottie-pulse.json)/ 旧 Share 三卡(Session/WorkoutComplete/WeeklyFrequency,其中 SessionShareCard 还带"组数×2"假时长回归隐患)/ PlanRow / PlanRationaleCard | ✅ 已删(~2600 行+1 依赖) |
| 删掉 | CommunityScreen(586 行):唯一触发点是截图环境变量,生产不可达,ClassicsSheet 已全面承接 | ✅ 已删 |
| 删掉 | 死设置字段 quickStartOnActiveTab / hasSeenCenterTabHint(中央 tab 双形态早已退役) | ✅ 已删 |
| 降级收纳·不是删 | Insights 单页 12 个信息块与"一屏一焦点"相悖(iapEnabled=false 时 Pro 沉底排序失效);卡本身有用,该收不该砍 | 🔶 |
| 重排·不是删 | Coach [+] 菜单三项混装(破坏性的 New conversation 与 Browse Classics/Import 同居);Import from photo 双入口 | 🔶 |
| 别动 | "免费送太多"的配置恰是冷启动期最强口碑资产(竞品处是 Pro/招牌),不但不收回还该显性化 | 📋 |
| 别动 | Settings 的 Debug 组包在 #if DEBUG,Release 包不编译,截图可见只因装机是 Debug 包 | 📋 |

---

## 2a. User flow 走查(三条主链路)

**① 开练链路** `打开 → Today → (详情) → 播放器 → 休息 → 完成`:整体顺畅,亮点是休息屏(UP NEXT+上次记录+Adjust 直接可调)。问题集中在首屏:双"开练"入口主次颠倒(1a#3)、两张相邻肌肉图语义相反(1a#1)。
**② 生成链路** `Coach 空态 → 输入 → 生成卡 → 保存 → Today/ROUTINES`:生成体验好,但首尾都断——空态无一键示例(1c#6);保存后无任何指向 Today 的可视线索,"Saved to routines"胶囊长得像状态标签、点一下却静默 unsave 无 undo。
**③ 回顾链路** `Progress/History → 会话详情 → Insights`:History 信息组织清楚;Insights 藏在分段控件后+单页 12 块过载(1d)。

## 2b. 信息冗余 / 迷惑点清单(走查原始发现)

- 休息屏同组数字三处三格式:目标「× 8 · 55 kg」vs 刚记「8 × 55 kg」乘号顺序相反,相邻两行分不清哪个是接下来 🔶(统一成哪种是文案拍板)
- 休息屏 UP NEXT 显示同名动作但不说是第几组——用户最想知道"下一组 2/3" 🔶
- 同一批东西四处四个名字:routines / My Routines / library / community plans 🔶(先定唯一术语)
- History 同屏三套时间口径:周历具体日期 + THIS WEEK 分组头 + 卡片 2 DAYS AGO 相对时间 🔶
- plan_detail 无标题 sheet 顶部的名字输入框像只读标题条,不知道能改名 🔶
- Coach 空态问候语与占位符逐字重复,浪费一次给示例的机会 🔶
- composer 三键 # 最难猜(聊天语境读作话题);偏好 slider 与右上齿轮语义相近 🔶
- 动作选择器「+23 ▾」变体折叠无说明;只折 1 个时反而多一次点击 📋
- "Muscle charts on exercise tags" 是开发者措辞,UI 里不存在 "exercise tags" 叫法 🔶
- Settings "Exercise data" 分组名像数据管理,实际是训练行为开关,且与 Training 组隔了四个组 🔶
- PlansScreen.swift 里已没有 PlansScreen(首个 struct 是 ClassicsSheet)、HistoryScreen.swift 实为 Progress——按文件名找代码会迷路 📋(重命名牵动 project.yml,留给大修)

---

## 本次已直接修复(✅ 汇总)

1. 语言选择器只列已打包语言(en/简中+System Default);老用户持久化的 off-list 选择自动归位"跟随系统"。
2. 删除 8 个死件 ≈3200 行:AnimeBodyView、LottieView(+Lottie SPM 依赖+lottie-pulse.json 资源)、SessionShareCard、WorkoutCompleteShareCard(ShareStat 先迁至 ShareCardFooter.swift)、WeeklyFrequencyShareCard、PlansScreen 内 PlanRow/PlanRationaleCard、CommunityScreen(+TodayScreen/RootView 的 showcase classics 挂点)。
3. 删除死设置字段 quickStartOnActiveTab / hasSeenCenterTabHint(Codable 兼容旧数据)+ 清 4 处过时注释。

## 建议的拍板顺序(给 Yumo)

1. **先修故事**:今日推荐接入疲劳模型(1a#2)+ 肌肉图语义统一(1a#1)——这两个一起做,首屏的差异化故事就闭环了。
2. **再做钱包安全**:AI Refresh 加 dataHash+冷却(1a#7)——开 IAP 前必做。
3. **然后是 1b#1 渐进建议**——跟你的 Pro roadmap ② 是同一件事,建议作为开墙的头号 Pro 卖点。
4. 术语统一(routines 系)+ Classics 文案 + 假教练署名,一次文案 sweep 全清。
