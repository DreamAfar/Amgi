import SwiftUI
import UniformTypeIdentifiers
import AnkiReader
import Dependencies

struct ReaderDictionarySettingsView: View {
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient
    @AppStorage(ReaderPreferences.Keys.dictionaryMaxResults) private var maxResults = 16
    @AppStorage(ReaderPreferences.Keys.dictionaryScanLength) private var scanLength = 16
    @AppStorage(ReaderPreferences.Keys.popupCollapseDictionaries) private var collapseDictionaries = false
    @AppStorage(ReaderPreferences.Keys.popupCompactGlossaries) private var compactGlossaries = true
    @AppStorage(ReaderPreferences.Keys.popupAudioSourceTemplate) private var audioSourceTemplate = ReaderLookupAudioDefaults.defaultTemplate
    @AppStorage(ReaderPreferences.Keys.popupLocalAudioEnabled) private var localAudioEnabled = false
    @AppStorage(ReaderPreferences.Keys.popupAudioAutoplay) private var audioAutoplay = false
    @AppStorage(ReaderPreferences.Keys.popupAudioPlaybackMode) private var audioPlaybackModeRawValue = ReaderLookupAudioPlaybackMode.interrupt.rawValue
    @AppStorage(ReaderPreferences.Keys.popupDebugInfoEnabled) private var popupDebugInfoEnabled = false

    @State private var libraryState = AppDictionaryLibraryState.empty
    @State private var isBusy = false
    @State private var showImporter = false
    @State private var pendingImportKind: AppDictionaryKind = .term
    @State private var selectedDictionaryKind: AppDictionaryKind = .term
    @State private var errorMessage: String?
    @State private var showError = false

    private static let zipArchiveType = UTType(filenameExtension: "zip") ?? .data

    private var selectedDictionaries: [AppDictionaryInfo] {
        switch selectedDictionaryKind {
        case .term:
            return libraryState.termDictionaries
        case .frequency:
            return libraryState.frequencyDictionaries
        case .pitch:
            return libraryState.pitchDictionaries
        }
    }

