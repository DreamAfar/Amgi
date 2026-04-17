import SwiftUI
import AnkiKit
import AnkiClients
import AnkiSync
import Dependencies

struct SyncSheet: View {
    @Binding var isPresented: Bool
    @Dependency(\.syncClient) var syncClient
    @ObservedObject private var syncCoordinator = AppSyncCoordinator.shared

    @AppStorage(SyncPreferences.Keys.modeForCurrentUser()) private var syncModeRaw = SyncPreferences.Mode.local.rawValue
    @AppStorage(SyncPreferences.Keys.syncMediaForCurrentUser()) private var syncMediaEnabled = true

    @State private var showLogin = false
    @State private var showServerSetup = false

    private var syncMode: SyncPreferences.Mode {
        SyncPreferences.resolvedMode(syncModeRaw)
    }

    private var displayedServer: String {
        switch syncMode {
        case .official:
            return SyncPreferences.officialServerLabel
        case .custom:
            return KeychainHelper.loadEndpoint() ?? L("common_none")
        case .local:
            return L("sync_local_mode_label")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if syncMode != .local {
                    serverConfigSection
                        .padding(.top)
                }

                Spacer()
                switch syncCoordinator.state {
                case .idle:
                    ProgressView(L("sync_preparing"))
                case .syncing(let message):
                    syncingView(message: message)
                case .syncingMedia(let total, let downloaded):
                    mediaProgressView(total: total, downloaded: downloaded)
                case .success(let summary):
                    successView(summary)
                case .error(let message):
                    errorView(message)
                case .needsFullSync:
                    fullSyncChoiceView
                case .noServer:
                    noServerView
                }
                Spacer()
            }
            .padding()
            .background(Color.amgiBackground)
            .navigationTitle(L("sync_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(syncCoordinator.isRunning ? L("btn_cancel") : L("sync_btn_done")) {
                        if syncCoordinator.isRunning {
                            syncCoordinator.cancel()
                        }
                        isPresented = false
                    }
                    .amgiToolbarTextButton(tone: syncCoordinator.isRunning ? .danger : .neutral)
                }
                if syncCoordinator.isRunning {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("sync_btn_background")) {
                            isPresented = false
                        }
                        .amgiToolbarTextButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet(isPresented: $showLogin) {
                Task { await startSync() }
            }
        }
        .sheet(isPresented: $showServerSetup) {
            ServerSetupSheet(isPresented: $showServerSetup) {
                Task { await startSync() }
            }
        }
        .onReceive(syncCoordinator.$requiresLogin) { needsLogin in
            guard needsLogin else { return }
            syncCoordinator.consumeLoginRequest()
            showLogin = true
        }
        .task { await startSync() }
    }

    // MARK: - Syncing View

    @ViewBuilder
    private func syncingView(message: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text(L("sync_syncing"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                Text(message)
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextTertiary)
                        .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(syncCoordinator.logEntries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.date, style: .time)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.amgiTextTertiary)
                                            .fixedSize()
                                        Text(entry.message)
                                            .amgiFont(.caption)
                                            .foregroundStyle(Color.amgiTextSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 8)
                                    .id(entry.id)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(maxHeight: 180)
                        .background(
                            Color.amgiSurface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .onChange(of: syncCoordinator.logEntries.count) { _, _ in
                            if let last = syncCoordinator.logEntries.last {
                                withAnimation(.linear(duration: 0.15)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaProgressView(total: Int, downloaded: Int) -> some View {
        VStack(spacing: 16) {
            Text(L("sync_syncing"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("sync_syncing_media"))
                            .amgiFont(.bodyEmphasis)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Text(L("sync_media_size_info", downloaded, total))
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                    Spacer()
                }

                if total > 0 {
                    ProgressView(value: Double(downloaded), total: Double(total))
                        .tint(Color.amgiAccent)

                    HStack {
                        Text("\(downloaded) / \(total)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.amgiTextSecondary)
                        Spacer()
                        let percentage = total > 0 ? Int(Double(downloaded) * 100 / Double(total)) : 0
                        Text("\(percentage)%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.amgiAccent)
                    }
                }
            }
            .padding()
            .background(
                Color.amgiSurfaceElevated,
                in: RoundedRectangle(cornerRadius: 12)
            )

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextTertiary)
                        .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(syncCoordinator.logEntries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.date, style: .time)
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundStyle(Color.amgiTextTertiary)
                                            .fixedSize()
                                        Text(entry.message)
                                            .amgiFont(.caption)
                                            .foregroundStyle(Color.amgiTextSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 8)
                                    .id(entry.id)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(maxHeight: 120)
                        .background(
                            Color.amgiSurface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .onChange(of: syncCoordinator.logEntries.count) { _, _ in
                            if let last = syncCoordinator.logEntries.last {
                                withAnimation(.linear(duration: 0.15)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Server Config Header

    @ViewBuilder
    private var serverConfigSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("sync_label_server"))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                Text(displayedServer)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let username = KeychainHelper.loadUsername() {
                    Text(username)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(Color.amgiTextTertiary)
                }
            }
            Spacer()
            if syncMode == .custom || KeychainHelper.loadHostKey() != nil {
                Menu {
                    if syncMode == .custom {
                        Button(L("sync_menu_change_server")) {
                            showServerSetup = true
                        }
                    }
                    if KeychainHelper.loadHostKey() != nil {
                        Button(L("sync_menu_logout"), role: .destructive) {
                            logout()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Sync Logic

    private func startSync() async {
        guard syncMode != .local else {
            syncCoordinator.reset()
            syncCoordinator.setState(.noServer)
            return
        }

        guard syncMode != .custom || KeychainHelper.loadEndpoint() != nil else {
            syncCoordinator.reset()
            syncCoordinator.setState(.noServer)
            return
        }

        guard KeychainHelper.loadHostKey() != nil else {
            syncCoordinator.reset()
            showLogin = true
            return
        }

        syncCoordinator.startSync(syncClient: syncClient, syncMediaEnabled: syncMediaEnabled)
    }

    private func logout() {
        AppSyncAuthEvents.clearCredentials()
        syncCoordinator.reset()
        isPresented = false
    }

    // MARK: - No Server (Setup) View

    @ViewBuilder
    private var noServerView: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.and.arrow.up.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(Color.amgiAccent)

            Text(L("sync_setup_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(L("sync_setup_subtitle"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                // AnkiWeb option
                Button {
                    UserDefaults.standard.set(
                        SyncPreferences.Mode.official.rawValue,
                        forKey: SyncPreferences.Keys.modeForCurrentUser()
                    )
                    showLogin = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AnkiWeb")
                                .amgiFont(.bodyEmphasis)
                                .foregroundStyle(Color.amgiTextPrimary)
                            Text(L("sync_setup_ankiweb_desc"))
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AmgiFont.caption.font)
                            .foregroundStyle(Color.amgiTextTertiary)
                    }
                    .padding()
                    .background(
                        Color.amgiSurfaceElevated,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)

                // Self-hosted option
                Button {
                    showServerSetup = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("sync_settings_server_type_custom"))
                                .amgiFont(.bodyEmphasis)
                                .foregroundStyle(Color.amgiTextPrimary)
                            Text(L("sync_setup_self_hosted_desc"))
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AmgiFont.caption.font)
                            .foregroundStyle(Color.amgiTextTertiary)
                    }
                    .padding()
                    .background(
                        Color.amgiSurfaceElevated,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
            }

            Button(L("sync_setup_offline")) {
                isPresented = false
            }
            .amgiFont(.caption)
            .foregroundStyle(Color.amgiTextSecondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Success View

    @ViewBuilder
    private func successView(_ summary: SyncSummary) -> some View {
        VStack(spacing: 12) {
            Label(L("sync_complete_title"), systemImage: "checkmark.circle.fill")
                .amgiStatusBadge(.positive, horizontalPadding: 12, verticalPadding: 8)
            VStack(alignment: .leading, spacing: 4) {
                if summary.cardsPulled > 0 { Text(L("sync_cards_received", summary.cardsPulled)) }
                if summary.cardsPushed > 0 { Text(L("sync_cards_sent", summary.cardsPushed)) }
                if summary.notesPulled > 0 { Text(L("sync_notes_received", summary.notesPulled)) }
                if summary.notesPushed > 0 { Text(L("sync_notes_sent", summary.notesPushed)) }
                if summary.cardsPulled == 0 && summary.cardsPushed == 0 {
                    Text(L("sync_up_to_date"))
                }
            }
            .amgiFont(.caption)
            .foregroundStyle(Color.amgiTextSecondary)

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextTertiary)
                        .padding(.horizontal, 4)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(syncCoordinator.logEntries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.date, style: .time)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Color.amgiTextTertiary)
                                        .fixedSize()
                                    Text(entry.message)
                                        .amgiFont(.caption)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 120)
                    .background(
                        Color.amgiSurface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .padding(.top, 4)
            }
        }
        .amgiStatusPanel(.positive, elevated: true)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Label(L("sync_failed_title"), systemImage: "exclamationmark.triangle.fill")
                .amgiStatusBadge(.warning, horizontalPadding: 12, verticalPadding: 8)
            Text(message)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)
            Button(L("btn_retry")) {
                Task { await startSync() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.amgiAccent)
        }
        .amgiStatusPanel(.warning, elevated: true)
    }

    // MARK: - Full Sync Choice View

    private var fullSyncChoiceView: some View {
        VStack(spacing: 16) {
            Label(L("sync_full_required_title"), systemImage: "arrow.triangle.2.circlepath")
                .amgiStatusBadge(.warning, horizontalPadding: 12, verticalPadding: 8)
            Text(L("sync_full_required_desc"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    Task { await fullSync(.download) }
                } label: {
                    Label(L("sync_btn_download"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.amgiAccent)

                Button {
                    Task { await fullSync(.upload) }
                } label: {
                    Label(L("sync_btn_upload"), systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.amgiAccent)
            }
        }
        .amgiStatusPanel(.warning, elevated: true)
    }

    private func fullSync(_ direction: SyncDirection) async {
        syncCoordinator.startFullSync(direction, syncClient: syncClient)
    }
}

// MARK: - Server Setup Sheet

private struct ServerSetupSheet: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

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
                    Button(L("btn_save")) {
                        save()
                    }
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("sync_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("btn_cancel")) { isPresented = false }
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
        UserDefaults.standard.set(
            SyncPreferences.Mode.custom.rawValue,
            forKey: SyncPreferences.Keys.modeForCurrentUser()
        )
        AppSyncAuthEvents.clearCredentials()
        isPresented = false
        onComplete()
    }
}
