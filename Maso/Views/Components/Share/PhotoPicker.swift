import SwiftUI
import PhotosUI
import UIKit

// 用户选自己照片 — 给 share card 加 hero banner 用.
//
// 两种 source:
//   - .photoLibrary → PHPickerViewController (iOS 14+, 无需相册访问权限, 用户挑完就给一张图)
//   - .camera → UIImagePickerController (拍照, 需要 NSCameraUsageDescription)
enum PhotoPickerSource: Identifiable {
    case photoLibrary
    case camera

    var id: Self { self }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let source: PhotoPickerSource
    var onLoadFailure: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .photoLibrary:
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .images
            let vc = PHPickerViewController(configuration: config)
            vc.delegate = context.coordinator
            return vc
        case .camera:
            let vc = UIImagePickerController()
            vc.sourceType = .camera
            vc.allowsEditing = false
            vc.delegate = context.coordinator
            return vc
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, dismissPicker: { dismiss() }, onLoadFailure: onLoadFailure)
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate,
                              UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let image: Binding<UIImage?>
        private let dismissPicker: () -> Void
        private let onLoadFailure: (() -> Void)?
        private var finished = false

        init(image: Binding<UIImage?>, dismissPicker: @escaping () -> Void,
             onLoadFailure: (() -> Void)? = nil) {
            self.image = image
            self.dismissPicker = dismissPicker
            self.onLoadFailure = onLoadFailure
        }

        private func finish(_ selectedImage: UIImage?, failed: Bool = false) {
            guard !finished else { return }
            finished = true
            if let selectedImage { image.wrappedValue = selectedImage }
            if failed { onLoadFailure?() }
            // SwiftUI owns this presentation. Do not also call UIKit dismiss:
            // moving the camera view twice can abort the keyboard layout engine.
            dismissPicker()
        }

        // PHPicker (library)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item = results.first?.itemProvider else { finish(nil); return }
            guard item.canLoadObject(ofClass: UIImage.self) else { finish(nil, failed: true); return }
            // Load before closing so the owner's onDismiss can consume the result.
            item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                Task { @MainActor in
                    self?.finish(obj as? UIImage, failed: !(obj is UIImage))
                }
            }
        }

        // UIImagePicker (camera)
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finish(info[.originalImage] as? UIImage, failed: !(info[.originalImage] is UIImage))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(nil)
        }
    }
}

/// Bound the camera's decoded preview and normalize its orientation before AI encoding.
enum MealPhotoPreparation {
    @MainActor
    static func preview(_ image: UIImage, maxDimension: CGFloat = 1280) -> UIImage? {
        let original = image.size
        guard original.width.isFinite, original.height.isFinite,
              original.width > 0, original.height > 0,
              maxDimension.isFinite, maxDimension > 0 else { return nil }
        let scale = min(1, maxDimension / max(original.width, original.height))
        let size = CGSize(width: original.width * scale, height: original.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
