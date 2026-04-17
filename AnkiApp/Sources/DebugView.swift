import SwiftUI
import AnkiBackend
import AnkiProto
import AnkiSync
import Dependencies
import Foundation
import SwiftProtobuf

struct DebugView: View {
    @Dependency(\.ankiBackend) var backend
    @State private var statusMessage = ""
    @State private var showResetConfirm = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        List {
            Section(L("debug_section_account")) {
                HStack {
                    Text(L("debug_username"))
                    Spacer()
                    Text(KeychainHelper.loadUsername() ?? L("debug_not_logged_in"))
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                .listRowBackground(Color.amgiSurfaceElevated)
                HStack {
                    Text(L("debug_host_key"))
                    Spacer()
                    Text(KeychainHelper.loadHostKey() != nil ? L("debug_stored") : L("common_none"))
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                .listRowBackground(Color.amgiSurfaceElevated)
                Button(L("debug_logout"), role: .destructive) {
                    AppSyncAuthEvents.clearCredentials()
                    statusMessage = L("debug_logged_out_msg")
                }
                .listRowBackground(Color.amgiSurfaceElevated)
            }

            Section(L("debug_section_import_export")) {
                Button(L("debug_export_button")) {
                    do {
                        let url = try ImportHelper.exportCollection(backend: backend)
                        exportedFileURL = url
                        showShareSheet = true
                        statusMessage = L("debug_export_ready", url.lastPathComponent)
                    } catch {
                        statusMessage = L("debug_export_error", error.localizedDescription)
                    }
                }
                .listRowBackground(Color.amgiSurfaceElevated)
            }

            Section(L("debug_section_database")) {
                Button(L("debug_check_db")) {
                    do {
                        let responseBytes = try backend.call(
                            service: AnkiBackend.Service.collection,
                            method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                        )
                        statusMessage = L("debug_check_db_ok", responseBytes.count)
                    } catch {
                        statusMessage = L("debug_check_db_error", "\(error)")
                    }
                }
                .listRowBackground(Color.amgiSurfaceElevated)

                Button(L("debug_reset_button"), role: .destructive) {
                    showResetConfirm = true
                }
                .listRowBackground(Color.amgiSurfaceElevated)
                .confirmationDialog(L("debug_reset_confirm_msg"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                    Button(L("debug_reset_confirm_button"), role: .destructive) {
                        resetEverything()
                    }
                }
            }

            if !statusMessage.isEmpty {
                Section(L("debug_section_status")) {
                    Text(statusMessage)
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.amgiSurfaceElevated)
                }
            }

            Section(L("debug_section_collection_info")) {
                Button(L("debug_dump_deck_tree")) {
                    dumpDeckTree()
                }
                .listRowBackground(Color.amgiSurfaceElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("debug_nav_title"))
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func dumpDeckTree() {
        do {
            var req = Anki_Decks_DeckTreeRequest()
            req.now = Int64(Date().timeIntervalSince1970)

            let responseBytes = try backend.call(
                service: AnkiBackend.Service.decks,
                method: AnkiBackend.DecksMethod.getDeckTree,
                request: req
            )

            let tree = try Anki_Decks_DeckTreeNode(serializedBytes: responseBytes)
            var info = "Root: id=\(tree.deckID), name='\(tree.name)', children=\(tree.children.count)\n"
            for child in tree.children {
                info += "  [\(child.deckID)] \(child.name) — new:\(child.newCount) learn:\(child.learnCount) review:\(child.reviewCount)\n"
                for sub in child.children {
                    info += "    [\(sub.deckID)] \(sub.name)\n"
                }
            }
            statusMessage = info
            print("[Debug] DeckTree:\n\(info)")
        } catch {
            statusMessage = L("debug_deck_tree_error", "\(error)")
            print("[Debug] DeckTree error: \(error)")
        }
    }

    private func resetEverything() {
        // Clear keychain
        AppSyncAuthEvents.clearCredentials()

        // Close collection
        try? backend.closeCollection()

        // Delete database files
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let ankiDir = appSupport.appendingPathComponent("AnkiCollection", isDirectory: true)
        try? FileManager.default.removeItem(at: ankiDir)

        // Remove migration marker so it recreates fresh
        statusMessage = L("debug_reset_complete")
        NotificationCenter.default.post(name: AppCollectionEvents.didResetNotification, object: nil)
    }
}
