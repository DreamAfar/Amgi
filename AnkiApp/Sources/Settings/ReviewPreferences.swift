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
    }
}
