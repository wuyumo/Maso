import SwiftUI
import UIKit

// 通用 share 按钮 — 点击 → 弹 customize sheet (含 preview + 卡内"添加照片"入口) → 渲染图 → 原生 share.
//
// 用法:
//   ShareImageButton(previewTitle: "My Workout") { photo, onTapAddPhoto in
//       WorkoutCompleteShareCard(session: ..., userPhoto: photo, onTapAddPhoto: onTapAddPhoto)
//   } label: {
//       Image(systemName: "square.and.arrow.up")
//   }
//
// shareContent 闭包参数:
//   - photo: 当前选的 UIImage. 没选 = nil. card 内根据它决定要不要显示 photo banner.
//   - onTapAddPhoto: card 内"添加照片"占位 tap 时调. preview 模式非 nil; 渲染最终图时 nil
//     (让 banner 在最终图里不渲染占位 UI).
struct ShareImageButton<ShareContent: View, Label: View>: View {
    let previewTitle: String
    @ViewBuilder let shareContent: (UIImage?, (() -> Void)?) -> ShareContent
    @ViewBuilder let label: () -> Label

    @State private var showCustomize = false

    var body: some View {
        Button(action: { showCustomize = true }, label: label)
            .buttonStyle(.plain)
            .sheet(isPresented: $showCustomize) {
                ShareCustomizeSheet(
                    previewTitle: previewTitle,
                    shareContent: shareContent
                )
            }
    }
}

/// 用户在分享前的 customize sheet:
///   - 实时 preview share card (卡内有 photo 占位入口)
///   - tap 占位区 / tap 已选照片 → confirmationDialog 选 Camera / Photos / Remove
///   - 最终 Share 按钮 → 渲染最终图 (传 nil callback, banner 不渲染占位) → 弹原生 share sheet
///
/// 之前底部有 [Camera] [Photos] [Remove] 按钮栏 — 删了, 入口移到卡内 photo banner 上.
struct ShareCustomizeSheet<ShareContent: View>: View {
    let previewTitle: String
    @ViewBuilder let shareContent: (UIImage?, (() -> Void)?) -> ShareContent

    @State private var userPhoto: UIImage? = nil
    /// 用 sheet(item:) 模式 — source 自身驱动 sheet, 避免 "set source + set bool" 双 state
    /// 同 event cycle 顺序 bug (会导致第一次点 camera 实际打开 library).
    @State private var activePicker: PhotoPickerSource? = nil
    @State private var renderedImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var showPhotoOptions = false
    @State private var isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // Preview — 传 userPhoto + tap callback. callback 设 showPhotoOptions = true →
                // confirmationDialog 弹 Camera / Photos / Remove 选项.
                shareContent(userPhoto, { showPhotoOptions = true })
                    .frame(width: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { renderAndShare() }
                        .fontWeight(.bold)
                }
            }
            // 系统 confirmationDialog — iOS 原生 bottom action sheet 风格, 跟 Mail / Photos
            // 加附件 / 加图片选项交互一致. 比 custom 底栏 native + 清爽.
            .confirmationDialog(
                NSLocalizedString("Add photo", comment: ""),
                isPresented: $showPhotoOptions,
                titleVisibility: .visible
            ) {
                if isCameraAvailable {
                    Button(NSLocalizedString("Take Photo", comment: "")) {
                        activePicker = .camera
                    }
                }
                Button(NSLocalizedString("Choose from Library", comment: "")) {
                    activePicker = .photoLibrary
                }
                if userPhoto != nil {
                    Button(NSLocalizedString("Remove Photo", comment: ""), role: .destructive) {
                        userPhoto = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activePicker) { source in
                PhotoPicker(image: $userPhoto, source: source)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = renderedImage {
                    ActivityViewController(activityItems: [img])
                }
            }
        }
    }

    private func renderAndShare() {
        // 渲染时传 nil callback — banner 在没 photo 时返回 EmptyView, 最终图不含占位 UI.
        let img = ShareImageRenderer.render { shareContent(userPhoto, nil) }
        guard let img else { return }
        renderedImage = img
        showShareSheet = true
    }
}

/// UIActivityViewController wrapper — 弹原生 share sheet, 用户选 AirDrop / Messages / Instagram 等.
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
