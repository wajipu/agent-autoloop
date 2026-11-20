import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 附件选择：相册（多选）、拍照、文件（任意类型）。
struct AttachmentPicker: View {
    @Binding var images: [(name: String, data: Data)]
    @Binding var files: [(name: String, data: Data)]
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var showPhotoPicker: Bool
    @Binding var showFilePicker: Bool
    @Binding var showCamera: Bool
    var showCameraButton = true
    var onPickedPhoto: (PhotosPickerItem) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                pickerButton("相册", icon: "photo.on.rectangle") { showPhotoPicker = true }
                pickerButton("拍照", icon: "camera") { showCamera = true }
                pickerButton("文件", icon: "folder") { showFilePicker = true }
            }

            ForEach(Array(images.enumerated()), id: \.offset) { _, item in
                row(name: item.name, data: item.data, isImage: true) {
                    images.removeAll { $0.name == item.name }
                }
            }
            ForEach(Array(files.enumerated()), id: \.offset) { _, item in
                row(name: item.name, data: item.data, isImage: false) {
                    files.removeAll { $0.name == item.name }
                }
            }
        }
    }

    private func pickerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func row(name: String, data: Data, isImage: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            if isImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: iconFor(name))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.footnote).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func iconFor(_ name: String) -> String {
        switch true {
        case name.hasSuffix(".pdf"): "doc.richtext"
        case name.hasSuffix(".zip") || name.hasSuffix(".gz"): "doc.zipper"
        case name.hasSuffix(".log") || name.hasSuffix(".txt"): "doc.plaintext"
        case name.hasSuffix(".json") || name.hasSuffix(".har"): "curlybraces.square"
        default: "doc"
        }
    }
}


struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
