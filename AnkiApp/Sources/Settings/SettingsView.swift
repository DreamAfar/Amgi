import SwiftUI
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

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

                NavigationLink {
                    SettingsInfoView(
                        title: L("settings_row_editing"),
                        message: L("settings_info_editing")
                    )
                } label: {
                    settingsRowLabel(L("settings_row_editing"), icon: "pencil.and.scribble")
                }

                NavigationLink {
                    ReviewOptionsView()
                } label: {
                    settingsRowLabel(L("settings_row_review"), icon: "rectangle.on.rectangle")
                }
            }

            Section(L("settings_section_display")) {
                Picker(L("settings_picker_theme"), selection: selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                Picker(L("settings_picker_language"), selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                if selectedLanguage.wrappedValue != .system {
                    Label(L("settings_language_restart_hint"), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("settings_section_maintenance")) {
                NavigationLink {
                    BackupView(username: AppUserStore.loadSelectedUser())
                } label: {
                    settingsRowLabel(L("settings_row_backup"), icon: "externaldrive")
                }

                Button {
                    checkDatabase()
                } label: {
                    settingsRowLabel(L("settings_row_check_database"), icon: "checkmark.seal")
                }

                Button {
                    checkMedia()
                } label: {
                    if isCheckingMedia {
                        HStack {
                            settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                    }
                }
                .disabled(isCheckingMedia)

                NavigationLink {
                    EmptyCardsView()
                } label: {
                    settingsRowLabel(L("settings_row_empty_cards"), icon: "rectangle.stack.badge.minus")
                }

                NavigationLink {
                    DebugView()
                } label: {
                    settingsRowLabel(L("debug_nav_title"), icon: "ladybug")
                }
            }

            Section(L("settings_section_other")) {
                NavigationLink {
                    AboutView()
                } label: {
                    settingsRowLabel(L("settings_row_about"), icon: "info.circle")
                }
            }
        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
    }
}

private struct ReviewOptionsView: View {
    @AppStorage(ReviewPreferences.Keys.autoplayAudio) private var autoplayAudio = true
    @AppStorage(ReviewPreferences.Keys.playAudioInSilentMode) private var playAudioInSilentMode = false
    @AppStorage(ReviewPreferences.Keys.showContextMenuButton) private var showContextMenuButton = true
    @AppStorage(ReviewPreferences.Keys.showAudioReplayButton) private var showAudioReplayButton = true
    @AppStorage(ReviewPreferences.Keys.showCorrectnessSymbols) private var showCorrectnessSymbols = false
    @AppStorage(ReviewPreferences.Keys.disperseAnswerButtons) private var disperseAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.showAnswerButtons) private var showAnswerButtons = true
    @AppStorage(ReviewPreferences.Keys.showRemainingDays) private var showRemainingDays = true
    @AppStorage(ReviewPreferences.Keys.showNextReviewTime) private var showNextReviewTime = false

    var body: some View {
        List {
            Section(L("settings_review_section_audio")) {
                Toggle(L("settings_review_autoplay_audio"), isOn: $autoplayAudio)
                Toggle(L("settings_review_play_audio_in_silent_mode"), isOn: $playAudioInSilentMode)
            }

            Section(L("settings_review_section_ui")) {
                Toggle(L("settings_review_show_context_menu_button"), isOn: $showContextMenuButton)
                Toggle(L("settings_review_show_audio_replay_button"), isOn: $showAudioReplayButton)
                Toggle(L("settings_review_show_correctness_symbols"), isOn: $showCorrectnessSymbols)
                Toggle(L("settings_review_disperse_answer_buttons"), isOn: $disperseAnswerButtons)
                Toggle(L("settings_review_show_answer_buttons"), isOn: $showAnswerButtons)
                Toggle(L("settings_review_show_remaining_days"), isOn: $showRemainingDays)
                Toggle(L("settings_review_show_next_review_time"), isOn: $showNextReviewTime)
            }
        }
        .navigationTitle(L("settings_row_review"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section(L("about_section_amgi")) {
                Text(L("about_summary_text"))
            }

            Section(L("about_section_architecture")) {
                Text(L("about_architecture_text"))
            }

            Section(L("about_section_tech_stack")) {
                Text(L("about_tech_text"))
            }

            Section(L("about_section_open_source")) {
                Text(L("about_open_source_text"))
            }

            Section(L("about_section_license")) {
                Text(L("about_license_text"))
            }
        }
        .navigationTitle(L("about_nav_title"))
    }
}
