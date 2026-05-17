import SwiftUI

// 单次训练记录分享卡 — 给 SessionDetailSheet 的"分享这次训练" 用.
//
// 信息层级:
//   - 训练日期 kicker
//   - Plan name 标题 (或 "Quick Workout")
//   - 关键数据: 时长 / 组数 / 动作数 / PR (if any)
//   - 前 4 个动作名 chip list
//   - BodyHint 显示涉及肌群
//   - Footer
struct SessionShareCard: View {
    let session: SessionSummary
    let exerciseNames: [String]   // 取前 4 个动作 displayName
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    private var dateLabel: String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return df.string(from: session.day)
    }

    /// 训练时长估算 — 没存 explicit duration, 用 setCount × 60s + rest 时间估
    /// (实际值不重要, 给用户大致感觉就行)
    private var estimatedDurationLabel: String {
        let mins = max(5, session.setCount * 2)  // 简单估: 每组约 2 分钟 (含组间休息)
        return "~\(mins)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: userPhoto == nil ? 24 : 12)

                // 日期 kicker + plan name
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateLabel.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(MasoColor.accent)
                    Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(2)
                }

                // 关键数据
                HStack(spacing: 18) {
                    ShareStat(value: estimatedDurationLabel, label: "Duration")
                    ShareStat(value: "\(session.setCount)", label: "Sets")
                    ShareStat(value: "\(session.exerciseCount)", label: "Exercises")
                    if session.prCount > 0 {
                        ShareStat(value: "🏆\(session.prCount)", label: "PR")
                    }
                }
                .padding(.top, 2)

                // 动作 chip 列表 (前 4 个 + "+N more")
                if !exerciseNames.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(exerciseNames.prefix(4), id: \.self) { name in
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MasoColor.text.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(MasoColor.surfaceHi)
                                .clipShape(Capsule())
                        }
                        if session.exerciseCount > 4 {
                            Text("+\(session.exerciseCount - 4) more")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(MasoColor.surfaceHi)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }

                // BodyHint
                if !session.muscles.isEmpty {
                    HStack {
                        Spacer()
                        BodyHint(muscles: session.muscles, height: 140, region: detectBodyRegion(session.muscles))
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            ShareCardFooter()
        }
        .background(MasoColor.background)
    }
}
