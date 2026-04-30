import SwiftUI
import UIKit
import AVFoundation

enum NoteEditorMediaAction {
    case photoLibrary
    case camera
    case file
    case audioRecording
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImageData: (Data) -> Void
        private let onCancel: () -> Void

        init(onImageData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImageData = onImageData
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard
                let image = info[.originalImage] as? UIImage,
                let data = image.jpegData(compressionQuality: 0.92)
            else {
                onCancel()
                return
            }
            onImageData(data)
        }
    }
}

struct AudioRecordingSheet: View {
    let onCancel: () -> Void
    let onFinishRecording: (URL) -> Void

    @StateObject private var recorder = AudioRecorderController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(recorder.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(recorder.elapsedText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Button(recorder.isRecording ? L("rich_text_audio_stop") : L("rich_text_audio_start")) {
                    if recorder.isRecording {
                        if let url = recorder.stop(save: true) {
                            onFinishRecording(url)
                        }
                    } else {
                        recorder.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(L("common_cancel"), role: .cancel) {
                    recorder.cancel()
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .navigationTitle(L("rich_text_action_record_audio"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.cancel()
            }
        }
    }
}

private final class AudioRecorderController: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsedText = "00:00"
    @Published var statusText = L("rich_text_audio_ready")

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var outputURL: URL?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else {
                    self.statusText = L("rich_text_audio_permission_denied")
                    return
                }

                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)

                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("recording-\(UUID().uuidString).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44_100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                    ]

                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.prepareToRecord()
                    recorder.record()

                    self.recorder = recorder
                    self.outputURL = url
                    self.startedAt = Date()
                    self.isRecording = true
                    self.statusText = L("rich_text_audio_recording")
                    self.elapsedText = "00:00"
                    self.startTimer()
                } catch {
                    self.statusText = error.localizedDescription
                }
            }
        }
    }

    func stop(save: Bool) -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        startedAt = nil
        isRecording = false
        statusText = L("rich_text_audio_ready")

        defer {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }

        guard let url = outputURL else { return nil }
        outputURL = nil
        if save {
            return url
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    func cancel() {
        _ = stop(save: false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            self.elapsedText = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        }
    }
}
