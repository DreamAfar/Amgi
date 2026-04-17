import SwiftUI
import AnkiBackend
import AnkiKit
import AnkiClients
import AnkiProto
import AnkiSync
import Dependencies
import SwiftProtobuf

private enum SettingsValueStyle {
    static let highlight = Color.amgiAccent
    static let primary = Color.amgiTextPrimary
    static let secondary = Color.amgiTextSecondary
}

private struct SettingsOptionCapsuleLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: AmgiSpacing.xs) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(SettingsValueStyle.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(AmgiFont.micro.font)
                .foregroundStyle(SettingsValueStyle.secondary)
        }
        .amgiCapsuleControl()
    }
}

private extension View {
    func amgiSettingsListRowSurface() -> some View {
        listRowBackground(Color.amgiSurfaceElevated)
    }
}

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("settings_theme_system")
        case .light:  return L("settings_theme_light")
        case .dark:   return L("settings_theme_dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chineseSimplified = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:            return L("settings_language_system")
        case .chineseSimplified: return L("settings_language_zh_hans")
        case .english:           return L("settings_language_en")
        case .japanese:          return L("settings_language_ja")
        }
    }

    var locale: Locale {
        switch self {
        case .system:            return .current
        case .chineseSimplified: return Locale(identifier: "zh-Hans")
        case .english:           return Locale(identifier: "en")
        case .japanese:          return Locale(identifier: "ja")
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Dependency(\.ankiBackend) var backend

    @AppStorage("app_theme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("app_language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var maintenanceMessage: String?
    @State private var showMaintenanceAlert = false
    @State private var isCheckingMedia = false
    @State private var mediaCheckResult: MediaCheckResult?
    @State private var showMediaCheckResult = false

    private var selectedTheme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: appThemeRaw) ?? .system },
            set: { appThemeRaw = $0.rawValue }
        )
    }

    private var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section(L("settings_section_basic")) {
                NavigationLink {
                    UserManagementView()
                } label: {
                    settingsRowLabel(L("settings_row_account"), icon: "person.crop.circle")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    SyncSettingsView()
                } label: {
                    settingsRowLabel(L("settings_row_sync"), icon: "arrow.triangle.2.circlepath")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    CodeEditorSettingsView()
                } label: {
                    settingsRowLabel(L("settings_row_editing"), icon: "pencil.and.scribble")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    ReviewOptionsView()
                } label: {
                    settingsRowLabel(L("settings_row_review"), icon: "rectangle.on.rectangle")
                }
                .amgiSettingsListRowSurface()
            }

            Section(L("settings_section_display")) {
                HStack {
                    Label(L("settings_picker_theme"), systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_picker_theme"), selection: selectedTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.displayName)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(theme)
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: selectedTheme.wrappedValue.displayName)
                    }
                }
                .amgiSettingsListRowSurface()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L("settings_picker_language"), systemImage: "globe")
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                        Menu {
                            Picker(L("settings_picker_language"), selection: selectedLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName)
                                        .foregroundStyle(SettingsValueStyle.highlight)
                                        .tag(lang)
                                }
                            }
                        } label: {
                            SettingsOptionCapsuleLabel(title: selectedLanguage.wrappedValue.displayName)
                        }
                    }

                    if selectedLanguage.wrappedValue != .system {
                        Text(L("settings_language_restart_hint"))
                            .amgiFont(.caption)
                            .foregroundStyle(SettingsValueStyle.secondary)
                            .padding(.leading, 28)
                    }
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    DeckListHeatmapSettingsView()
                } label: {
                    settingsRowLabel(L("settings_row_home_heatmap"), icon: "chart.bar.xaxis")
                }
                .amgiSettingsListRowSurface()
            }

            Section(L("settings_section_maintenance")) {
                NavigationLink {
                    BackupView(username: AppUserStore.loadSelectedUser())
                } label: {
                    settingsRowLabel(L("settings_row_backup"), icon: "externaldrive")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    UserFileManagerView(username: AppUserStore.loadSelectedUser())
                } label: {
                    settingsRowLabel(L("settings_row_file_manager"), icon: "folder")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    DeckTemplateListView()
                } label: {
                    settingsRowLabel(L("settings_row_deck_templates"), icon: "square.stack.3d.up")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    NotetypeFieldManagerListView()
                } label: {
                    settingsRowLabel(L("settings_row_field_manager"), icon: "text.badge.plus")
                }
                .amgiSettingsListRowSurface()

                Button {
                    checkDatabase()
                } label: {
                    HStack {
                        settingsRowLabel(L("settings_row_check_database"), icon: "checkmark.seal")
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .amgiSettingsListRowSurface()

                Button {
                    checkMedia()
                } label: {
                    if isCheckingMedia {
                        HStack {
                            settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            ProgressView()
                        }
                        .contentShape(Rectangle())
                    } else {
                        HStack {
                            settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCheckingMedia)
                .amgiSettingsListRowSurface()

                NavigationLink {
                    EmptyCardsView()
                } label: {
                    settingsRowLabel(L("settings_row_empty_cards"), icon: "rectangle.stack.badge.minus")
                }
                .amgiSettingsListRowSurface()

                NavigationLink {
                    DebugView()
                } label: {
                    settingsRowLabel(L("debug_nav_title"), icon: "ladybug")
                }
                .amgiSettingsListRowSurface()
            }

            Section(L("settings_section_other")) {
                NavigationLink {
                    AboutView()
                } label: {
                    settingsRowLabel(L("settings_row_about"), icon: "info.circle")
                }
                .amgiSettingsListRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_nav_title"))
        .alert(L("common_done"), isPresented: $showMaintenanceAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(maintenanceMessage ?? L("common_unknown_error"))
        }
        .sheet(isPresented: $showMediaCheckResult) {
            if let result = mediaCheckResult {
                MediaCheckResultView(result: result)
            }
        }
    }

    private func settingsRowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .amgiFont(.body)
            .foregroundStyle(SettingsValueStyle.primary)
    }

    private func checkDatabase() {
        do {
            let responseBytes = try backend.call(
                service: AnkiBackend.Service.collection,
                method: AnkiBackend.CheckDatabaseMethod.checkDatabase
            )
            maintenanceMessage = L("debug_check_db_ok", responseBytes.count)
            showMaintenanceAlert = true
        } catch {
            maintenanceMessage = L("debug_check_db_error", "\(error)")
            showMaintenanceAlert = true
        }
    }

    private func checkMedia() {
        isCheckingMedia = true
        let capturedBackend = backend
        Task.detached {
            do {
                let response: Anki_Media_CheckMediaResponse = try capturedBackend.invoke(
                    service: AnkiBackend.Service.media,
                    method: AnkiBackend.MediaMethod.checkMedia
                )
                let result = MediaCheckResult(
                    missing: response.missing,
                    unused: response.unused,
                    missingNoteIds: response.missingMediaNotes,
                    report: response.report,
                    haveTrash: response.haveTrash
                )
                await MainActor.run {
                    isCheckingMedia = false
                    mediaCheckResult = result
                    showMediaCheckResult = true
                }
            } catch {
                await MainActor.run {
                    isCheckingMedia = false
                    maintenanceMessage = L("media_check_error", error.localizedDescription)
                    showMaintenanceAlert = true
                }
            }
        }
    }
}

private struct SettingsInfoView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            Text(message)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.amgiBackground)
        .navigationTitle(title)
    }
}

