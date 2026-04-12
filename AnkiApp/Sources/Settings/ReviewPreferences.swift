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
    }
}

enum SyncPreferences {
    enum Keys {
        static let mode = "syncMode"
        static let syncMedia = "sync_pref_sync_media"
        static let ioTimeoutSecs = "sync_pref_io_timeout_secs"
        static let mediaLastLog = "sync_pref_media_last_log"
        static let mediaLastSyncedAt = "sync_pref_media_last_synced_at"
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

    static func resolvedMode(_ rawValue: String) -> Mode {
        Mode(rawValue: rawValue) ?? .local
    }

    static func resolvedTimeout(_ rawValue: Int) -> Timeout {
        Timeout(rawValue: rawValue) ?? .seconds60
    }

    static func recordMediaSyncLog(_ message: String, date: Date = .now) {
        UserDefaults.standard.set(message, forKey: Keys.mediaLastLog)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.mediaLastSyncedAt)
    }
}
