import SwiftUI
import AnkiBackend
import AnkiKit
import AnkiClients
import Dependencies

struct ReaderSettingsHomeView: View {
    @AppStorage(ReaderPreferences.Keys.showTab) private var isReaderTabEnabled = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $isReaderTabEnabled) {
                    Label(L("settings_reader_show_tab"), systemImage: "square.bottomthird.inset.filled")
                        .foregroundStyle(SettingsValueStyle.primary)
                }
            } footer: {
                Text(L("settings_reader_show_tab_description"))
            }
            .amgiSettingsListRowSurface()

            Section {
                NavigationLink {
                    ReaderLibraryView()
                } label: {
                    Label(L("settings_reader_open_library"), systemImage: "books.vertical")
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.primary)
                }
            }
            .amgiSettingsListRowSurface()

            Section {
                NavigationLink {
                    ReaderSourceSettingsView()
                } label: {
                    Label(L("settings_reader_section_source"), systemImage: "tray.full")
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReaderDictionarySettingsView()
                } label: {
                    Label(L("settings_reader_manage_dictionaries"), systemImage: "character.book.closed")
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReaderDisplaySettingsView()
                } label: {
                    Label(L("settings_reader_display_settings"), systemImage: "paintbrush")
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReaderAdvancedSettingsView()
                } label: {
                    Label(L("settings_reader_advanced_settings"), systemImage: "gearshape.2")
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.primary)
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_reader"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReaderSourceSettingsView: View {
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.ankiBackend) var backend

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.notetypeID) private var selectedNotetypeID = 0
    @AppStorage(ReaderPreferences.Keys.bookIDField) private var bookIDField = ""
    @AppStorage(ReaderPreferences.Keys.bookTitleField) private var bookTitleField = ""
    @AppStorage(ReaderPreferences.Keys.chapterTitleField) private var chapterTitleField = ""
    @AppStorage(ReaderPreferences.Keys.chapterOrderField) private var chapterOrderField = ""
    @AppStorage(ReaderPreferences.Keys.contentField) private var contentField = ""
    @AppStorage(ReaderPreferences.Keys.languageField) private var languageField = ""

    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(Int64, String)] = []
    @State private var availableFields: [String] = []

    private var selectedDeckLabel: String {
        guard !decks.isEmpty else {
            return L("settings_reader_no_decks")
        }
        guard selectedDeckID != 0 else {
            return L("settings_reader_not_set")
        }
        return decks.first(where: { Int($0.id) == selectedDeckID })?.name ?? L("settings_reader_not_set")
    }

    private var selectedNotetypeLabel: String {
        guard !notetypeNames.isEmpty else {
            return L("settings_reader_no_notetypes")
        }
        guard selectedNotetypeID != 0 else {
            return L("settings_reader_not_set")
        }
        return notetypeNames.first(where: { Int($0.0) == selectedNotetypeID })?.1 ?? L("settings_reader_not_set")
    }

    var body: some View {
        List {
            Section(L("settings_reader_section_source")) {
                HStack {
                    Label(L("settings_reader_deck"), systemImage: "books.vertical")
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_reader_deck"), selection: $selectedDeckID) {
                            Text(L("settings_reader_not_set"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(0)
                            ForEach(decks) { deck in
                                Text(deck.name)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(Int(deck.id))
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: selectedDeckLabel)
                    }
                    .disabled(decks.isEmpty)
                }

                HStack {
                    Label(L("settings_reader_notetype"), systemImage: "square.text.square")
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_reader_notetype"), selection: $selectedNotetypeID) {
                            Text(L("settings_reader_not_set"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(0)
                            ForEach(notetypeNames, id: \.0) { id, name in
                                Text(name)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(Int(id))
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: selectedNotetypeLabel)
                    }
                    .disabled(notetypeNames.isEmpty)
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_section_fields")) {
                readerFieldRow(title: L("settings_reader_book_id_field"), selection: $bookIDField)
                readerFieldRow(title: L("settings_reader_book_title_field"), selection: $bookTitleField)
                readerFieldRow(title: L("settings_reader_chapter_title_field"), selection: $chapterTitleField)
                readerFieldRow(title: L("settings_reader_chapter_order_field"), selection: $chapterOrderField)
                readerFieldRow(title: L("settings_reader_content_field"), selection: $contentField)
                readerFieldRow(title: L("settings_reader_language_field"), selection: $languageField)
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_section_source"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .onChange(of: selectedNotetypeID) {
            loadAvailableFields()
        }
    }

    @ViewBuilder
    private func readerFieldRow(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(SettingsValueStyle.primary)
            Spacer()
            Menu {
                Picker(title, selection: selection) {
                    Text(L("settings_reader_not_set"))
                        .foregroundStyle(SettingsValueStyle.highlight)
                        .tag("")
                    ForEach(availableFields, id: \.self) { fieldName in
                        Text(fieldName)
                            .foregroundStyle(SettingsValueStyle.highlight)
                            .tag(fieldName)
                    }
                }
            } label: {
                SettingsOptionCapsuleLabel(title: selection.wrappedValue.isEmpty ? L("settings_reader_not_set") : selection.wrappedValue)
            }
            .disabled(availableFields.isEmpty)
        }
    }

    private func loadData() async {
        decks = (try? deckClient.fetchNamesOnly()) ?? []

        do {
            notetypeNames = try loadStandardNotetypeEntries(backend: backend)
        } catch {
            notetypeNames = []
        }

        if selectedDeckID != 0, !decks.contains(where: { Int($0.id) == selectedDeckID }) {
            selectedDeckID = 0
        }

        if selectedNotetypeID != 0,
           !notetypeNames.contains(where: { Int($0.0) == selectedNotetypeID }) {
            selectedNotetypeID = 0
        }

        loadAvailableFields()
    }

    private func loadAvailableFields() {
        guard selectedNotetypeID != 0 else {
            availableFields = []
            clearInvalidFieldSelections(validFields: [])
            return
        }

        do {
            let notetype = try fetchNotetype(backend: backend, id: Int64(selectedNotetypeID))
            availableFields = notetype.fields.map(\.name)
            clearInvalidFieldSelections(validFields: availableFields)
        } catch {
            availableFields = []
            clearInvalidFieldSelections(validFields: [])
        }
    }

    private func clearInvalidFieldSelections(validFields: [String]) {
        if !validFields.contains(bookIDField) {
            bookIDField = ""
        }
        if !validFields.contains(bookTitleField) {
            bookTitleField = ""
        }
        if !validFields.contains(chapterTitleField) {
            chapterTitleField = ""
        }
        if !validFields.contains(chapterOrderField) {
            chapterOrderField = ""
        }
        if !validFields.contains(contentField) {
            contentField = ""
        }
        if !validFields.contains(languageField) {
            languageField = ""
        }
    }
}

struct ReaderDisplaySettingsView: View {
    @AppStorage(ReaderPreferences.Keys.verticalLayout) private var verticalLayout = false
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24

    var body: some View {
        List {
            Section(L("settings_reader_display_settings")) {
                Toggle(L("settings_reader_vertical_layout"), isOn: $verticalLayout)

                HStack {
                    Text(L("settings_reader_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", readerFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $readerFontSize, in: 16...40)
                        .labelsHidden()
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_display_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReaderAdvancedSettingsView: View {
    @AppStorage(ReaderPreferences.Keys.tapLookup) private var tapLookupEnabled = true

    var body: some View {
        List {
            Section {
                Toggle(L("settings_reader_tap_lookup"), isOn: $tapLookupEnabled)
                    .foregroundStyle(SettingsValueStyle.primary)
            } footer: {
                Text(L("settings_reader_tap_lookup_description"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_advanced_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}