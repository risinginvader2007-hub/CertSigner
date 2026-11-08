import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit document picker. Uses `asCopy: true`, so the URL handed back is a copy in
/// the app's tmp folder and can be read directly (no security-scoped access needed).
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.item]
    var onPresented: () -> Void = {}
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        let presented = onPresented
        DispatchQueue.main.async { presented() }
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            } else {
                parent.onCancel()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
