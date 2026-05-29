import SwiftUI
import AnkiBackend
import AnkiProto
import AmgiTheme
import Dependencies
import SwiftProtobuf

struct DebugView: View {
    @Dependency(\.ankiBackend) var backend
    @Environment(\.palette) private var palette
    @AppStorage(DebugPreferences.Keys.cardRenderDiagnosticsEnabled) private var cardRenderDiagnosticsEnabled = false
    @AppStorage(DebugPreferences.Keys.cardRenderForceFrameReload) private var cardRenderForceFrameReload = true
    @AppStorage(DebugPreferences.Keys.cardRenderUseNilBaseURL) private var cardRenderUseNilBaseURL = true
    @AppStorage(DebugPreferences.Keys.cardRenderRedFrameBackground) private var cardRenderRedFrameBackground = true
    @AppStorage(DebugPreferences.Keys.cardRenderShowJSErrorOverlay) private var cardRenderShowJSErrorOverlay = true
    @State private var statusMessage = ""
    @State private var showResetAllConfirm = false

    var body: some View {
        List {
            if !statusMessage.isEmpty {
                Section(L("debug_section_status")) {
                    Text(statusMessage)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(palette.surfaceElevated)
                }
            }

            Section(L("debug_section_collection_info")) {
                Button(L("debug_dump_deck_tree")) {
                    dumpDeckTree()
                }
                .listRowBackground(palette.surfaceElevated)
            }

            Section(L("debug_section_card_render")) {
                Toggle(L("debug_card_render_enable"), isOn: $cardRenderDiagnosticsEnabled)
                    .listRowBackground(palette.surfaceElevated)

                if cardRenderDiagnosticsEnabled {
                    Toggle(L("debug_card_render_force_reload"), isOn: $cardRenderForceFrameReload)
                        .listRowBackground(palette.surfaceElevated)
                    Toggle(L("debug_card_render_nil_base_url"), isOn: $cardRenderUseNilBaseURL)
                        .listRowBackground(palette.surfaceElevated)
                    Toggle(L("debug_card_render_red_frame"), isOn: $cardRenderRedFrameBackground)
                        .listRowBackground(palette.surfaceElevated)
                    Toggle(L("debug_card_render_js_error_overlay"), isOn: $cardRenderShowJSErrorOverlay)
                        .listRowBackground(palette.surfaceElevated)

                    Text(L("debug_card_render_hint"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(palette.surfaceElevated)
                }
            }

            Section {
                Button(L("debug_reset_all_button"), role: .destructive) {
                    showResetAllConfirm = true
                }
                .listRowBackground(palette.surfaceElevated)
            } header: {
                Text(L("debug_section_danger"))
            } footer: {
                Text(L("debug_reset_all_confirm_msg"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(L("debug_nav_title"))
        .confirmationDialog(L("debug_reset_all_confirm_msg"), isPresented: $showResetAllConfirm, titleVisibility: .visible) {
            Button(L("debug_reset_confirm_button"), role: .destructive) {
                resetAllAppData()
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

    private func resetAllAppData() {
        try? backend.closeCollection()

        do {
            try AppUserStore.deleteAllAppData()
            NotificationCenter.default.post(name: AppUserStore.didChangeNotification, object: nil)
            NotificationCenter.default.post(name: AppSyncAuthEvents.didChangeNotification, object: nil)
            NotificationCenter.default.post(name: AppCollectionEvents.didResetNotification, object: nil)
            statusMessage = L("debug_reset_all_complete")
        } catch {
            statusMessage = L("debug_deck_tree_error", "\(error)")
        }
    }
}
