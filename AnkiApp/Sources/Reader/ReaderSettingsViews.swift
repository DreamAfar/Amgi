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
    @AppStorage(ReaderPreferences.Keys.hideFurigana) private var hideFurigana = false
    @AppStorage(ReaderPreferences.Keys.horizontalPadding) private var horizontalPadding = 5
    @AppStorage(ReaderPreferences.Keys.verticalPadding) private var verticalPadding = 0
    @AppStorage(ReaderPreferences.Keys.layoutAdvanced) private var layoutAdvanced = false
    @AppStorage(ReaderPreferences.Keys.lineHeight) private var lineHeight = 1.65
    @AppStorage(ReaderPreferences.Keys.characterSpacing) private var characterSpacing = 0.0
    @AppStorage(ReaderPreferences.Keys.showTitle) private var showTitle = true
    @AppStorage(ReaderPreferences.Keys.showPercentage) private var showPercentage = true
    @AppStorage(ReaderPreferences.Keys.showProgressTop) private var showProgressTop = true
    @AppStorage(ReaderPreferences.Keys.popupWidth) private var popupWidth = 320
    @AppStorage(ReaderPreferences.Keys.popupHeight) private var popupHeight = 250
    @AppStorage(ReaderPreferences.Keys.popupFullWidth) private var popupFullWidth = false
    @AppStorage(ReaderPreferences.Keys.popupSwipeToDismiss) private var popupSwipeToDismiss = false

    var body: some View {
        List {
            Section(L("settings_reader_display_section_text")) {
                HStack {
                    Text(L("settings_reader_text_orientation"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Picker("", selection: $verticalLayout) {
                        Text(L("settings_reader_text_orientation_vertical")).tag(true)
                        Text(L("settings_reader_text_orientation_horizontal")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }

                HStack {
                    Text(L("settings_reader_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", readerFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $readerFontSize, in: 16...40)
                        .labelsHidden()
                }

                Toggle(L("settings_reader_hide_furigana"), isOn: $hideFurigana)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_display_section_layout")) {
                HStack {
                    Text(L("settings_reader_horizontal_padding"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_padding_value", horizontalPadding))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $horizontalPadding, in: 0...20)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_vertical_padding"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_padding_value", verticalPadding))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $verticalPadding, in: 0...20)
                        .labelsHidden()
                }

                Toggle(L("settings_reader_layout_advanced"), isOn: $layoutAdvanced)

                if layoutAdvanced {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("settings_reader_line_height"))
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            Text(L("settings_reader_line_height_value", lineHeight))
                                .foregroundStyle(SettingsValueStyle.highlight)
                        }
                        Slider(value: $lineHeight, in: 1.0...2.5, step: 0.05)
                            .tint(Color.amgiAccent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("settings_reader_character_spacing"))
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            Text(L("settings_reader_character_spacing_value", Int(characterSpacing)))
                                .foregroundStyle(SettingsValueStyle.highlight)
                        }
                        Slider(value: $characterSpacing, in: -10...10, step: 1)
                            .tint(Color.amgiAccent)
                    }
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_display_section_display")) {
                Toggle(L("settings_reader_display_show_title"), isOn: $showTitle)
                Toggle(L("settings_reader_display_show_percentage"), isOn: $showPercentage)

                HStack {
                    Text(L("settings_reader_display_progress_position"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Picker("", selection: $showProgressTop) {
                        Text(L("settings_reader_display_progress_position_top")).tag(true)
                        Text(L("settings_reader_display_progress_position_bottom")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_display_section_popup")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("settings_reader_popup_width"))
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                        Text("\(popupWidth)")
                            .foregroundStyle(SettingsValueStyle.highlight)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(popupWidth) },
                            set: { popupWidth = Int($0.rounded()) }
                        ),
                        in: 240...420,
                        step: 10
                    )
                    .tint(Color.amgiAccent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("settings_reader_popup_height"))
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                        Text("\(popupHeight)")
                            .foregroundStyle(SettingsValueStyle.highlight)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(popupHeight) },
                            set: { popupHeight = Int($0.rounded()) }
                        ),
                        in: 180...420,
                        step: 10
                    )
                    .tint(Color.amgiAccent)
                }

                Toggle(L("settings_reader_popup_full_width"), isOn: $popupFullWidth)
                Toggle(L("settings_reader_popup_swipe_to_dismiss"), isOn: $popupSwipeToDismiss)
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
                NavigationLink {
                    ReaderSourceSettingsView()
                } label: {
                    Label(L("settings_reader_section_source"), systemImage: "tray.full")
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReaderDisplaySettingsView()
                } label: {
                    Label(L("settings_reader_display_settings"), systemImage: "paintbrush")
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReaderDictionarySettingsView()
                } label: {
                    Label(L("settings_reader_dictionary_settings"), systemImage: "character.book.closed")
                        .foregroundStyle(SettingsValueStyle.primary)
                }
            }
            .amgiSettingsListRowSurface()

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
        .navigationBarTitleDisplayMode(.large)
    }
}