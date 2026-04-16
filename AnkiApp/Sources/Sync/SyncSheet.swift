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
                }
                if syncCoordinator.isRunning {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("sync_btn_background")) {
                            isPresented = false
                        }
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
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(syncCoordinator.logEntries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.date, style: .time)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                            .fixedSize()
                                        Text(entry.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            Color(.systemGroupedBackground),
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
                .font(.title3.weight(.semibold))

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("sync_syncing_media"))
                            .font(.headline.weight(.semibold))
                        Text(L("sync_media_size_info", downloaded, total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if total > 0 {
                    ProgressView(value: Double(downloaded), total: Double(total))
                        .tint(.blue)

                    HStack {
                        Text("\(downloaded) / \(total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        let percentage = total > 0 ? Int(Double(downloaded) * 100 / Double(total)) : 0
                        Text("\(percentage)%")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding()
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(syncCoordinator.logEntries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.date, style: .time)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                            .fixedSize()
                                        Text(entry.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            Color(.systemGroupedBackground),
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayedServer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let username = KeychainHelper.loadUsername() {
                    Text(username)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.tint)

            Text(L("sync_setup_title"))
                .font(.title3.weight(.semibold))

            Text(L("sync_setup_subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(L("sync_setup_ankiweb_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(
                        Color(.secondarySystemGroupedBackground),
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
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(L("sync_setup_self_hosted_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
            }

            Button(L("sync_setup_offline")) {
                isPresented = false
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Success View

    @ViewBuilder
    private func successView(_ summary: SyncSummary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(L("sync_complete_title"))
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                if summary.cardsPulled > 0 { Text(L("sync_cards_received", summary.cardsPulled)) }
                if summary.cardsPushed > 0 { Text(L("sync_cards_sent", summary.cardsPushed)) }
                if summary.notesPulled > 0 { Text(L("sync_notes_received", summary.notesPulled)) }
                if summary.notesPushed > 0 { Text(L("sync_notes_sent", summary.notesPushed)) }
                if summary.cardsPulled == 0 && summary.cardsPushed == 0 {
                    Text(L("sync_up_to_date"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !syncCoordinator.logEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("sync_log_section_title"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(syncCoordinator.logEntries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.date, style: .time)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .fixedSize()
                                    Text(entry.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 120)
                    .background(
                        Color(.systemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(L("sync_failed_title"))
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("btn_retry")) {
                Task { await startSync() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Full Sync Choice View

    private var fullSyncChoiceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(L("sync_full_required_title"))
                .font(.title3.weight(.semibold))
            Text(L("sync_full_required_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    Task { await fullSync(.download) }
                } label: {
                    Label(L("sync_btn_download"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await fullSync(.upload) }
                } label: {
                    Label(L("sync_btn_upload"), systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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
                }

                Section {
                    Button(L("btn_save")) {
                        save()
                    }
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(L("sync_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("btn_cancel")) { isPresented = false }
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
