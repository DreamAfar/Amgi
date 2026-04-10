import SwiftUI
import AnkiKit
import AnkiClients
import AnkiSync
import Dependencies

struct SyncSheet: View {
    @Binding var isPresented: Bool
    @Dependency(\.syncClient) var syncClient

    @State private var syncState: SyncState = .idle
    @State private var showLogin = false
    @State private var showServerSetup = false

    private var syncMode: String {
        UserDefaults.standard.string(forKey: "syncMode") ?? "local"
    }

    enum SyncState {
        case idle
        case syncing(String)
        case success(SyncSummary)
        case error(String)
        case needsFullSync
        case noServer
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                serverConfigSection
                    .padding(.top)

                Spacer()
                switch syncState {
                case .idle:
                    ProgressView(L("sync_preparing"))
                case .syncing(let message):
                    ProgressView(message)
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
                    Button(L("sync_btn_done")) { isPresented = false }
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
        .task { await startSync() }
    }

    @ViewBuilder
    private var serverConfigSection: some View {
        VStack(spacing: 8) {
            if let endpoint = KeychainHelper.loadEndpoint() {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("sync_label_server"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(endpoint)
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
                    Menu {
                        Button(L("sync_menu_change_server")) {
                            showServerSetup = true
                        }
                        Button(L("sync_menu_logout"), role: .destructive) {
                            logout()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            } else if syncMode == "local" {
                HStack {
                    Label(L("sync_local_mode_label"), systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("sync_btn_setup_server")) {
                        showServerSetup = true
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
            }
        }
    }

    private func startSync() async {
        guard KeychainHelper.loadEndpoint() != nil else {
            syncState = .noServer
            return
        }

        guard KeychainHelper.loadHostKey() != nil else {
            showLogin = true
            return
        }

        syncState = .syncing(L("sync_syncing"))

        do {
            let summary = try await syncClient.sync()
            syncState = .syncing(L("sync_syncing_media"))
            _ = try? await syncClient.syncMedia()
            syncState = .success(summary)
        } catch let syncError as SyncError where syncError == .authFailed {
            showLogin = true
            syncState = .idle
        } catch let syncError as SyncError where syncError == .fullSyncRequired {
            syncState = .needsFullSync
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    private func logout() {
        KeychainHelper.deleteHostKey()
        KeychainHelper.deleteUsername()
        syncState = .idle
    }

    @ViewBuilder
    private var noServerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("sync_no_server_title"))
                .font(.title3.weight(.semibold))
            Text(L("sync_no_server_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("sync_btn_setup_server")) {
                showServerSetup = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

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
        }
    }

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
        syncState = .syncing(
            direction == .download ? L("sync_full_downloading") : L("sync_full_uploading")
        )
        do {
            try await syncClient.fullSync(direction)
            syncState = .success(SyncSummary())
        } catch {
            syncState = .error(error.localizedDescription)
        }
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
        UserDefaults.standard.set("custom", forKey: "syncMode")
        // Clear existing auth since server changed
        KeychainHelper.deleteHostKey()
        isPresented = false
        onComplete()
    }
}
