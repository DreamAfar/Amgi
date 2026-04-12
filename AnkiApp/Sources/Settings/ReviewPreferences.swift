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
        static let modeBase = "syncMode"
        static let syncMediaBase = "sync_pref_sync_media"
        static let ioTimeoutSecsBase = "sync_pref_io_timeout_secs"
        static let mediaLastLogBase = "sync_pref_media_last_log"
        static let mediaLastSyncedAtBase = "sync_pref_media_last_synced_at"

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
