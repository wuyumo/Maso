import SwiftUI

// 训练完成分享卡 — 跟 CompletedView 视觉一致, 加关键数据 + body hint.
//
// 信息层级 (从上到下):
//   - 大圆 ✓ (accent)
//   - "Workout Complete" 主标题
//   - Plan name 副标题
//   - 关键数据行: 时长 / 组数 / PR (if any)
//   - BodyHint 显示练到的肌群
//   - Footer
struct WorkoutCompleteShareCard: View {
    let planName: String
    let durationSeconds: Int
    let setCount: Int
    let prCount: Int
    let muscles: [MuscleGroup]
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式 (ShareCustomizeSheet) 传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    private var durationLabel: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var body: some View {
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(spacing: 18) {
                Spacer(minLength: userPhoto == nil ? 30 : 16)

                // 完成圆环 ✓
                ZStack {
                    Circle().fill(MasoColor.accent).frame(width: 76, height: 76)
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.black)
                }

                VStack(spacing: 6) {
                    Text("Workout Complete")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    if !planName.isEmpty {
                        Text(planName)
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                // 关键数据 — 横排 stat
                HStack(spacing: 18) {
                    ShareStat(value: durationLabel, label: NSLocalizedString("Duration", comment: ""))
                    ShareStat(value: "\(setCount)", label: NSLocalizedString("Sets", comment: ""))
                    if prCount > 0 {
                        ShareStat(value: "🏆\(prCount)", label: NSLocalizedString("PR", comment: "share stat — personal record"))
                    }
                }
                .padding(.top, 4)

                // BodyHint — 显示练到的肌群
                if !muscles.isEmpty {
                    BodyHint(muscles: muscles, height: 140, region: detectBodyRegion(muscles))
                        .padding(.top, 8)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)

            ShareCardFooter(qrPayload: MasoLinks.appStore)
        }
        .background(MasoColor.background)
    }
}

/// 共用的 stat 单元 — 大数字 + 下方小 label
struct ShareStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
                .foregroundStyle(MasoColor.text)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(MasoColor.textDim)
        }
    }
}
