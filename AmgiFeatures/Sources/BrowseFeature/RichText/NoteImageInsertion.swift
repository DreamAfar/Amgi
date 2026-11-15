//
//  NoteImageInsertion.swift
//  BrowseFeature
//

#if canImport(UIKit)
import AnkiClients
import Dependencies
import Foundation
import PhotosUI
import SwiftUI
import Theme
import UIKit
import UniformTypeIdentifiers

/// The path of an image into a note field: a source is requested from a
/// field's toolbar, the picked image is adjusted, the result is written to
/// the media folder, and its filename goes back to the field that asked.
/// One per editing screen, shared by its fields through the environment;
/// owns the `mediaClient` dependency so the views carry none.
@Observable
@MainActor
final class NoteImageInsertionModel {
    /// The picker to show.
    var source: RichTextToolbar.ImageSource?
    /// The picked image, while it is being adjusted.
    var candidate: NoteImageCandidate?
    var errorMessage: String?

    @ObservationIgnored private var insert: ((String) -> Void)?
    @ObservationIgnored @Dependency(\.mediaClient) private var mediaClient

    /// Starts an insertion; `insert` receives the stored filename.
    func request(_ source: RichTextToolbar.ImageSource, insert: @escaping (String) -> Void) {
        self.insert = insert
        self.source = source
    }

    /// Takes the picked file. Waits out the picker's dismissal first: a
    /// sheet presented while another is still going away is dropped.
    func picked(_ data: Data?) async {
        source = nil
        guard let data else { return }
        guard let candidate = NoteImageCandidate(data: data) else {
            errorMessage = String(localized: "This file isn't an image that can be added.", bundle: .module)
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        self.candidate = candidate
    }

    func cancel() {
        source = nil
        candidate = nil
        insert = nil
    }

    /// Stores the adjusted image as media and hands its name to the field.
    /// Like Anki's editor, the file is written when it's inserted; if the
    /// note is then abandoned, Check Media clears it out.
    func finish(_ output: NoteImageOutput) async {
        candidate = nil
        let filename = output.filename
        do {
            try await mediaClient.save(output.data, filename)
            insert?(filename)
        } catch {
            errorMessage = error.localizedDescription
        }
        insert = nil
    }
}

extension View {
    /// Lets the note fields inside insert images: provides the insertion
    /// model to them and presents its pickers and adjust sheet.
    func noteImageInsertion() -> some View {
        modifier(NoteImageInsertion())
    }
}

private struct NoteImageInsertion: ViewModifier {
    @State private var model = NoteImageInsertionModel()
    @State private var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .environment(model)
            .photosPicker(
                isPresented: isShowing(.photoLibrary),
                selection: $photoItem,
                matching: .images
            )
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task { await model.picked(try? await item.loadTransferable(type: Data.self)) }
            }
            .fullScreenCover(isPresented: isShowing(.camera)) {
                CameraPicker { data in
                    Task { await model.picked(data) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: isShowing(.files), allowedContentTypes: [.image]) { result in
                let data = (try? result.get()).flatMap(Self.read)
                Task { await model.picked(data) }
            }
            .sheet(item: $model.candidate) { candidate in
                NoteImageAdjustSheet(
                    candidate: candidate,
                    onInsert: { output in Task { await model.finish(output) } },
                    onCancel: { model.cancel() }
                )
            }
            .alert(
                String(localized: "Couldn't Add Image", bundle: .module),
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    private func isShowing(_ source: RichTextToolbar.ImageSource) -> Binding<Bool> {
        Binding(
            get: { model.source == source },
            set: { if !$0, model.source == source { model.source = nil } }
        )
    }

    /// Files come from outside the sandbox, so reading needs the scoped grant.
    private static func read(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

/// The system camera, returning the shot as JPEG data.
private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Full quality here; the adjust sheet decides the compression.
            onFinish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif
