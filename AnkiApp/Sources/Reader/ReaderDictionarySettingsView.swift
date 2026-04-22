import SwiftUI
import UniformTypeIdentifiers
import AnkiReader
import Dependencies

struct ReaderDictionarySettingsView: View {
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    @State private var libraryState = AppDictionaryLibraryState.empty
    @State private var isBusy = false
    @State private var showImporter = false
    @State private var pendingImportKind: AppDictionaryKind = .term
    @State private var errorMessage: String?
    @State private var showError = false

    private static let zipArchiveType = UTType(filenameExtension: "zip") ?? .data

    var body: some View {
        List {
            Section(L("settings_reader_dictionary_section_recommended")) {
                Button {
                    Task {
                        await downloadRecommendedDictionaries()
                    }
                } label: {
                    Label(L("settings_reader_dictionary_download_recommended"), systemImage: "arrow.down.circle")
                }
                .disabled(isBusy)
            } footer: {
                Text(L("settings_reader_dictionary_recommended_description"))
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            Section(L("settings_reader_dictionary_section_import")) {
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
            }
            .listRowBackground(Color.amgiSurfaceElevated)

            dictionarySection(
                title: L("settings_reader_dictionary_section_term"),
                icon: "text.book.closed",
                kind: .term,
                dictionaries: libraryState.termDictionaries
            )

            dictionarySection(
                title: L("settings_reader_dictionary_section_frequency"),
                icon: "chart.bar",
                kind: .frequency,
                dictionaries: libraryState.frequencyDictionaries
            )

            dictionarySection(
                title: L("settings_reader_dictionary_section_pitch"),
                icon: "waveform.path.ecg",
                kind: .pitch,
                dictionaries: libraryState.pitchDictionaries
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_dictionary_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
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
            await refreshState()
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

    private func show(_ error: any Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}