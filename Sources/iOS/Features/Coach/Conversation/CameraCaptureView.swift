import SwiftUI
import UIKit

/// Inline camera capture sheet content. Uses `UIImagePickerController` so we
/// stay on the system camera UI without dragging in AVFoundation.
///
/// On simulators (or any device without a rear camera) we fall back to the
/// photo library picker so the conversation flow still works in the IDE.
struct CameraCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let raw = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage)
            parent.image = raw?.resizedForCoach(maxDimension: 1024)
            parent.onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

extension UIImage {
    /// Downscales the image so its longest edge is `maxDimension` px while
    /// preserving aspect ratio. Returns the original if it already fits.
    func resizedForCoach(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
