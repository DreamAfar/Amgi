import SwiftUI
import AnkiBackend
import AnkiKit
import AnkiClients
import Dependencies
import UIKit

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
    @AppStorage(ReaderPreferences.Keys.themeMode) private var themeModeRawValue = ReaderThemeMode.system.rawValue
    @AppStorage(ReaderPreferences.Keys.customContentColor) private var customContentColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customBackgroundColor) private var customBackgroundColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customTextColor) private var customTextColorHex = "#17212F"
    @AppStorage(ReaderPreferences.Keys.customHintColor) private var customHintColorHex = "#7F7F7F"
    @AppStorage(ReaderPreferences.Keys.popupWidth) private var popupWidth = 320
    @AppStorage(ReaderPreferences.Keys.popupHeight) private var popupHeight = 250
    @AppStorage(ReaderPreferences.Keys.popupFontSize) private var popupFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupFrequencyFontSize) private var popupFrequencyFontSize = 13
    @AppStorage(ReaderPreferences.Keys.popupContentFontSize) private var popupContentFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupDictionaryNameFontSize) private var popupDictionaryNameFontSize = 13
    @AppStorage(ReaderPreferences.Keys.popupKanaFontSize) private var popupKanaFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupFullWidth) private var popupFullWidth = false
    @AppStorage(ReaderPreferences.Keys.popupSwipeToDismiss) private var popupSwipeToDismiss = false

    private var themeMode: ReaderThemeMode {
        get { ReaderThemeMode(rawValue: themeModeRawValue) ?? .system }
        set { themeModeRawValue = newValue.rawValue }
    }

    private var customContentColorBinding: Binding<Color> {
        Binding(
            get: { Color(readerHex: customContentColorHex, fallback: .init(red: 1.0, green: 253 / 255, blue: 248 / 255)) },
            set: { customContentColorHex = $0.readerHexString() }
        )
    }

    private var customBackgroundColorBinding: Binding<Color> {
        Binding(
            get: { Color(readerHex: customBackgroundColorHex, fallback: .init(red: 1.0, green: 253 / 255, blue: 248 / 255)) },
            set: { customBackgroundColorHex = $0.readerHexString() }
        )
    }

    private var customTextColorBinding: Binding<Color> {
        Binding(
            get: { Color(readerHex: customTextColorHex, fallback: .init(red: 23 / 255, green: 33 / 255, blue: 47 / 255)) },
            set: { customTextColorHex = $0.readerHexString() }
        )
    }

    private var customHintColorBinding: Binding<Color> {
        Binding(
            get: { Color(readerHex: customHintColorHex, fallback: .init(red: 127 / 255, green: 127 / 255, blue: 127 / 255)) },
            set: { customHintColorHex = $0.readerHexString() }
        )
    }

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
                HStack {
                    Text(L("settings_reader_theme_mode"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Picker("", selection: Binding(get: { themeMode }, set: { themeMode = $0 })) {
                        Text(L("settings_reader_theme_mode_system")).tag(ReaderThemeMode.system)
                        Text(L("settings_reader_theme_mode_eye_care")).tag(ReaderThemeMode.eyeCare)
                        Text(L("settings_reader_theme_mode_sepia")).tag(ReaderThemeMode.sepia)
                        Text(L("settings_reader_theme_mode_custom")).tag(ReaderThemeMode.custom)
                    }
                    .pickerStyle(.menu)
                }

                if themeMode == .custom {
                    ColorPicker(L("settings_reader_theme_custom_content_color"), selection: customContentColorBinding, supportsOpacity: false)
                    ColorPicker(L("settings_reader_theme_custom_background_color"), selection: customBackgroundColorBinding, supportsOpacity: false)
                    ColorPicker(L("settings_reader_theme_custom_text_color"), selection: customTextColorBinding, supportsOpacity: false)
                    ColorPicker(L("settings_reader_theme_custom_hint_color"), selection: customHintColorBinding, supportsOpacity: false)
                }

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
                HStack {
                    Text(L("settings_reader_popup_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", popupFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $popupFontSize, in: 10...30)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_popup_frequency_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", popupFrequencyFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $popupFrequencyFontSize, in: 10...30)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_popup_content_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", popupContentFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $popupContentFontSize, in: 10...30)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_popup_dictionary_name_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", popupDictionaryNameFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $popupDictionaryNameFontSize, in: 10...30)
                        .labelsHidden()
                }

                HStack {
                    Text(L("settings_reader_popup_kana_font_size"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Text(L("settings_reader_font_size_value", popupKanaFontSize))
                        .foregroundStyle(SettingsValueStyle.highlight)
                    Stepper("", value: $popupKanaFontSize, in: 10...30)
                        .labelsHidden()
                }

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

private extension Color {
    init(readerHex: String, fallback: Color) {
        let sanitized = readerHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count == 6,
              let value = Int(sanitized, radix: 16) else {
            self = fallback
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }

    func readerHexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct ReaderAdvancedSettingsView: View {
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.ankiBackend) var backend

    @AppStorage(ReaderPreferences.Keys.tapLookup) private var tapLookupEnabled = true
    @AppStorage(ReaderPreferences.Keys.lookupNoteTemplate) private var lookupNoteTemplateData = ""

    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(Int64, String)] = []
    @State private var availableFields: [String] = []

    private var lookupNoteTemplate: ReaderLookupNoteTemplate {
        ReaderLookupNoteTemplate.decode(from: lookupNoteTemplateData)
    }

    private var selectedTemplateDeckLabel: String {
        guard !decks.isEmpty else {
            return L("settings_reader_no_decks")
        }
        guard let deckID = lookupNoteTemplate.deckID else {
            return L("settings_reader_not_set")
        }
        return decks.first(where: { $0.id == deckID })?.name ?? L("settings_reader_not_set")
    }

    private var selectedTemplateNotetypeLabel: String {
        guard !notetypeNames.isEmpty else {
            return L("settings_reader_no_notetypes")
        }
        guard let notetypeID = lookupNoteTemplate.notetypeID else {
            return L("settings_reader_not_set")
        }
        return notetypeNames.first(where: { $0.0 == notetypeID })?.1 ?? L("settings_reader_not_set")
    }

    private var templateDeckSelection: Binding<Int> {
        Binding(
            get: { lookupNoteTemplate.deckID.map { Int($0) } ?? 0 },
            set: { newValue in
                updateTemplate { template in
                    template.deckID = newValue == 0 ? nil : Int64(newValue)
                }
            }
        )
    }

    private var templateNotetypeSelection: Binding<Int> {
        Binding(
            get: { lookupNoteTemplate.notetypeID.map { Int($0) } ?? 0 },
            set: { newValue in
                let resolvedID = newValue == 0 ? nil : Int64(newValue)
                updateTemplate { template in
                    template.notetypeID = resolvedID
                }
                loadTemplateFields(for: resolvedID)
            }
        )
    }

    var body: some View {
        List {
            Section {
                Toggle(L("settings_reader_tap_lookup"), isOn: $tapLookupEnabled)
                    .foregroundStyle(SettingsValueStyle.primary)
            } footer: {
                Text(L("settings_reader_tap_lookup_description"))
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_note_add_settings")) {
                HStack {
                    Label(L("settings_reader_note_template_deck"), systemImage: "rectangle.stack")
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_reader_note_template_deck"), selection: templateDeckSelection) {
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
                        SettingsOptionCapsuleLabel(title: selectedTemplateDeckLabel)
                    }
                    .disabled(decks.isEmpty)
                }

                HStack {
                    Label(L("settings_reader_note_template_notetype"), systemImage: "square.text.square")
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_reader_note_template_notetype"), selection: templateNotetypeSelection) {
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
                        SettingsOptionCapsuleLabel(title: selectedTemplateNotetypeLabel)
                    }
                    .disabled(notetypeNames.isEmpty)
                }
            } footer: {
                Text(L("settings_reader_note_add_settings_description"))
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_reader_note_template_fields")) {
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_term_field"),
                    selection: templateFieldBinding(\.termField)
                )
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_reading_field"),
                    selection: templateFieldBinding(\.readingField)
                )
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_sentence_field"),
                    selection: templateFieldBinding(\.sentenceField)
                )
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_definition1_field"),
                    selection: templateFieldBinding(\.definition1Field)
                )
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_definition2_field"),
                    selection: templateFieldBinding(\.definition2Field)
                )
                noteTemplateFieldRow(
                    title: L("settings_reader_note_template_definition3_field"),
                    selection: templateFieldBinding(\.definition3Field)
                )
            } footer: {
                Text(L("settings_reader_note_template_supported_fields"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_reader_advanced_settings"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
    }

    @ViewBuilder
    private func noteTemplateFieldRow(title: String, selection: Binding<String>) -> some View {
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

    private func templateFieldBinding(_ keyPath: WritableKeyPath<ReaderLookupNoteTemplate, String>) -> Binding<String> {
        Binding(
            get: { lookupNoteTemplate[keyPath: keyPath] },
            set: { newValue in
                updateTemplate { template in
                    template[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func loadData() async {
        decks = (try? deckClient.fetchNamesOnly()) ?? []

        do {
            notetypeNames = try loadStandardNotetypeEntries(backend: backend)
        } catch {
            notetypeNames = []
        }

        var template = lookupNoteTemplate
        if let deckID = template.deckID,
           !decks.contains(where: { $0.id == deckID }) {
            template.deckID = nil
        }
        if let notetypeID = template.notetypeID,
           !notetypeNames.contains(where: { $0.0 == notetypeID }) {
            template.notetypeID = nil
            template.clearInvalidFields(validFields: [])
        }
        storeTemplateIfChanged(template)
        loadTemplateFields(for: template.notetypeID)
    }

    private func loadTemplateFields(for notetypeID: Int64?) {
        guard let notetypeID else {
            availableFields = []
            updateTemplate { template in
                template.clearInvalidFields(validFields: [])
            }
            return
        }

        do {
            let notetype = try fetchNotetype(backend: backend, id: notetypeID)
            availableFields = notetype.fields.map(\.name)
            updateTemplate { template in
                template.clearInvalidFields(validFields: availableFields)
            }
        } catch {
            availableFields = []
            updateTemplate { template in
                template.clearInvalidFields(validFields: [])
            }
        }
    }

    private func updateTemplate(_ update: (inout ReaderLookupNoteTemplate) -> Void) {
        var template = lookupNoteTemplate
        update(&template)
        storeTemplateIfChanged(template)
    }

    private func storeTemplateIfChanged(_ template: ReaderLookupNoteTemplate) {
        guard template != lookupNoteTemplate else {
            return
        }
        lookupNoteTemplateData = template.encodedString()
    }
}
