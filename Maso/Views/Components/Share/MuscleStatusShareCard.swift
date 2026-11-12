import SwiftUI

// 当天/本周肌肉状态分享卡.
//
// 信息层级:
//   - "Muscle Status" 标题 + 日期
//   - 大 BodyHint (跟 HistoryScreen 顶部卡片同款衰减 opacity)
//   - 关键数据: 本周训练次数 / 总组数 / 涉及部位
//   - Footer
struct MuscleStatusShareCard: View {
    /// muscle → (颜色, 透明度) 恢复热图映射 (绿=可以练 / 蓝=疲劳)
    let muscleStyle: (MuscleGroup) -> (Color, Double)?
    let workoutsThisWeek: Int
    let totalSetsThisWeek: Int
    let muscleSectionsHit: Int  // 涉及多少个大肌群 section (chest/back/...)
    let coarseOnly: Bool
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    private var todayLabel: String {
        let df = DateFormatter()
        df.locale = LanguageManager.currentLocale
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            if onTapAddPhoto != nil {
                ShareSelectableCard(id: "muscle-photo", title: NSLocalizedString("Photo", comment: "")) {
                    SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
                }.padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
            VStack(spacing: 14) {
                Spacer(minLength: 24)

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

                ShareSelectableCard(id: "muscle-map", title: NSLocalizedString("Muscle Status", comment: "")) {
                // BodyHint — 同 HistoryScreen 同尺寸 + 同衰减 mapping
                ShareMuscleMap2D(muscleStyle: muscleStyle, height: 148)
                .padding(.top, 4)

                }
                ShareSelectableCard(id: "muscle-summary", title: NSLocalizedString("Workouts", comment: "")) {
                // 关键数据 — 标签走本地化 (跟 ShareCardFooter 的 stat 标签同一套键)
                HStack(spacing: 18) {
                    ShareStat(value: "\(workoutsThisWeek)", label: NSLocalizedString("Workouts", comment: ""))
                    ShareStat(value: "\(totalSetsThisWeek)", label: NSLocalizedString("Total Sets", comment: "share stat — weekly total sets"))
                    ShareStat(value: "\(muscleSectionsHit)", label: NSLocalizedString("Groups Hit", comment: "share stat — muscle sections hit"))
                }
                .padding(.top, 4)

                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, ShareLayout.contentInset)
            .frame(maxWidth: .infinity)

            ShareCardFooter(qrPayload: MasoLinks.appStore, photo: userPhoto, photoSelectionID: "muscle-photo")
        }
        .background(MasoColor.background)
    }
}
