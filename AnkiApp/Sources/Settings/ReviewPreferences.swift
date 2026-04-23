import Foundation

enum ReviewPreferences {
    enum Keys {
        static let autoplayAudio = "review_pref_autoplay_audio"
        static let playAudioInSilentMode = "review_pref_play_audio_in_silent_mode"
        static let showContextMenuButton = "review_pref_show_context_menu_button"
        static let showAudioReplayButton = "review_pref_show_audio_replay_button"
        static let showCorrectnessSymbols = "review_pref_show_correctness_symbols"
        static let disperseAnswerButtons = "review_pref_disperse_answer_buttons"
        static let showAnswerButtons = "review_pref_show_answer_buttons"
        static let showRemainingDays = "review_pref_show_remaining_days"
        static let showNextReviewTime = "review_pref_show_next_review_time"
        static let openLinksExternally = "review_pref_open_links_externally"
        static let cardContentAlignment = "review_pref_card_content_alignment"
        static let glassAnswerButtons = "review_pref_glass_answer_buttons"
        static let autoMatchCardBackground = "review_pref_auto_match_card_background"
    }
}

enum ReaderPreferences {
    enum Keys {
        static let showTab = "reader_pref_show_tab"
        static let tapLookup = "reader_pref_tap_lookup"
        static let deckID = "reader_pref_deck_id"
        static let notetypeID = "reader_pref_notetype_id"
        static let bookIDField = "reader_pref_book_id_field"
        static let bookTitleField = "reader_pref_book_title_field"
        static let chapterTitleField = "reader_pref_chapter_title_field"
        static let chapterOrderField = "reader_pref_chapter_order_field"
        static let contentField = "reader_pref_content_field"
        static let languageField = "reader_pref_language_field"
        static let verticalLayout = "reader_pref_vertical_layout"
        static let fontSize = "reader_pref_font_size"
        static let hideFurigana = "reader_pref_hide_furigana"
        static let horizontalPadding = "reader_pref_horizontal_padding"
        static let verticalPadding = "reader_pref_vertical_padding"
        static let layoutAdvanced = "reader_pref_layout_advanced"
        static let lineHeight = "reader_pref_line_height"
        static let characterSpacing = "reader_pref_character_spacing"
        static let showTitle = "reader_pref_show_title"
        static let showPercentage = "reader_pref_show_percentage"
        static let showProgressTop = "reader_pref_show_progress_top"
        static let popupWidth = "reader_pref_popup_width"
        static let popupHeight = "reader_pref_popup_height"
        static let popupFullWidth = "reader_pref_popup_full_width"
        static let popupSwipeToDismiss = "reader_pref_popup_swipe_to_dismiss"
        static let dictionaryMaxResults = "reader_pref_dictionary_max_results"
        static let dictionaryScanLength = "reader_pref_dictionary_scan_length"
    }
}

enum DebugPreferences {
    enum Keys {
        static let cardRenderDiagnosticsEnabled = "debug_pref_card_render_enabled"
        static let cardRenderForceFrameReload = "debug_pref_card_render_force_reload"
        static let cardRenderUseNilBaseURL = "debug_pref_card_render_nil_base_url"
        static let cardRenderRedFrameBackground = "debug_pref_card_render_red_frame"
        static let cardRenderShowJSErrorOverlay = "debug_pref_card_render_js_error_overlay"
    }
}

enum SyncPreferences {
    enum Keys {
        static let modeBase = "syncMode"
        static let syncMediaBase = "sync_pref_sync_media"
        static let ioTimeoutSecsBase = "sync_pref_io_timeout_secs"
        static let mediaLastLogBase = "sync_pref_media_last_log"
        static let mediaLastSyncedAtBase = "sync_pref_media_last_synced_at"
        static let lastCollectionSyncedAtBase = "sync_pref_collection_last_synced_at"

        static func modeForCurrentUser() -> String {
            scoped(modeBase)
        }

        static func syncMediaForCurrentUser() -> String {
            scoped(syncMediaBase)
        }

        static func ioTimeoutSecsForCurrentUser() -> String {
            scoped(ioTimeoutSecsBase)
        }

        static func mediaLastLogForCurrentUser() -> String {
            scoped(mediaLastLogBase)
        }

        static func mediaLastSyncedAtForCurrentUser() -> String {
            scoped(mediaLastSyncedAtBase)
        }

        static func lastCollectionSyncedAtForCurrentUser() -> String {
            scoped(lastCollectionSyncedAtBase)
        }

        private static func scoped(_ base: String) -> String {
            "\(base).\(SyncPreferences.currentProfileID())"
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case official
        case custom
        case local

        var id: String { rawValue }
    }

    enum Timeout: Int, CaseIterable, Identifiable {
        case seconds15 = 15
        case seconds30 = 30
        case seconds60 = 60
        case seconds120 = 120

        static let defaultValue = seconds60.rawValue

        var id: Int { rawValue }
    }

    static let officialServerLabel = "AnkiWeb"

    private static func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return profile.isEmpty ? "default" : profile
    }

    static func resolvedMode(_ rawValue: String) -> Mode {
        Mode(rawValue: rawValue) ?? .local
    }

    static func resolvedTimeout(_ rawValue: Int) -> Timeout {
        Timeout(rawValue: rawValue) ?? .seconds60
    }

    static func recordMediaSyncLog(_ message: String, date: Date = .now) {
        UserDefaults.standard.set(message, forKey: Keys.mediaLastLogForCurrentUser())
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.mediaLastSyncedAtForCurrentUser())
    }
}
