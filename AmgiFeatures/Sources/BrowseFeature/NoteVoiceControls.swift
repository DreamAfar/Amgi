#if canImport(UIKit)
import Foundation
import SwiftUI
import Theme
import UIKit

/// Small mic button for a field's header row. Sized to the caption it sits
/// beside, so adding it doesn't make the row any taller.
struct NoteVoiceRecordButton: View {
    @Environment(\.palette) private var palette
    let recorder: VoiceRecorder
    let fieldIndex: Int
    let onRecorded: (URL) -> Void

    private var isRecordingHere: Bool { recorder.recordingFieldIndex == fieldIndex }

    var body: some View {
        Button {
            if isRecordingHere {
                if let clip = recorder.stop() { onRecorded(clip.url) }
            } else {
                Task { await recorder.start(fieldIndex: fieldIndex) }
            }
        } label: {
            if isRecordingHere, let startedAt = recorder.recordingStartedAt {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(palette.danger)
            } else {
                Label(String(localized: "Record", bundle: .module), systemImage: "mic.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(palette.accent)
            }
        }
        .buttonStyle(.borderless)
        .amgiFont(.caption)
        .disabled(recorder.isStarting || (recorder.isRecording && !isRecordingHere))
        .accessibilityLabel(isRecordingHere ? String(localized: "Stop recording", bundle: .module) : String(localized: "Record voice", bundle: .module))
    }
}

/// A single row of compact play chips under a field: one for each sound the
/// field already references (the `[sound:…]` text stays in the field, as in
/// Anki), and one for each new recording waiting to be saved. Takes no space
/// when the field has no audio.
struct NoteFieldAudioBar: View {
    @Environment(\.palette) private var palette
    let soundFiles: [String]
    let pendingClips: [URL]
    let playingURL: URL?
    let resolve: (String) -> URL?
    let onTogglePlayback: (URL) -> Void
    let onDeletePending: (URL) -> Void

    var body: some View {
        if !soundFiles.isEmpty || !pendingClips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AmgiSpacing.xs) {
                    ForEach(Array(soundFiles.enumerated()), id: \.element) { index, name in
                        chip(
                            title: String(localized: "Audio \(index + 1)", bundle: .module),
                            accessibilityName: name,
                            url: resolve(name),
                            onDelete: nil
                        )
                    }
                    ForEach(Array(pendingClips.enumerated()), id: \.element) { index, url in
                        let title = String(localized: "Recording \(index + 1)", bundle: .module)
                        chip(title: title, accessibilityName: title, url: url) { onDeletePending(url) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func chip(title: String, accessibilityName: String, url: URL?, onDelete: (() -> Void)?) -> some View {
        let isPlaying = url != nil && playingURL == url
        return HStack(spacing: 4) {
            Button {
                if let url { onTogglePlayback(url) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: url == nil ? "exclamationmark.triangle" : (isPlaying ? "stop.fill" : "play.fill"))
                        .imageScale(.small)
                    Text(title)
                }
            }
            .buttonStyle(.borderless)
            .disabled(url == nil)
            .accessibilityLabel(Text(accessibilityName))
            .accessibilityHint(url == nil
                ? Text("This audio file is missing from the media folder.", bundle: .module)
                : Text(isPlaying ? "Stops playback" : "Plays the audio", bundle: .module))

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Delete \(accessibilityName)", bundle: .module))
            }
        }
        .amgiFont(.caption)
        .foregroundStyle(url == nil ? palette.textSecondary : palette.accent)
        .padding(.horizontal, AmgiSpacing.sm)
        .padding(.vertical, AmgiSpacing.xxs)
        .background(palette.accentSoft, in: Capsule())
    }
}

/// The recorder's failure alerts, shared by Add Note and Edit Note.
struct VoiceRecorderAlerts: ViewModifier {
    let recorder: VoiceRecorder

    func body(content: Content) -> some View {
        content
            .alert(String(localized: "Microphone access is off", bundle: .module), isPresented: Binding(
                get: { recorder.failure == .permissionDenied },
                set: { if !$0 { recorder.failure = nil } }
            )) {
                Button(String(localized: "Open Settings", bundle: .module)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            } message: {
                Text("Allow microphone access in Settings to record audio onto cards.", bundle: .module)
            }
            .alert(String(localized: "Recording could not start", bundle: .module), isPresented: Binding(
                get: { recorder.failure == .couldNotStart },
                set: { if !$0 { recorder.failure = nil } }
            )) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text("Please try recording again.", bundle: .module)
            }
            .alert(String(localized: "Recording ended", bundle: .module), isPresented: Binding(
                get: { recorder.failure == .endedEarly },
                set: { if !$0 { recorder.failure = nil } }
            )) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text("Recording was interrupted or reached the 10-minute limit. The clip so far was kept.", bundle: .module)
            }
    }
}
#endif
