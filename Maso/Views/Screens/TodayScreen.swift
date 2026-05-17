import SwiftUI

struct TodayScreen: View {
    @Environment(DataStore.self) private var data
    let onStart: (Plan) -> Void
    /// 拉起"自由训练" flow — Today 卡片下方按钮触发, 走 QuickWorkout sheet 选肌肉 / 动作 / 开练
    let onFreeWorkout: () -> Void

    /// 卡片 tap → 弹 plan detail sheet 查看动作 + 每组 sets/reps/weight
    @State private var detailPlan: Plan? = nil

    private var suggested: Plan? {
        // 优先 AI 生成的今日计划; 没有 (AI 关闭 / API key 未填 / 网络失败) → fallback 系统推荐
        data.aiTodayPlan ?? data.todayRecommendedPlan
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let key: String
        switch h {
        case 0..<5:   key = "Late Night"
        case 5..<12:  key = "Good Morning"
        case 12..<18: key = "Good Afternoon"
        default:      key = "Good Evening"
        }
        // 走 NSLocalizedString — Text("...") 的 LocalizedStringKey 自动查表只对字面量生效,
        // 这里返回的是 var, 必须显式查表才能拿到译文
        return NSLocalizedString(key, comment: "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // DESIGN §2.4: page 顶部留白 56pt
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(MasoColor.accent)
                    // 标题: 跟 Plans / History 一样的 26pt bold, 全 tab 视觉对齐.
                    // 长翻译仍允许换行 (lineLimit 3), 但默认环境通常 1 行就放下.
                    Text("Today's Workout")
                        // 中间 tab (Today) 是"主屏" — 标题比左右两个 tab (Plans/History 26pt) 大一档,
                        // iOS HIG Title 1 标准 28pt, 视觉上凸显这是 app 的核心入口.
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, MasoMetrics.pagePaddingTop)

                if let plan = suggested {
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        kicker: "Recommended",
                        onStart: { onStart(plan) },
                        onShowDetail: { detailPlan = plan }
                    )
                } else {
                    Text("No training plans yet")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.vertical, 60)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 自由训练入口 — 不依赖今日推荐. 用户想完全自定义 / 临时加练时走这条.
                // 去掉 accent 描边: 之前的 25% accent 边框让它跟 WorkoutCard 视觉对立感太强,
                // 改成纯 surface 卡片 (跟 WorkoutCard 同卡片底色) — 入口归入口, 不喧宾夺主.
                Button(action: onFreeWorkout) {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Free workout")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(MasoColor.text)
                            Text("Pick your own exercises and go")
                                .font(.system(size: 11))
                                .foregroundStyle(MasoColor.textDim)
                                .lineLimit(1)
                        }
                        Spacer()
                        // 跟 PlanPlayer 主播放按钮的中央三角形一致 (play.fill).
                        // 颜色 / 尺寸保留原 chevron 设置, 只换 symbol 形状 → 视觉语义统一为"开始训练".
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.vertical, 14)
                    .background(MasoColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                }
                .buttonStyle(.plain)

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
        // 详情 sheet — 复用 PlanDetailSheet, 用户在里面可看每个动作的 sets/reps/weight,
        // 也能编辑 (跟 Plans tab 进入是同款体验).
        // onStart 回调走 TodayScreen 自己的 onStart, 让用户在 detail 内开练也走统一入口.
        .sheet(item: $detailPlan) { plan in
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in
                    detailPlan = nil
                    DispatchQueue.main.async { onStart(p) }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
}
