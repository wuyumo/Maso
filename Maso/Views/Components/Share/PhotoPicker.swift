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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate,
                              UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        // PHPicker (library)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else { return }
            item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                if let img = obj as? UIImage {
                    DispatchQueue.main.async { self?.parent.image = img }
                }
            }
        }

        // UIImagePicker (camera)
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
