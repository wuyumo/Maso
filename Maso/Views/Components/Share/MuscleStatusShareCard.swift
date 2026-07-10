import SwiftUI

// 当天/本周肌肉状态分享卡.
//
// 信息层级:
//   - "Muscle Status" 标题 + 日期
//   - 大 BodyHint (跟 HistoryScreen 顶部卡片同款衰减 opacity)
//   - 关键数据: 本周训练次数 / 总组数 / 涉及部位
//   - Footer
struct MuscleStatusShareCard: View {
    /// 同 HistoryScreen 的 muscle → lastTrained date 映射, 给 BodyHint 算衰减 opacity
    let muscleOpacity: (MuscleGroup) -> Double?
    let workoutsThisWeek: Int
    let totalSetsThisWeek: Int
    let muscleSectionsHit: Int  // 涉及多少个大肌群 section (chest/back/...)
    let coarseOnly: Bool
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    private var todayLabel: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(spacing: 14) {
                Spacer(minLength: userPhoto == nil ? 24 : 12)

                // 标题
                VStack(spacing: 4) {
                    Text(todayLabel.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(MasoColor.accent)
                    Text("Muscle Status")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                }

                // BodyHint — 同 HistoryScreen 同尺寸 + 同衰减 mapping
                BodyHint(
                    muscles: [],
                    height: 200,
                    opacityFor: muscleOpacity,
                    coarseOnly: coarseOnly
                )
                .padding(.top, 4)

                // 关键数据 — 标签走本地化 (跟 ShareCardFooter 的 stat 标签同一套键)
                HStack(spacing: 18) {
                    ShareStat(value: "\(workoutsThisWeek)", label: NSLocalizedString("Workouts", comment: ""))
                    ShareStat(value: "\(totalSetsThisWeek)", label: NSLocalizedString("Total Sets", comment: "share stat — weekly total sets"))
                    ShareStat(value: "\(muscleSectionsHit)", label: NSLocalizedString("Groups Hit", comment: "share stat — muscle sections hit"))
                }
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)

            ShareCardFooter()
        }
        .background(MasoColor.background)
    }
}