    private var hasUpdatableDictionaries: Bool {
        (libraryState.termDictionaries + libraryState.frequencyDictionaries + libraryState.pitchDictionaries)
            .contains { $0.index.isUpdatable && $0.index.indexURL.isEmpty == false }
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        await downloadRecommendedDictionaries()
                    }
                } label: {
                    Label(L("settings_reader_dictionary_download_recommended"), systemImage: "arrow.down.circle")
                }
                .disabled(isBusy)

                Button {
                    Task {
                        await updateDictionaries()
                    }
                } label: {
                    Label(L("settings_reader_dictionary_update"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isBusy || hasUpdatableDictionaries == false)
            } header: {
                Text(L("settings_reader_dictionary_section_recommended"))
            } footer: {
                Text(L("settings_reader_dictionary_recommended_description"))
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            Section(L("settings_reader_dictionary_section_settings")) {
                HStack {
                    Text(L("settings_reader_dictionary_max_results"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    Text("\(maxResults)")
                        .foregroundStyle(Color.amgiAccent)
                    Stepper("", value: $maxResults, in: 1...50)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_dictionary_scan_length"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    Text("\(scanLength)")
                        .foregroundStyle(Color.amgiAccent)
                    Stepper("", value: $scanLength, in: 1...64)
                        .labelsHidden()
                }

                Toggle(L("settings_reader_dictionary_collapse_dictionaries"), isOn: $collapseDictionaries)
                    .foregroundStyle(Color.amgiTextPrimary)

                Toggle(L("settings_reader_dictionary_compact_glossaries"), isOn: $compactGlossaries)
                    .foregroundStyle(Color.amgiTextPrimary)

                Toggle(L("settings_reader_dictionary_popup_debug_info"), isOn: $popupDebugInfoEnabled)
                    .foregroundStyle(Color.amgiTextPrimary)
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            Section(L("settings_reader_dictionary_section_audio")) {
                Toggle(L("settings_reader_dictionary_local_audio"), isOn: $localAudioEnabled)
                    .foregroundStyle(Color.amgiTextPrimary)

                Toggle(L("settings_reader_dictionary_audio_autoplay"), isOn: $audioAutoplay)
                    .foregroundStyle(Color.amgiTextPrimary)

                Picker(
                    L("settings_reader_dictionary_audio_playback_mode"),
                    selection: Binding(
                        get: { ReaderLookupAudioDefaults.resolvedPlaybackMode(audioPlaybackModeRawValue) },
                        set: { audioPlaybackModeRawValue = $0.rawValue }
                    )
                ) {
                    ForEach(ReaderLookupAudioPlaybackMode.allCases) { mode in
                        Text(title(for: mode)).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("settings_reader_dictionary_audio_source_template"))
                        .foregroundStyle(Color.amgiTextPrimary)

                    TextField("", text: $audioSourceTemplate, prompt: Text(ReaderLookupAudioDefaults.defaultTemplate))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            Section {
                Picker("", selection: $selectedDictionaryKind) {
                    ForEach(AppDictionaryKind.allCases) { kind in
                        Text(title(for: kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            dictionarySection(
                title: title(for: selectedDictionaryKind),
                icon: icon(for: selectedDictionaryKind),
                kind: selectedDictionaryKind,
                dictionaries: selectedDictionaries
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_dictionary_settings"))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isBusy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    importButton(
                        title: L("settings_reader_dictionary_import_term"),
                        systemImage: "text.book.closed",
                        kind: .term
                    )

                    importButton(
                        title: L("settings_reader_dictionary_import_frequency"),
                        systemImage: "chart.bar",
                        kind: .frequency
                    )

                    importButton(
                        title: L("settings_reader_dictionary_import_pitch"),
                        systemImage: "waveform.path.ecg",
                        kind: .pitch
                    )
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if isBusy {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L("settings_reader_dictionary_busy"))
                            .font(.footnote)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .task {
            ReaderLookupLocalAudioServer.shared.setEnabled(localAudioEnabled)
            await refreshState()
        }
        .onChange(of: localAudioEnabled) { _, enabled in
            ReaderLookupLocalAudioServer.shared.setEnabled(enabled)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [Self.zipArchiveType],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task {
                    await importArchives(urls, kind: pendingImportKind)
                }
            case let .failure(error):
                show(error)
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
    }

    @ViewBuilder
    private func dictionarySection(
        title: String,
        icon: String,
        kind: AppDictionaryKind,
        dictionaries: [AppDictionaryInfo]
    ) -> some View {
        Section(title) {
            if dictionaries.isEmpty {
                Text(L("settings_reader_dictionary_empty"))
                    .foregroundStyle(Color.amgiTextSecondary)
            } else {
                ForEach(dictionaries) { dictionary in
                    Toggle(
                        isOn: Binding(
                            get: { dictionary.isEnabled },
                            set: { enabled in
                                Task {
                                    await setEnabled(kind: kind, dictionaryID: dictionary.id, enabled: enabled)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(dictionary.title, systemImage: icon)
                                .foregroundStyle(Color.amgiTextPrimary)
                            if !dictionary.index.revision.isEmpty {
                                Text(L("settings_reader_dictionary_revision", dictionary.index.revision))
                                    .font(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    Task {
                        await deleteDictionaries(at: offsets, kind: kind, dictionaries: dictionaries)
                    }
                }
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private func importButton(title: String, systemImage: String, kind: AppDictionaryKind) -> some View {
        Button {
            pendingImportKind = kind
            showImporter = true
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func refreshState() async {
        isBusy = true
        defer { isBusy = false }

        do {
            libraryState = try await dictionaryLookupClient.loadState()
        } catch {
            show(error)
        }
    }

    private func downloadRecommendedDictionaries() async {
        isBusy = true
        defer { isBusy = false }

        do {
            libraryState = try await dictionaryLookupClient.importRecommended()
        } catch {
            show(error)
        }
    }

    private func importArchives(_ urls: [URL], kind: AppDictionaryKind) async {
        guard !urls.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            libraryState = try await dictionaryLookupClient.importArchives(urls, kind)
        } catch {
            show(error)
        }
    }

    private func setEnabled(kind: AppDictionaryKind, dictionaryID: String, enabled: Bool) async {
        do {
            libraryState = try await dictionaryLookupClient.setEnabled(kind, dictionaryID, enabled)
        } catch {
            show(error)
        }
    }

    private func deleteDictionaries(
        at offsets: IndexSet,
        kind: AppDictionaryKind,
        dictionaries: [AppDictionaryInfo]
    ) async {
        for index in offsets {
            guard dictionaries.indices.contains(index) else { continue }
            do {
                libraryState = try await dictionaryLookupClient.delete(kind, dictionaries[index].id)
            } catch {
                show(error)
            }
        }
    }

    private func updateDictionaries() async {
        isBusy = true
        defer { isBusy = false }

        do {
            libraryState = try await dictionaryLookupClient.updateDictionaries()
        } catch {
            show(error)
        }
    }

    private func title(for mode: ReaderLookupAudioPlaybackMode) -> String {
        switch mode {
        case .interrupt:
            return L("settings_reader_dictionary_audio_mode_interrupt")
        case .duck:
            return L("settings_reader_dictionary_audio_mode_duck")
        case .mix:
            return L("settings_reader_dictionary_audio_mode_mix")
        }
    }

    private func title(for kind: AppDictionaryKind) -> String {
        switch kind {
        case .term:
            return L("settings_reader_dictionary_section_term")
        case .frequency:
            return L("settings_reader_dictionary_section_frequency")
        case .pitch:
            return L("settings_reader_dictionary_section_pitch")
        }
    }

    private func icon(for kind: AppDictionaryKind) -> String {
        switch kind {
        case .term:
            return "text.book.closed"
        case .frequency:
            return "chart.bar"
        case .pitch:
            return "waveform.path.ecg"
        }
    }

    private func show(_ error: any Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
