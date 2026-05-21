import SwiftUI
import AnkiKit
import AnkiClients
import AnkiSync
import Dependencies

struct SyncSheet: View {
    private enum StatusHeaderTone {
        case primary
        case positive
        case warning
    }

    private let syncLogHeight: CGFloat = 220
    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH: mm: ss"
        return formatter
    }()

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                serverConfigSection

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
                case .needsFullSync(let requirement):
                    fullSyncChoiceView(requirement)
                case .noServer:
                    noServerView
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
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
                        Button {
                            isPresented = false
                        } label: {
                            Text(L("sync_btn_background"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
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
        VStack(spacing: 12) {
            statusHeader(title: syncStageTitle(for: message)) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }

            if let detail = syncStageDetail(for: message) {
                Text(detail)
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            syncLogView(height: syncLogHeight)
        }
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

    private func syncLogView(height: CGFloat) -> some View {
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
                                Text(Self.logTimestampFormatter.string(from: entry.date))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.amgiTextTertiary)
                                    .fixedSize()
                                Text(entry.message)
                                    .amgiFont(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: height)
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

    @ViewBuilder
    private func mediaProgressView(total: Int, downloaded: Int) -> some View {
        VStack(spacing: 16) {
            statusHeader(title: L("sync_syncing_media")) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }

            if total > 0 {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("sync_media_size_info", downloaded, total))
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        Spacer()
                    }

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
                .padding()
                .background(
                    Color.amgiSurfaceElevated,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }

            syncLogView(height: syncLogHeight)
        }
    }

    // MARK: - Server Config Header

    @ViewBuilder
    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("sync_settings_server_type"))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                Text(serverTypeLabel)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if syncMode == .custom {
                    Menu {
                        Button(L("sync_menu_change_server")) {
                            showServerSetup = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            if syncMode == .official {
                ankiWebSupportNotice()
            }
        }
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

        if SchemaChangeFullSyncGuard.needsFullUpload() {
            syncCoordinator.reset()
            syncCoordinator.setState(
                .needsFullSync(
                    SyncFullSyncRequirement(kind: .uploadOnly)
                )
            )
            return
        }

        syncCoordinator.startSync(syncClient: syncClient, syncMediaEnabled: syncMediaEnabled)
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
            statusHeader(title: L("sync_complete_title"), tone: .positive) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AmgiFont.sectionHeading.font)
                    .foregroundStyle(Color.amgiPositive)
            }
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
                                    Text(Self.logTimestampFormatter.string(from: entry.date))
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
                    .frame(height: syncLogHeight)
                    .background(
                        Color.amgiSurface,
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
            statusHeader(title: L("sync_failed_title"), tone: .warning) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.amgiWarning)
            }
            Text(message)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)
            Button(L("btn_retry")) {
                Task { await startSync() }
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .tint(Color.amgiAccent)
        }
    }

    // MARK: - Full Sync Choice View

    private func fullSyncChoiceView(_ requirement: SyncFullSyncRequirement) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(L("sync_full_required_title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Text(fullSyncDescription(for: requirement))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            VStack(spacing: 10) {
                if requirement.kind != .uploadOnly {
                    Button {
                        Task { await fullSync(.download, requirement: requirement) }
                    } label: {
                        Label(L("sync_btn_download"), systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FullSyncActionButtonStyle(kind: .primary))
                }

                if requirement.kind != .downloadOnly {
                    if requirement.kind == .uploadOnly {
                        Button {
                            Task { await fullSync(.upload, requirement: requirement) }
                        } label: {
                            Label(L("sync_btn_upload"), systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FullSyncActionButtonStyle(kind: .primary))
                    } else {
                        Button {
                            Task { await fullSync(.upload, requirement: requirement) }
                        } label: {
                            Label(L("sync_btn_upload"), systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FullSyncActionButtonStyle(kind: .secondary))
                    }
                }
            }
            .frame(maxWidth: 380)

            if let serverMessage = requirement.serverMessage,
               serverMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text(serverMessage)
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func fullSync(_ direction: SyncDirection, requirement: SyncFullSyncRequirement) async {
        syncCoordinator.startFullSync(
            direction,
            requirement: requirement,
            syncClient: syncClient,
            syncMediaEnabled: syncMediaEnabled
        )
    }

    private func fullSyncDescription(for requirement: SyncFullSyncRequirement) -> String {
        switch requirement.kind {
        case .conflict:
            return L("sync_full_conflict_desc")
        case .downloadOnly:
            return L("sync_full_download_confirm_desc")
        case .uploadOnly:
            if SchemaChangeFullSyncGuard.needsFullUpload() {
                return L("schema_change_confirm_message")
            }
            return L("sync_full_upload_confirm_desc")
        }
    }

    private func syncStageTitle(for message: String) -> String {
        if message == L("sync_full_downloading") || message == L("sync_full_uploading") {
            return message
        }
        return L("sync_stage_syncing_collection")
    }

    private func syncStageDetail(for message: String) -> String? {
        if message == L("sync_preparing") || message == L("sync_log_connecting") {
            return message
        }
        return nil
    }

    @ViewBuilder
    private func statusHeader<Accessory: View>(
        title: String,
        tone: StatusHeaderTone = .primary,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 8) {
            statusHeaderTitle(title, tone: tone)
            accessory()
        }
    }

    @ViewBuilder
    private func statusHeaderTitle(_ title: String, tone: StatusHeaderTone) -> some View {
        switch tone {
        case .primary:
            Text(title)
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)
        case .positive:
            Text(title)
                .amgiStatusText(.positive, font: .sectionHeading)
        case .warning:
            Text(title)
                .amgiStatusText(.warning, font: .sectionHeading)
        }
    }

    private func ankiWebSupportNotice() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("ankiweb_support_notice"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: "https://apps.apple.com/us/app/ankimobile-flashcards/id373493387") {
                HStack(spacing: 4) {
                    Text(L("common_view"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
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
}

private struct FullSyncActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .background(backgroundColor, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return Color.amgiAccent
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return Color.amgiAccent
        case .secondary:
            return Color.amgiAccent.opacity(0.16)
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