private struct ReviewOptionsView: View {
    private enum CardAlignment: String, CaseIterable, Identifiable {
        case top
        case center

        var id: String { rawValue }

        var title: String {
            switch self {
            case .top: return L("settings_review_alignment_top")
            case .center: return L("settings_review_alignment_center")
            }
        }
    }

    @AppStorage(ReviewPreferences.Keys.autoplayAudio) private var autoplayAudio = true
    @AppStorage(ReviewPreferences.Keys.playAudioInSilentMode) private var playAudioInSilentMode = false
    @AppStorage(ReviewPreferences.Keys.showContextMenuButton) private var showContextMenuButton = true
    @AppStorage(ReviewPreferences.Keys.showAudioReplayButton) private var showAudioReplayButton = true
    @AppStorage(ReviewPreferences.Keys.showCorrectnessSymbols) private var showCorrectnessSymbols = false
    @AppStorage(ReviewPreferences.Keys.disperseAnswerButtons) private var disperseAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.showAnswerButtons) private var showAnswerButtons = true
    @AppStorage(ReviewPreferences.Keys.showRemainingDays) private var showRemainingDays = true
    @AppStorage(ReviewPreferences.Keys.showNextReviewTime) private var showNextReviewTime = false
    @AppStorage(ReviewPreferences.Keys.openLinksExternally) private var openLinksExternally = true
    @AppStorage(ReviewPreferences.Keys.cardContentAlignment) private var cardContentAlignmentRaw = CardAlignment.center.rawValue
    @AppStorage(ReviewPreferences.Keys.glassAnswerButtons) private var glassAnswerButtons = false

    private var cardAlignment: Binding<CardAlignment> {
        Binding(
            get: { CardAlignment(rawValue: cardContentAlignmentRaw) ?? .center },
            set: { cardContentAlignmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section(L("settings_review_section_audio")) {
                Toggle(L("settings_review_autoplay_audio"), isOn: $autoplayAudio)
                Toggle(L("settings_review_play_audio_in_silent_mode"), isOn: $playAudioInSilentMode)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_ui")) {
                Toggle(L("settings_review_show_context_menu_button"), isOn: $showContextMenuButton)
                Toggle(L("settings_review_show_audio_replay_button"), isOn: $showAudioReplayButton)
                Toggle(L("settings_review_show_correctness_symbols"), isOn: $showCorrectnessSymbols)
                Toggle(L("settings_review_disperse_answer_buttons"), isOn: $disperseAnswerButtons)
                Toggle(L("settings_review_show_answer_buttons"), isOn: $showAnswerButtons)
                Toggle(L("settings_review_show_remaining_days"), isOn: $showRemainingDays)
                Toggle(L("settings_review_show_next_review_time"), isOn: $showNextReviewTime)
                Toggle(L("settings_review_open_links_externally"), isOn: $openLinksExternally)

                if #available(iOS 26.0, *) {
                    Toggle(L("settings_review_glass_answer_buttons"), isOn: $glassAnswerButtons)
                }

                HStack {
                    Text(L("settings_review_card_alignment"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("settings_review_card_alignment"), selection: cardAlignment) {
                            ForEach(CardAlignment.allCases) { alignment in
                                Text(alignment.title)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(alignment)
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: cardAlignment.wrappedValue.title)
                    }
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_review"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeckListHeatmapSettingsView: View {
    @Dependency(\.deckClient) var deckClient

    @AppStorage(DeckListHeatmapSettings.showKey) private var showDeckListHeatmap = true
    @AppStorage(DeckListHeatmapSettings.heightKey) private var deckListHeatmapHeight = DeckListHeatmapSettings.defaultHeight
    @AppStorage(DeckListHeatmapSettings.scopeKey) private var heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
    @AppStorage(DeckListHeatmapSettings.selectedDeckIDKey) private var selectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID
    @AppStorage(DeckListHeatmapSettings.initialDaysKey) private var initialDaysRaw = DeckListHeatmapSettings.defaultInitialDays

    @State private var decks: [DeckInfo] = []

    private var heatmapScope: Binding<DeckListHeatmapScope> {
        Binding(
            get: { DeckListHeatmapScope(rawValue: heatmapScopeRaw) ?? .allDecks },
            set: { heatmapScopeRaw = $0.rawValue }
        )
    }

    private var heatmapScopeLabel: String {
        switch heatmapScope.wrappedValue {
        case .allDecks:
            return L("settings_display_heatmap_scope_all")
        case .selectedDeck:
            return L("settings_display_heatmap_scope_selected")
        }
    }

    private var selectedDeckLabel: String {
        decks.first(where: { Int($0.id) == selectedDeckID })?.name
            ?? L("settings_display_heatmap_selected_deck_none")
    }

    private var initialDaysLabel: String {
        HeatmapInitialDays(rawValue: initialDaysRaw)?.localizedLabel ?? L("heatmap_range_6_months")
    }

    var body: some View {
        List {
            Section(L("deck_list_heatmap_title")) {
                Toggle(L("settings_display_show_deck_heatmap"), isOn: $showDeckListHeatmap)

                if showDeckListHeatmap {
                    HStack {
                        Text(L("settings_display_heatmap_scope"))
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                        Menu {
                            Picker(L("settings_display_heatmap_scope"), selection: heatmapScope) {
                                Text(L("settings_display_heatmap_scope_all"))
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(DeckListHeatmapScope.allDecks)
                                Text(L("settings_display_heatmap_scope_selected"))
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(DeckListHeatmapScope.selectedDeck)
                            }
                        } label: {
                            SettingsOptionCapsuleLabel(title: heatmapScopeLabel)
                        }
                    }

                    if heatmapScope.wrappedValue == .selectedDeck {
                        HStack {
                            Label(L("settings_display_heatmap_selected_deck"), systemImage: "rectangle.stack")
                            Spacer()
                            Menu {
                                Picker(
                                    L("settings_display_heatmap_selected_deck"),
                                    selection: $selectedDeckID
                                ) {
                                    if decks.isEmpty {
                                        Text(L("settings_display_heatmap_selected_deck_none"))
                                            .foregroundStyle(SettingsValueStyle.highlight)
                                            .tag(DeckListHeatmapSettings.defaultSelectedDeckID)
                                    } else {
                                        ForEach(decks) { deck in
                                            Text(deck.name)
                                                .foregroundStyle(SettingsValueStyle.highlight)
                                                .tag(Int(deck.id))
                                        }
                                    }
                                }
                            } label: {
                                SettingsOptionCapsuleLabel(title: selectedDeckLabel)
                            }
                            .disabled(decks.isEmpty)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(L("settings_display_deck_heatmap_height"), systemImage: "arrow.up.and.down")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            Text(L("settings_display_deck_heatmap_height_value", Int(deckListHeatmapHeight)))
                                .foregroundStyle(SettingsValueStyle.highlight)
                        }

                        Slider(value: $deckListHeatmapHeight, in: 136...220, step: 4)
                    }

                    HStack {
                        Label(L("settings_heatmap_initial_range"), systemImage: "calendar")
                            .foregroundStyle(SettingsValueStyle.primary)
                        Spacer()
                        Menu {
                            Picker(L("settings_heatmap_initial_range"), selection: $initialDaysRaw) {
                                ForEach(HeatmapInitialDays.allCases) { option in
                                    Text(option.localizedLabel)
                                        .foregroundStyle(SettingsValueStyle.highlight)
                                        .tag(option.rawValue)
                                }
                            }
                        } label: {
                            SettingsOptionCapsuleLabel(title: initialDaysLabel)
                        }
                    }
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_home_heatmap"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDecks()
        }
        .onChange(of: heatmapScope.wrappedValue) {
            normalizeSelectedDeck()
        }
    }

    private func loadDecks() async {
        decks = (try? deckClient.fetchAll()) ?? []
        normalizeSelectedDeck()
    }

    private func normalizeSelectedDeck() {
        guard heatmapScope.wrappedValue == .selectedDeck else { return }

        let validDeckIDs = Set(decks.map { Int($0.id) })
        if validDeckIDs.isEmpty {
            selectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID
            return
        }

        if !validDeckIDs.contains(selectedDeckID), let fallback = decks.first {
            selectedDeckID = Int(fallback.id)
        }
    }
}

private struct SyncSettingsView: View {
    @Dependency(\.syncClient) var syncClient

    @AppStorage(SyncPreferences.Keys.modeForCurrentUser()) private var syncModeRaw = SyncPreferences.Mode.local.rawValue
    @AppStorage(SyncPreferences.Keys.syncMediaForCurrentUser()) private var syncMediaEnabled = true
    @AppStorage(SyncPreferences.Keys.ioTimeoutSecsForCurrentUser()) private var ioTimeoutSecs = SyncPreferences.Timeout.defaultValue
    @AppStorage(SyncPreferences.Keys.mediaLastLogForCurrentUser()) private var mediaLastLog = ""
    @AppStorage(SyncPreferences.Keys.mediaLastSyncedAtForCurrentUser()) private var mediaLastSyncedAt = 0.0

    @State private var showServerSetup = false
    @State private var showLogin = false
    @State private var isSyncingMedia = false
    @State private var syncMessage: String?
    @State private var showSyncAlert = false

    private var syncMode: SyncPreferences.Mode {
        SyncPreferences.resolvedMode(syncModeRaw)
    }

    private var timeout: SyncPreferences.Timeout {
        SyncPreferences.resolvedTimeout(ioTimeoutSecs)
    }

    private var syncModeBinding: Binding<SyncPreferences.Mode> {
        Binding(
            get: { syncMode },
            set: { newMode in
                let previousMode = syncMode
                if newMode == .custom && KeychainHelper.loadEndpoint() == nil {
                    showServerSetup = true
                    return
                }
                syncModeRaw = newMode.rawValue
                if newMode != previousMode {
                    AppSyncAuthEvents.clearCredentials()
                }
            }
        )
    }

    private var timeoutBinding: Binding<SyncPreferences.Timeout> {
        Binding(
            get: { timeout },
            set: { ioTimeoutSecs = $0.rawValue }
        )
    }

    private var timeoutLabel: String {
        L("sync_settings_timeout_seconds", timeout.rawValue)
    }

    private var serverTypeLabel: String {
        switch syncMode {
        case .official:
            return L("sync_settings_server_type_official")
        case .custom:
            return L("sync_settings_server_type_custom")
        case .local:
            return L("sync_settings_server_type_local")
        }
    }

    private var currentServerValue: String {
        switch syncMode {
        case .official:
            return SyncPreferences.officialServerLabel
        case .custom:
            return KeychainHelper.loadEndpoint() ?? L("common_none")
        case .local:
            return L("sync_local_mode_label")
        }
    }

    private var currentAccountValue: String {
        KeychainHelper.loadUsername() ?? L("sync_settings_not_logged_in")
    }

    private var formattedLastMediaSync: String {
        guard mediaLastSyncedAt > 0 else { return L("common_none") }
        return Date(timeIntervalSince1970: mediaLastSyncedAt).formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    var body: some View {
        List {
            Section(L("sync_settings_section_server")) {
                HStack {
                    Text(L("sync_settings_server_type"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("sync_settings_server_type"), selection: syncModeBinding) {
                            Text(L("sync_settings_server_type_official"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(SyncPreferences.Mode.official)
                            Text(L("sync_settings_server_type_custom"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(SyncPreferences.Mode.custom)
                            Text(L("sync_settings_server_type_local"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(SyncPreferences.Mode.local)
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: serverTypeLabel)
                    }
                }

                infoRow(title: L("sync_settings_server_type"), value: serverTypeLabel)
                infoRow(title: L("sync_settings_current_server"), value: currentServerValue)
                infoRow(title: L("sync_settings_account"), value: currentAccountValue)

                if syncMode == .custom {
                    Button(L("sync_settings_change_server")) {
                        showServerSetup = true
                    }
                    .foregroundStyle(SettingsValueStyle.highlight)
                }

                if syncMode != .local {
                    if KeychainHelper.loadHostKey() == nil {
                        Button(L("login_btn_sign_in")) {
                            showLogin = true
                        }
                        .foregroundStyle(SettingsValueStyle.highlight)
                    } else {
                        Button(L("sync_menu_logout"), role: .destructive) {
                            logout()
                        }
                    }
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("sync_settings_section_options")) {
                Toggle(L("sync_settings_sync_media"), isOn: $syncMediaEnabled)

                HStack {
                    Text(L("sync_settings_timeout"))
                        .foregroundStyle(SettingsValueStyle.primary)
                    Spacer()
                    Menu {
                        Picker(L("sync_settings_timeout"), selection: timeoutBinding) {
                            ForEach(SyncPreferences.Timeout.allCases) { option in
                                Text(L("sync_settings_timeout_seconds", option.rawValue))
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(option)
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: timeoutLabel)
                    }
                }
            }
            .amgiSettingsListRowSurface()

            if syncMode != .local {
                Section(L("sync_settings_section_media")) {
                    Button {
                        Task { await syncMediaNow() }
                    } label: {
                        HStack {
                            Label(L("sync_settings_sync_media_now"), systemImage: "photo.on.rectangle")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            if isSyncingMedia {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingMedia)

                    infoRow(title: L("sync_settings_last_media_sync"), value: formattedLastMediaSync)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("sync_settings_media_log"))
                            .amgiFont(.bodyEmphasis)
                            .foregroundStyle(SettingsValueStyle.primary)
                        Text(mediaLastLog.isEmpty ? L("common_none") : mediaLastLog)
                            .amgiFont(.caption)
                            .foregroundStyle(SettingsValueStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AmgiSpacing.xs)
                            .padding(.horizontal, AmgiSpacing.sm)
                            .background(
                                Color.amgiSurface,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .padding(.vertical, 4)
                }
                .amgiSettingsListRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_sync"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showServerSetup) {
            SyncServerSetupSheet(isPresented: $showServerSetup)
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet(isPresented: $showLogin) {
                syncMessage = L("common_done")
                showSyncAlert = true
            }
        }
        .alert(L("settings_row_sync"), isPresented: $showSyncAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(syncMessage ?? L("common_none"))
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(SettingsValueStyle.primary)
            Spacer()
            Text(value)
                .amgiFont(.body)
                .foregroundStyle(SettingsValueStyle.highlight)
                .multilineTextAlignment(.trailing)
        }
    }

    private func logout() {
        AppSyncAuthEvents.clearCredentials()
        syncMessage = L("sync_settings_logged_out")
        showSyncAlert = true
    }

    private func syncMediaNow() async {
        guard syncMode != .local else { return }
        guard KeychainHelper.loadHostKey() != nil else {
            showLogin = true
            return
        }

        isSyncingMedia = true
        defer { isSyncingMedia = false }

        do {
            _ = try await syncClient.syncMedia()
            let message = L("sync_settings_media_log_success")
            SyncPreferences.recordMediaSyncLog(message)
            mediaLastLog = message
            mediaLastSyncedAt = Date.now.timeIntervalSince1970
            syncMessage = message
        } catch {
            let message = L("sync_settings_media_log_failed", error.localizedDescription)
            SyncPreferences.recordMediaSyncLog(message)
            mediaLastLog = message
            mediaLastSyncedAt = Date.now.timeIntervalSince1970
            syncMessage = message
        }

        showSyncAlert = true
    }
}

private struct SyncServerSetupSheet: View {
    @Binding var isPresented: Bool
    @State private var serverURL: String = KeychainHelper.loadEndpoint() ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("onboarding_server_url_placeholder"), text: $serverURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text(L("sync_label_server"))
                } footer: {
                    Text(L("onboarding_footer"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }

                Section {
                    Button(L("common_save")) {
                        save()
                    }
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("sync_menu_change_server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) {
                        isPresented = false
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                }
            }
        }
    }

    private func save() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        try? KeychainHelper.saveEndpoint(url)
        UserDefaults.standard.set(SyncPreferences.Mode.custom.rawValue, forKey: SyncPreferences.Keys.modeForCurrentUser())
        AppSyncAuthEvents.clearCredentials()
        isPresented = false
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AmgiSpacing.xl) {
                VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                    Text("Amgi")
                        .amgiFont(.displayHero)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Text(L("about_summary_text"))
                        .amgiFont(.body)
                        .foregroundStyle(Color.amgiTextSecondary)
                }

                aboutSection(title: L("about_section_project")) {
                    Text(L("about_project_text"))
                        .amgiFont(.body)
                        .foregroundStyle(Color.amgiTextPrimary)
                }

                aboutSection(title: L("about_section_architecture")) {
                    Text(L("about_architecture_text"))
                        .amgiFont(.body)
                        .foregroundStyle(Color.amgiTextPrimary)
                }

                aboutSection(title: L("about_section_tech_stack")) {
                    VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
                        aboutBullet("SwiftUI")
                        aboutBullet("Swift 6.2")
                        aboutBullet("Rust FFI")
                        aboutBullet("Protocol Buffers")
                        aboutBullet("SQLite")
                        aboutBullet("XcodeGen")
                    }
                }

                aboutSection(title: L("about_section_acknowledgements")) {
                    VStack(alignment: .leading, spacing: AmgiSpacing.lg) {
                        aboutLinkBlock(
                            title: "ankitects/anki",
                            description: L("about_ack_anki_text"),
                            urlString: "https://github.com/ankitects/anki"
                        )
                        aboutLinkBlock(
                            title: "AnkiDroid",
                            description: L("about_ack_ankidroid_text"),
                            urlString: "https://github.com/ankidroid/Anki-Android"
                        )
                        aboutLinkBlock(
                            title: "Point-Free swift-dependencies",
                            description: L("about_ack_dependencies_text"),
                            urlString: "https://github.com/pointfreeco/swift-dependencies"
                        )
                        aboutLinkBlock(
                            title: "SwiftProtobuf",
                            description: L("about_ack_swiftprotobuf_text"),
                            urlString: "https://github.com/apple/swift-protobuf"
                        )
                        aboutLinkBlock(
                            title: "XcodeGen",
                            description: L("about_ack_xcodegen_text"),
                            urlString: "https://github.com/yonaskolb/XcodeGen"
                        )
                    }
                }

                aboutSection(title: L("about_section_links")) {
                    VStack(alignment: .leading, spacing: AmgiSpacing.md) {
                        aboutLinkRow(title: L("about_link_project_repo"), urlString: "https://github.com/antigluten/amgi")
                        aboutLinkRow(title: L("about_link_anki_repo"), urlString: "https://github.com/ankitects/anki")
                    }
                }

                aboutSection(title: L("about_section_license")) {
                    Text(L("about_license_text"))
                        .amgiFont(.body)
                        .foregroundStyle(Color.amgiTextPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AmgiSpacing.lg)
            .padding(.vertical, AmgiSpacing.xl)
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("about_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(title)
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)
            content()
        }
    }

    private func aboutBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AmgiSpacing.xs) {
            Text("•")
                .amgiFont(.body)
                .foregroundStyle(Color.amgiAccent)
            Text(text)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextPrimary)
        }
    }

    private func aboutLinkBlock(title: String, description: String, urlString: String) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            Text(title)
                .amgiFont(.bodyEmphasis)
                .foregroundStyle(Color.amgiTextPrimary)
            Text(description)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextSecondary)
            aboutLinkRow(title: urlString, urlString: urlString)
        }
    }

    private func aboutLinkRow(title: String, urlString: String) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: AmgiSpacing.xs) {
                        Text(title)
                            .amgiFont(.captionBold)
                        Image(systemName: "arrow.up.right")
                            .font(AmgiFont.caption.font)
                    }
                    .foregroundStyle(Color.amgiLink)
                }
            }
        }
    }
}
