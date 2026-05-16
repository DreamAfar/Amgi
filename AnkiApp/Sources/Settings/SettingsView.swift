import SwiftUI
import AnkiBackend
import AnkiKit
import AnkiClients
import AnkiProto
import AnkiSync
import Dependencies
import SwiftProtobuf

enum SettingsValueStyle {
    static let highlight = Color.amgiAccent
    static let primary = Color.amgiTextPrimary
    static let secondary = Color.amgiTextSecondary
}

struct SettingsOptionCapsuleLabel: View {
    let title: String
    var icon: String? = nil
    var titleColor: Color = SettingsValueStyle.highlight
    var indicatorColor: Color = SettingsValueStyle.secondary
    var backgroundColor: Color = .amgiMenuSurface
    var maxWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: AmgiSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(AmgiFont.micro.font)
                    .foregroundStyle(indicatorColor)
            }
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(AmgiFont.micro.font)
                .foregroundStyle(indicatorColor)
        }
        .amgiCapsuleControl(backgroundColor: backgroundColor)
        .frame(maxWidth: maxWidth, alignment: .trailing)
    }
}

extension View {
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

    var preferredBackendLangs: [String] {
        switch self {
        case .system:
            return Locale.preferredLanguages
        case .chineseSimplified:
            return ["zh-Hans"]
        case .english:
            return ["en"]
        case .japanese:
            return ["ja"]
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
    @State private var isCheckingDatabase = false
    @State private var databaseCheckResult = ""
    @State private var showDatabaseCheckResult = false

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

                NavigationLink {
                    ReaderOptionsView()
                } label: {
                    settingsRowLabel(L("settings_row_reader"), icon: "book.closed")
                }
                .amgiSettingsListRowSurface()
            }

            Section(L("settings_section_display")) {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Label(L("settings_picker_theme"), systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    HStack(alignment: .top, spacing: AmgiSpacing.md) {
                        Label(L("settings_picker_language"), systemImage: "globe")
                            .foregroundStyle(SettingsValueStyle.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                    if isCheckingDatabase {
                        HStack {
                            settingsRowLabel(L("settings_row_check_database"), icon: "checkmark.seal")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                            ProgressView()
                        }
                        .contentShape(Rectangle())
                    } else {
                        HStack {
                            settingsRowLabel(L("settings_row_check_database"), icon: "checkmark.seal")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCheckingDatabase)
                .amgiSettingsListRowSurface()

                NavigationLink {
                    MediaCheckResultView()
                } label: {
                    settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                }
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
        .sheet(isPresented: $showDatabaseCheckResult) {
            NavigationStack {
                SettingsInfoView(
                    title: L("settings_row_check_database"),
                    message: databaseCheckResult,
                    showsResetCurrentUserButton: true
                )
            }
        }
    }

    private func settingsRowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .amgiFont(.body)
            .foregroundStyle(SettingsValueStyle.primary)
    }

    private func checkDatabase() {
        isCheckingDatabase = true
        let capturedBackend = backend
        Task.detached {
            do {
                let response: Anki_Collection_CheckDatabaseResponse = try capturedBackend.invoke(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                )
                let resultText: String
                if response.problems.isEmpty {
                    resultText = L("settings_check_database_no_issues")
                } else {
                    resultText = response.problems.joined(separator: "\n")
                }
                await MainActor.run {
                    isCheckingDatabase = false
                    databaseCheckResult = resultText
                    showDatabaseCheckResult = true
                }
            } catch {
                await MainActor.run {
                    isCheckingDatabase = false
                    maintenanceMessage = L("debug_check_db_error", error.localizedDescription)
                    showMaintenanceAlert = true
                }
            }
        }
    }

}

private struct SettingsInfoView: View {
    let title: String
    let message: String
    let showsResetCurrentUserButton: Bool
    @Dependency(\.ankiBackend) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var showResetComplete = false
    @State private var showResetError = false
    @State private var resetErrorMessage = ""

    var body: some View {
        List {
            Section {
                Text(message)
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.amgiSurfaceElevated)
            }

            if showsResetCurrentUserButton {
                Section {
                    Button(L("debug_reset_button"), role: .destructive) {
                        showResetConfirm = true
                    }
                    .listRowBackground(Color.amgiSurfaceElevated)
                } footer: {
                    Text(L("debug_reset_confirm_msg"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_done")) { dismiss() }
                    .amgiToolbarTextButton(tone: .neutral)
            }
        }
        .confirmationDialog(L("debug_reset_confirm_msg"), isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button(L("debug_reset_confirm_button"), role: .destructive) {
                resetCurrentUserData()
            }
        }
        .alert(L("common_done"), isPresented: $showResetComplete) {
            Button(L("common_ok"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(L("debug_reset_complete"))
        }
        .alert(L("common_error"), isPresented: $showResetError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(resetErrorMessage)
        }
    }

    private func resetCurrentUserData() {
        let currentUser = AppUserStore.loadSelectedUser()
        try? backend.closeCollection()

        do {
            try AppUserStore.deleteUserData(for: currentUser)
            NotificationCenter.default.post(name: AppCollectionEvents.didResetNotification, object: nil)
            showResetComplete = true
        } catch {
            resetErrorMessage = error.localizedDescription
            showResetError = true
        }
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

    @Dependency(\.ankiBackend) var backend

    @AppStorage(ReviewPreferences.Keys.playAudioInSilentMode) private var playAudioInSilentMode = false
    @AppStorage(ReviewPreferences.Keys.showContextMenuButton) private var showContextMenuButton = true
    @AppStorage(ReviewPreferences.Keys.showAudioReplayButton) private var showAudioReplayButton = true
    @AppStorage(ReviewPreferences.Keys.showCorrectnessSymbols) private var showCorrectnessSymbols = false
    @AppStorage(ReviewPreferences.Keys.disperseAnswerButtons) private var disperseAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.showAnswerButtons) private var showAnswerButtons = true
    @AppStorage(ReviewPreferences.Keys.hideHardAndEasyButtons) private var hideHardAndEasyButtons = false
    @AppStorage(ReviewPreferences.Keys.showRemainingDays) private var showRemainingDays = true
    @AppStorage(ReviewPreferences.Keys.showNextReviewTime) private var showNextReviewTime = false
    @AppStorage(ReviewPreferences.Keys.openLinksExternally) private var openLinksExternally = true
    @AppStorage(ReviewPreferences.Keys.lookupPopupEnabled) private var lookupPopupEnabled = true
    @AppStorage(ReviewPreferences.Keys.lookupPopupFrontEnabled) private var lookupPopupFrontEnabled = false
    @AppStorage(ReviewPreferences.Keys.lookupPopupBackEnabled) private var lookupPopupBackEnabled = true
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupEnabled) private var selectionMenuLookupEnabled = false
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEnabled) private var selectionMenuAIEnabled = false
    @AppStorage(ReviewPreferences.Keys.cardContentAlignment) private var cardContentAlignmentRaw = CardAlignment.top.rawValue
    @AppStorage(ReviewPreferences.Keys.glassAnswerButtons) private var glassAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.autoMatchCardBackground) private var autoMatchCardBackground = true
    @AppStorage(ReviewPreferences.Keys.dayStartHour) private var persistedDayStartHour = 4
    @AppStorage(ReviewPreferences.Keys.dailyReminderEnabledForCurrentUser()) private var dailyReminderEnabled = false
    @AppStorage(ReviewPreferences.Keys.dailyReminderHourForCurrentUser()) private var dailyReminderHour = 20
    @AppStorage(ReviewPreferences.Keys.dailyReminderMinuteForCurrentUser()) private var dailyReminderMinute = 0
    @State private var rolloverHour = 4
    @State private var loadBalancerEnabled = false
    @State private var fsrsShortTermWithStepsEnabled = false
    @State private var isLoadingFsrsOptions = true
    @State private var isSyncingFsrsOptions = false
    @State private var suppressFsrsOptionSync = false
    @State private var fsrsOptionsError: String?
    @State private var showFsrsOptionsError = false
    @State private var isSyncingDailyReminder = false

    private var cardAlignment: Binding<CardAlignment> {
        Binding(
            get: { CardAlignment(rawValue: cardContentAlignmentRaw) ?? .top },
            set: { cardContentAlignmentRaw = $0.rawValue }
        )
    }

    private var rolloverHourBinding: Binding<Int> {
        Binding(
            get: { rolloverHour },
            set: { rolloverHour = $0 }
        )
    }

    private var rolloverHourLabel: String {
        String(format: L("settings_review_day_start_hour_value"), rolloverHour)
    }

    private var dailyReminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let components = DateComponents(hour: dailyReminderHour, minute: dailyReminderMinute)
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                dailyReminderHour = components.hour ?? 20
                dailyReminderMinute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        List {
            Section(L("settings_review_section_plan_and_reminders")) {
                if isLoadingFsrsOptions {
                    HStack {
                        Text(L("settings_review_loading"))
                            .foregroundStyle(SettingsValueStyle.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else {
                    HStack(alignment: .top, spacing: AmgiSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("settings_review_day_start"))
                                .foregroundStyle(SettingsValueStyle.primary)
                            Text(L("settings_review_day_start_hint"))
                                .amgiFont(.caption)
                                .foregroundStyle(SettingsValueStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Menu {
                            Picker(L("settings_review_day_start"), selection: rolloverHourBinding) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: L("settings_review_day_start_hour_value"), hour))
                                        .foregroundStyle(SettingsValueStyle.highlight)
                                        .tag(hour)
                                }
                            }
                        } label: {
                            SettingsOptionCapsuleLabel(title: rolloverHourLabel)
                        }
                    }

                    Toggle(L("settings_review_daily_reminder_enabled"), isOn: $dailyReminderEnabled)

                    if dailyReminderEnabled {
                        HStack(alignment: .top, spacing: AmgiSpacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("settings_review_daily_reminder_time"))
                                    .foregroundStyle(SettingsValueStyle.primary)
                                Text(L("settings_review_daily_reminder_hint"))
                                    .amgiFont(.caption)
                                    .foregroundStyle(SettingsValueStyle.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            DatePicker(
                                L("settings_review_daily_reminder_time"),
                                selection: dailyReminderTimeBinding,
                                displayedComponents: [.hourAndMinute]
                            )
                            .labelsHidden()
                        }
                    }

                    Toggle(L("settings_review_load_balancer_enabled"), isOn: $loadBalancerEnabled)
                    Text(L("settings_review_load_balancer_enabled_hint"))
                        .amgiFont(.caption)
                        .foregroundStyle(SettingsValueStyle.secondary)

                    Toggle(
                        L("settings_review_fsrs_short_term_with_steps_enabled"),
                        isOn: $fsrsShortTermWithStepsEnabled
                    )
                    Text(L("settings_review_fsrs_short_term_with_steps_enabled_hint"))
                        .amgiFont(.caption)
                        .foregroundStyle(SettingsValueStyle.secondary)
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_audio")) {
                Toggle(L("settings_review_play_audio_in_silent_mode"), isOn: $playAudioInSilentMode)
                Toggle(L("settings_review_show_audio_replay_button"), isOn: $showAudioReplayButton)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_page_display")) {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("settings_review_card_alignment"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

                Toggle(L("settings_review_show_context_menu_button"), isOn: $showContextMenuButton)
                Toggle(L("settings_review_show_correctness_symbols"), isOn: $showCorrectnessSymbols)
                Toggle(L("settings_review_auto_match_card_background"), isOn: $autoMatchCardBackground)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_answer_buttons")) {
                Toggle(L("settings_review_show_answer_buttons"), isOn: $showAnswerButtons)
                Toggle(L("settings_review_disperse_answer_buttons"), isOn: $disperseAnswerButtons)
                Toggle(L("settings_review_hide_hard_and_easy_buttons"), isOn: $hideHardAndEasyButtons)
                Toggle(L("settings_review_show_remaining_days"), isOn: $showRemainingDays)
                Toggle(L("settings_review_show_next_review_time"), isOn: $showNextReviewTime)

                if #available(iOS 26.0, *) {
                    Toggle(L("settings_review_glass_answer_buttons"), isOn: $glassAnswerButtons)
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_lookup_and_links")) {
                Toggle(L("settings_review_open_links_externally"), isOn: $openLinksExternally)
                Toggle(L("settings_review_lookup_popup_enabled"), isOn: $lookupPopupEnabled)
                if lookupPopupEnabled {
                    Toggle(L("settings_review_lookup_popup_front_enabled"), isOn: $lookupPopupFrontEnabled)
                    Toggle(L("settings_review_lookup_popup_back_enabled"), isOn: $lookupPopupBackEnabled)
                }
                NavigationLink {
                    ReviewSelectionMenuSettingsView()
                } label: {
                    reviewSettingsRowLabel(L("settings_review_text_selection_menu"), icon: "text.cursor")
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_section_input_mappings")) {
                NavigationLink {
                    ReviewGestureOptionsView()
                } label: {
                    reviewSettingsRowLabel(L("settings_review_section_gestures"), icon: "hand.tap")
                }

                NavigationLink {
                    ReviewControllerOptionsView()
                } label: {
                    reviewSettingsRowLabel(L("settings_review_section_controller"), icon: "gamecontroller")
                }

                NavigationLink {
                    ReviewKeyboardOptionsView()
                } label: {
                    reviewSettingsRowLabel(L("settings_review_section_keyboard"), icon: "keyboard")
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_review"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviewSchedulingOptions()
        }
        .onChange(of: loadBalancerEnabled) { _, _ in
            persistFsrsReviewingOptionsIfNeeded()
        }
        .onChange(of: fsrsShortTermWithStepsEnabled) { _, _ in
            persistFsrsReviewingOptionsIfNeeded()
        }
        .onChange(of: rolloverHour) { oldValue, newValue in
            guard oldValue != newValue, newValue != persistedDayStartHour else { return }
            persistSchedulingOptionsIfNeeded()
        }
        .onChange(of: dailyReminderEnabled) { oldValue, newValue in
            guard oldValue != newValue else { return }
            syncDailyReminderSettings(enabled: newValue)
        }
        .onChange(of: dailyReminderHour) { oldValue, newValue in
            guard oldValue != newValue, dailyReminderEnabled else { return }
            syncDailyReminderSettings(enabled: true)
        }
        .onChange(of: dailyReminderMinute) { oldValue, newValue in
            guard oldValue != newValue, dailyReminderEnabled else { return }
            syncDailyReminderSettings(enabled: true)
        }
        .alert(L("deck_action_error_title"), isPresented: $showFsrsOptionsError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(fsrsOptionsError ?? L("common_unknown_error"))
        }
    }

    private func reviewSettingsRowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .amgiFont(.body)
            .foregroundStyle(SettingsValueStyle.primary)
    }

    @MainActor
    private func loadReviewSchedulingOptions() async {
        isLoadingFsrsOptions = true
        defer { isLoadingFsrsOptions = false }

        do {
            let preferences = try backend.getPreferences()
            suppressFsrsOptionSync = true
            rolloverHour = Int(preferences.scheduling.rollover)
            persistedDayStartHour = rolloverHour
            loadBalancerEnabled = preferences.reviewing.loadBalancerEnabled
            fsrsShortTermWithStepsEnabled = preferences.reviewing.fsrsShortTermWithStepsEnabled
            suppressFsrsOptionSync = false
        } catch {
            fsrsOptionsError = L("settings_review_schedule_load_failed", error.localizedDescription)
            showFsrsOptionsError = true
        }
    }

    private func persistFsrsReviewingOptionsIfNeeded() {
        guard !isLoadingFsrsOptions, !suppressFsrsOptionSync, !isSyncingFsrsOptions else { return }

        let loadBalancer = loadBalancerEnabled
        let shortTermWithSteps = fsrsShortTermWithStepsEnabled
        let capturedBackend = backend
        isSyncingFsrsOptions = true

        Task {
            do {
                var preferences = try capturedBackend.getPreferences()
                preferences.reviewing.loadBalancerEnabled = loadBalancer
                preferences.reviewing.fsrsShortTermWithStepsEnabled = shortTermWithSteps
                try capturedBackend.setPreferences(preferences)
            } catch {
                await MainActor.run {
                    fsrsOptionsError = L("settings_review_fsrs_save_failed", error.localizedDescription)
                    showFsrsOptionsError = true
                }
                await loadReviewSchedulingOptions()
            }
            await MainActor.run {
                isSyncingFsrsOptions = false
            }
        }
    }

    private func persistSchedulingOptionsIfNeeded() {
        guard !isLoadingFsrsOptions, !suppressFsrsOptionSync, !isSyncingFsrsOptions else { return }

        let selectedRolloverHour = UInt32(rolloverHour)
        let capturedBackend = backend
        isSyncingFsrsOptions = true

        Task {
            do {
                var preferences = try capturedBackend.getPreferences()
                preferences.scheduling.rollover = selectedRolloverHour
                try capturedBackend.setPreferences(preferences)
                await MainActor.run {
                    persistedDayStartHour = Int(selectedRolloverHour)
                }
            } catch {
                await MainActor.run {
                    fsrsOptionsError = L("settings_review_schedule_save_failed", error.localizedDescription)
                    showFsrsOptionsError = true
                }
                await loadReviewSchedulingOptions()
            }
            await MainActor.run {
                isSyncingFsrsOptions = false
            }
        }
    }

    private func syncDailyReminderSettings(enabled: Bool) {
        guard !isSyncingDailyReminder else { return }
        isSyncingDailyReminder = true

        Task {
            defer {
                Task { @MainActor in
                    isSyncingDailyReminder = false
                }
            }

            if enabled {
                do {
                    let granted = try await ReviewDailyReminderScheduler.requestAuthorizationIfNeeded()
                    guard granted else {
                        await MainActor.run {
                            dailyReminderEnabled = false
                            fsrsOptionsError = L("settings_review_daily_reminder_permission_denied")
                            showFsrsOptionsError = true
                        }
                        ReviewDailyReminderScheduler.disable()
                        return
                    }
                } catch {
                    await MainActor.run {
                        dailyReminderEnabled = false
                        fsrsOptionsError = L("settings_review_daily_reminder_save_failed", error.localizedDescription)
                        showFsrsOptionsError = true
                    }
                    ReviewDailyReminderScheduler.disable()
                    return
                }

                await ReviewDailyReminderScheduler.refreshIfNeeded(using: backend)
            } else {
                ReviewDailyReminderScheduler.disable()
            }
        }
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
                    HStack(alignment: .top, spacing: AmgiSpacing.md) {
                        Text(L("settings_display_heatmap_scope"))
                            .foregroundStyle(SettingsValueStyle.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        HStack(alignment: .top, spacing: AmgiSpacing.md) {
                            Label(L("settings_display_heatmap_selected_deck"), systemImage: "rectangle.stack")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

                    HStack(alignment: .top, spacing: AmgiSpacing.md) {
                        Label(L("settings_heatmap_initial_range"), systemImage: "calendar")
                            .foregroundStyle(SettingsValueStyle.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ReviewGestureOptionsView: View {
    @AppStorage(ReviewPreferences.Keys.frontTapGestureAction) private var frontTapGestureActionRaw = ReviewPreferences.GestureAction.showAnswer.rawValue
    @AppStorage(ReviewPreferences.Keys.frontSwipeLeftGestureAction) private var frontSwipeLeftGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.frontSwipeRightGestureAction) private var frontSwipeRightGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backTapGestureAction) private var backTapGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backSwipeLeftGestureAction) private var backSwipeLeftGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backSwipeRightGestureAction) private var backSwipeRightGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue

    var body: some View {
        List {
            Section(L("settings_review_gesture_front")) {
                ReviewInputActionRow(title: L("settings_review_tap_action"), selection: binding($frontTapGestureActionRaw))
                ReviewInputActionRow(title: L("settings_review_swipe_left_action"), selection: binding($frontSwipeLeftGestureActionRaw))
                ReviewInputActionRow(title: L("settings_review_swipe_right_action"), selection: binding($frontSwipeRightGestureActionRaw))
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_gesture_back")) {
                ReviewInputActionRow(title: L("settings_review_tap_action"), selection: binding($backTapGestureActionRaw))
                ReviewInputActionRow(title: L("settings_review_swipe_left_action"), selection: binding($backSwipeLeftGestureActionRaw))
                ReviewInputActionRow(title: L("settings_review_swipe_right_action"), selection: binding($backSwipeRightGestureActionRaw))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_section_gestures"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ rawValue: Binding<String>) -> Binding<ReviewPreferences.GestureAction> {
        Binding(
            get: { ReviewPreferences.GestureAction(rawValue: rawValue.wrappedValue) ?? .none },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }
}

private struct ReviewControllerOptionsView: View {
    var body: some View {
        List {
            Section {
                ForEach(ReviewPreferences.ControllerButton.allCases) { button in
                    ReviewInputActionRow(
                        title: button.title,
                        selection: actionBinding(button)
                    )
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_section_controller"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionBinding(_ button: ReviewPreferences.ControllerButton) -> Binding<ReviewPreferences.GestureAction> {
        let key = ReviewPreferences.Keys.controllerButtonAction(button)
        return Binding(
            get: {
                let raw = UserDefaults.standard.string(forKey: key) ?? button.defaultAction.rawValue
                return ReviewPreferences.GestureAction(rawValue: raw) ?? .none
            },
            set: { UserDefaults.standard.set($0.rawValue, forKey: key) }
        )
    }
}

private struct ReviewKeyboardOptionsView: View {
    var body: some View {
        List {
            Section {
                ForEach(ReviewPreferences.KeyboardShortcut.allCases) { shortcut in
                    ReviewInputActionRow(
                        title: shortcut.title,
                        selection: actionBinding(shortcut)
                    )
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_section_keyboard"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionBinding(_ shortcut: ReviewPreferences.KeyboardShortcut) -> Binding<ReviewPreferences.GestureAction> {
        let key = ReviewPreferences.Keys.keyboardShortcutAction(shortcut)
        return Binding(
            get: {
                let raw = UserDefaults.standard.string(forKey: key) ?? shortcut.defaultAction.rawValue
                return ReviewPreferences.GestureAction(rawValue: raw) ?? .none
            },
            set: { UserDefaults.standard.set($0.rawValue, forKey: key) }
        )
    }
}

private struct ReviewInputActionRow: View {
    let title: String
    @Binding var selection: ReviewPreferences.GestureAction

    var body: some View {
        HStack(alignment: .top, spacing: AmgiSpacing.md) {
            Text(title)
                .foregroundStyle(SettingsValueStyle.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(ReviewPreferences.GestureAction.allCases) { action in
                        Text(action.title)
                            .foregroundStyle(SettingsValueStyle.highlight)
                            .tag(action)
                    }
                }
            } label: {
                SettingsOptionCapsuleLabel(title: selection.title)
            }
        }
    }
}

private extension ReviewPreferences.GestureAction {
    var title: String {
        switch self {
        case .none: return L("settings_review_gesture_action_none")
        case .showAnswer: return L("review_show_answer")
        case .again: return L("review_rating_again")
        case .hard: return L("review_rating_hard")
        case .good: return L("review_rating_good")
        case .easy: return L("review_rating_easy")
        case .replayAudio: return L("settings_review_gesture_action_replay_audio")
        case .goBack: return L("settings_review_gesture_action_go_back")
        case .showContextMenu: return L("settings_review_gesture_action_show_context_menu")
        case .editNote: return L("review_edit_button")
        case .editTemplate: return L("card_template_editor_title")
        case .undo: return L("card_action_undo")
        case .showDeckStats: return L("stats_nav_title")
        case .showCardInfo: return L("card_info_title")
        case .moveToDeck: return L("browse_batch_move_deck")
        case .changeNotetype: return L("browse_batch_change_notetype")
        case .setDueDate: return L("card_action_set_due_date")
        case .suspendCard: return L("card_action_suspend")
        case .buryCard: return L("card_action_bury")
        case .resetCard: return L("card_action_reset_to_new")
        case .flagNone: return L("review_flag_clear")
        case .flagRed: return L("review_flag_red")
        case .flagOrange: return L("review_flag_orange")
        case .flagGreen: return L("review_flag_green")
        case .flagBlue: return L("review_flag_blue")
        case .flagPink: return L("review_flag_pink")
        case .flagCyan: return L("review_flag_cyan")
        case .flagPurple: return L("review_flag_purple")
        case .userAction1: return String(format: L("review_user_action_number"), 1)
        case .userAction2: return String(format: L("review_user_action_number"), 2)
        case .userAction3: return String(format: L("review_user_action_number"), 3)
        case .userAction4: return String(format: L("review_user_action_number"), 4)
        case .userAction5: return String(format: L("review_user_action_number"), 5)
        case .userAction6: return String(format: L("review_user_action_number"), 6)
        case .userAction7: return String(format: L("review_user_action_number"), 7)
        case .userAction8: return String(format: L("review_user_action_number"), 8)
        case .userAction9: return String(format: L("review_user_action_number"), 9)
        }
    }
}

private extension ReviewPreferences.ControllerButton {
    var title: String {
        switch self {
        case .buttonA: return "A"
        case .buttonB: return "B"
        case .buttonX: return "X"
        case .buttonY: return "Y"
        case .dpadUp: return L("settings_review_controller_dpad_up")
        case .dpadDown: return L("settings_review_controller_dpad_down")
        case .dpadLeft: return L("settings_review_controller_dpad_left")
        case .dpadRight: return L("settings_review_controller_dpad_right")
        case .leftShoulder: return L("settings_review_controller_left_shoulder")
        case .rightShoulder: return L("settings_review_controller_right_shoulder")
        case .leftTrigger: return L("settings_review_controller_left_trigger")
        case .rightTrigger: return L("settings_review_controller_right_trigger")
        case .leftThumbstick: return L("settings_review_controller_left_thumbstick")
        case .rightThumbstick: return L("settings_review_controller_right_thumbstick")
        case .options: return L("settings_review_controller_options")
        case .menu: return L("settings_review_controller_menu")
        }
    }

    var defaultAction: ReviewPreferences.GestureAction {
        switch self {
        case .buttonA: return .good
        case .buttonB: return .again
        case .buttonX: return .easy
        case .buttonY: return .hard
        case .rightShoulder: return .replayAudio
        default: return .none
        }
    }
}

private extension ReviewPreferences.KeyboardShortcut {
    var title: String {
        switch self {
        case .space: return L("settings_review_keyboard_space")
        case .enter: return L("settings_review_keyboard_enter")
        case .number1: return "1"
        case .number2: return "2"
        case .number3: return "3"
        case .number4: return "4"
        case .replay: return "R"
        case .command1: return "⌘1"
        case .command2: return "⌘2"
        case .command3: return "⌘3"
        case .command4: return "⌘4"
        case .command5: return "⌘5"
        case .command6: return "⌘6"
        case .command7: return "⌘7"
        case .command8: return "⌘8"
        case .command9: return "⌘9"
        }
    }

    var defaultAction: ReviewPreferences.GestureAction {
        switch self {
        case .space, .enter: return .showAnswer
        case .number1: return .again
        case .number2: return .hard
        case .number3: return .good
        case .number4: return .easy
        case .replay: return .replayAudio
        case .command1: return .userAction1
        case .command2: return .userAction2
        case .command3: return .userAction3
        case .command4: return .userAction4
        case .command5: return .userAction5
        case .command6: return .userAction6
        case .command7: return .userAction7
        case .command8: return .userAction8
        case .command9: return .userAction9
        }
    }
}

private struct ReaderOptionsView: View {
    var body: some View {
        ReaderSettingsHomeView()
    }
}

private struct SyncSettingsView: View {
    @AppStorage(SyncPreferences.Keys.modeForCurrentUser()) private var syncModeRaw = SyncPreferences.Mode.local.rawValue
    @AppStorage(SyncPreferences.Keys.syncMediaForCurrentUser()) private var syncMediaEnabled = true
    @AppStorage(SyncPreferences.Keys.ioTimeoutSecsForCurrentUser()) private var ioTimeoutSecs = SyncPreferences.Timeout.defaultValue

    @State private var showServerSetup = false
    @State private var showLogin = false
    @State private var showSyncSheet = false
    @State private var syncMessage: String?
    @State private var showSyncAlert = false
    @State private var showLogoutConfirm = false

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

    var body: some View {
        List {
            Section(L("sync_settings_section_server")) {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("sync_settings_server_type"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

                if syncMode == .official {
                    ankiWebSupportNoticeRow()
                } else {
                    infoRow(title: L("sync_settings_server_type"), value: serverTypeLabel)
                }
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
                            showLogoutConfirm = true
                        }
                    }
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("sync_settings_section_options")) {
                Toggle(L("sync_settings_sync_media"), isOn: $syncMediaEnabled)

                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("sync_settings_timeout"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                Section {
                    Button {
                        showSyncSheet = true
                    } label: {
                        HStack {
                            Label(L("sync_settings_sync_now"), systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(SettingsValueStyle.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("sync_settings_sync_now_hint"))
                            .amgiFont(.caption)
                            .foregroundStyle(SettingsValueStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
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
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(isPresented: $showSyncSheet)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
        }
        .alert(L("settings_row_sync"), isPresented: $showSyncAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(syncMessage ?? L("common_none"))
        }
        .alert(L("sync_logout_confirm_title"), isPresented: $showLogoutConfirm) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("sync_logout_confirm_button"), role: .destructive) {
                logout()
            }
        } message: {
            Text(L("sync_logout_confirm_message"))
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

    private func ankiWebSupportNoticeRow() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("ankiweb_support_notice"))
                .amgiFont(.caption)
                .foregroundStyle(SettingsValueStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: "https://apps.apple.com/us/app/ankimobile-flashcards/id373493387") {
                HStack(spacing: 4) {
                    Text(L("common_view"))
                        .amgiFont(.caption)
                        .foregroundStyle(SettingsValueStyle.secondary)
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("AnkiMobile")
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

    private func logout() {
        AppSyncAuthEvents.clearCredentials()
        syncMessage = L("sync_settings_logged_out")
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
                            title: "AnkiWeb Sync Service",
                            description: L("about_ack_ankiweb_text"),
                            urlString: "https://apps.apple.com/us/app/ankimobile-flashcards/id373493387",
                            linkTitle: "AnkiMobile"
                        )
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
                            title: "Hoshi-Reader",
                            description: L("about_ack_hoshi_reader_text"),
                            urlString: "https://github.com/Manhhao/Hoshi-Reader"
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
                        aboutLinkRow(title: L("about_link_hoshi_reader_repo"), urlString: "https://github.com/Manhhao/Hoshi-Reader")
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

    private func aboutLinkBlock(
        title: String,
        description: String,
        urlString: String,
        linkTitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            Text(title)
                .amgiFont(.bodyEmphasis)
                .foregroundStyle(Color.amgiTextPrimary)
            Text(description)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextSecondary)
            aboutLinkRow(title: linkTitle ?? urlString, urlString: urlString)
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
