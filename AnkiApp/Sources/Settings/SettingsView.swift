import SwiftUI
import AnkiBackend
import Dependencies

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

    @AppStorage("app_color_scheme") private var followSystem = true
    @AppStorage("app_force_dark") private var forceDarkMode = false
    @AppStorage("app_language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var maintenanceMessage: String?
    @State private var showMaintenanceAlert = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

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
                    SettingsInfoView(
                        title: L("settings_row_review"),
                        message: L("settings_info_review")
                    )
                } label: {
                    settingsRowLabel(L("settings_row_review"), icon: "rectangle.on.rectangle")
                }
            }

            Section(L("settings_section_display")) {
                Toggle(L("settings_toggle_follow_system"), isOn: $followSystem)
                Toggle(L("settings_toggle_dark_mode"), isOn: $forceDarkMode)
                    .disabled(followSystem)

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
                Button {
                    exportBackup()
                } label: {
                    settingsRowLabel(L("settings_row_backup"), icon: "externaldrive")
                }

                Button {
                    checkDatabase()
                } label: {
                    settingsRowLabel(L("settings_row_check_database"), icon: "checkmark.seal")
                }

                Button {
                    maintenanceMessage = L("settings_check_media_not_wired")
                    showMaintenanceAlert = true
                } label: {
                    settingsRowLabel(L("settings_row_check_media"), icon: "photo.on.rectangle")
                }

                Button {
                    maintenanceMessage = L("settings_empty_cards_not_wired")
                    showMaintenanceAlert = true
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
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func settingsRowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
    }

    private func exportBackup() {
        do {
            let url = try ImportHelper.exportCollection()
            exportedFileURL = url
            showShareSheet = true
            maintenanceMessage = L("debug_export_ready", url.lastPathComponent)
            showMaintenanceAlert = true
        } catch {
            maintenanceMessage = L("debug_export_error", error.localizedDescription)
            showMaintenanceAlert = true
        }
    }

    private func checkDatabase() {
        do {
            let responseBytes = try backend.call(
                service: AnkiBackend.Service.checkDatabase,
                method: AnkiBackend.CheckDatabaseMethod.checkDatabase
            )
            maintenanceMessage = L("debug_check_db_ok", responseBytes.count)
            showMaintenanceAlert = true
        } catch {
            maintenanceMessage = L("debug_check_db_error", "\(error)")
            showMaintenanceAlert = true
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
