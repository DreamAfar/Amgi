import Foundation

enum ReaderThemeMode: String, CaseIterable, Identifiable {
    case system
    case eyeCare
    case sepia
    case custom

    var id: String { rawValue }
}

enum ReaderLibrarySourceMode: String, CaseIterable, Identifiable {
    case ankiNotes = "anki_notes"
    case epub = "epub"

    var id: String { rawValue }
}

enum ReviewPreferences {
    enum TapGestureLayout: String, CaseIterable, Identifiable, Sendable {
        case threeRows
        case nineGrid

        var id: String { rawValue }
    }

    enum TapGestureRegion: String, CaseIterable, Identifiable, Sendable {
        case topLeft
        case topCenter
        case topRight
        case middleLeft
        case middleCenter
        case middleRight
        case bottomLeft
        case bottomCenter
        case bottomRight

        var id: String { rawValue }

        var collapsedToThreeRows: Self {
            switch self {
            case .topLeft, .topCenter, .topRight:
                return .topCenter
            case .middleLeft, .middleCenter, .middleRight:
                return .middleCenter
            case .bottomLeft, .bottomCenter, .bottomRight:
                return .bottomCenter
            }
        }
    }

    enum GestureAction: String, CaseIterable, Identifiable, Sendable {
        case none
        case showAnswer
        case again
        case hard
        case good
        case easy
        case replayAudio
        case goBack
        case showContextMenu
        case editNote
        case editTemplate
        case undo
        case showDeckStats
        case showCardInfo
        case moveToDeck
        case changeNotetype
        case setDueDate
        case suspendCard
        case buryCard
        case resetCard
        case flagNone
        case flagRed
        case flagOrange
        case flagGreen
        case flagBlue
        case flagPink
        case flagCyan
        case flagPurple
        case userAction1
        case userAction2
        case userAction3
        case userAction4
        case userAction5
        case userAction6
        case userAction7
        case userAction8
        case userAction9

        var id: String { rawValue }
    }

    enum ControllerButton: String, CaseIterable, Identifiable, Sendable {
        case buttonA
        case buttonB
        case buttonX
        case buttonY
        case dpadUp
        case dpadDown
        case dpadLeft
        case dpadRight
        case leftShoulder
        case rightShoulder
        case leftTrigger
        case rightTrigger
        case leftThumbstick
        case rightThumbstick
        case options
        case menu

        var id: String { rawValue }
    }

    enum KeyboardShortcut: String, CaseIterable, Identifiable, Sendable {
        case space
        case enter
        case number1
        case number2
        case number3
        case number4
        case replay
        case command1
        case command2
        case command3
        case command4
        case command5
        case command6
        case command7
        case command8
        case command9

        var id: String { rawValue }
    }

    enum Keys {
        static let playAudioInSilentMode = "review_pref_play_audio_in_silent_mode"
        static let showContextMenuButton = "review_pref_show_context_menu_button"
        static let showAudioReplayButton = "review_pref_show_audio_replay_button"
        static let showCorrectnessSymbols = "review_pref_show_correctness_symbols"
        static let disperseAnswerButtons = "review_pref_disperse_answer_buttons"
        static let showAnswerButtons = "review_pref_show_answer_buttons"
        static let smallReviewButtons = "review_pref_small_review_buttons"
        static let hideHardAndEasyButtons = "review_pref_hide_hard_and_easy_buttons"
        static let showRemainingDays = "review_pref_show_remaining_days"
        static let showNextReviewTime = "review_pref_show_next_review_time"
        static let openLinksExternally = "review_pref_open_links_externally"
        static let lookupPopupEnabled = "review_pref_lookup_popup_enabled"
        static let lookupPopupFrontEnabled = "review_pref_lookup_popup_front_enabled"
        static let lookupPopupBackEnabled = "review_pref_lookup_popup_back_enabled"
        static let selectionMenuLookupEnabled = "review_pref_selection_menu_lookup_enabled"
        static let selectionMenuAIEnabled = "review_pref_selection_menu_ai_enabled"
        static let selectionMenuLookupTemplate = "review_pref_selection_menu_lookup_template"
        static let selectionMenuLookupPresets = "review_pref_selection_menu_lookup_presets"
        static let selectionMenuAIEndpoint = "review_pref_selection_menu_ai_endpoint"
        static let selectionMenuAIModel = "review_pref_selection_menu_ai_model"
        static let selectionMenuAISystemPrompt = "review_pref_selection_menu_ai_system_prompt"
        static let selectionMenuAIGlossary = "review_pref_selection_menu_ai_glossary"
        static let selectionMenuAIPresets = "review_pref_selection_menu_ai_presets"
        static let selectionMenuAIQuickActions = "review_pref_selection_menu_ai_quick_actions"
        static let aiFavorites = "review_pref_ai_favorites"
        static let aiNoteTemplate = "review_pref_ai_note_template"
        static let cardContentAlignment = "review_pref_card_content_alignment"
        static let glassAnswerButtons = "review_pref_glass_answer_buttons"
        static let autoMatchCardBackground = "review_pref_auto_match_card_background"
        static let dayStartHour = "review_pref_day_start_hour"
        static let dailyReminderEnabledBase = "review_pref_daily_reminder_enabled"
        static let dailyReminderHourBase = "review_pref_daily_reminder_hour"
        static let dailyReminderMinuteBase = "review_pref_daily_reminder_minute"
        static let frontTapGestureAction = "review_pref_front_tap_gesture_action"
        static let frontSwipeLeftGestureAction = "review_pref_front_swipe_left_gesture_action"
        static let frontSwipeRightGestureAction = "review_pref_front_swipe_right_gesture_action"
        static let backTapGestureAction = "review_pref_back_tap_gesture_action"
        static let backSwipeLeftGestureAction = "review_pref_back_swipe_left_gesture_action"
        static let backSwipeRightGestureAction = "review_pref_back_swipe_right_gesture_action"
        static let tapGestureLayout = "review_pref_tap_gesture_layout"
        static let frontTapGestureRegionPrefix = "review_pref_front_tap_region_"
        static let backTapGestureRegionPrefix = "review_pref_back_tap_region_"
        static let controllerButtonPrefix = "review_pref_controller_"
        static let keyboardShortcutPrefix = "review_pref_keyboard_"

        static func controllerButtonAction(_ button: ControllerButton) -> String {
            controllerButtonPrefix + button.rawValue
        }

        static func keyboardShortcutAction(_ shortcut: KeyboardShortcut) -> String {
            keyboardShortcutPrefix + shortcut.rawValue
        }

        static func tapGestureRegionAction(
            isBackSide: Bool,
            region: TapGestureRegion
        ) -> String {
            let prefix = isBackSide ? backTapGestureRegionPrefix : frontTapGestureRegionPrefix
            return prefix + region.rawValue
        }

        static func dailyReminderEnabledForCurrentUser() -> String {
            scoped(dailyReminderEnabledBase)
        }

        static func dailyReminderHourForCurrentUser() -> String {
            scoped(dailyReminderHourBase)
        }

        static func dailyReminderMinuteForCurrentUser() -> String {
            scoped(dailyReminderMinuteBase)
        }

        private static func scoped(_ base: String) -> String {
            "\(base).\(ReviewPreferences.currentProfileID())"
        }
    }

    private static func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return profile.isEmpty ? "default" : profile
    }
}

enum ReaderPreferences {
    enum Keys {
        static let showTabBase = "reader_pref_show_tab"
        static let tapLookupBase = "reader_pref_tap_lookup"
        static let sourceModeBase = "reader_pref_source_mode"
        static let deckIDBase = "reader_pref_deck_id"
        static let notetypeIDBase = "reader_pref_notetype_id"
        static let bookIDFieldBase = "reader_pref_book_id_field"
        static let bookTitleFieldBase = "reader_pref_book_title_field"
        static let bookCoverFieldBase = "reader_pref_book_cover_field"
        static let chapterTitleFieldBase = "reader_pref_chapter_title_field"
        static let chapterOrderFieldBase = "reader_pref_chapter_order_field"
        static let contentFieldBase = "reader_pref_content_field"
        static let languageFieldBase = "reader_pref_language_field"
        static let bookshelfColumnsBase = "reader_pref_bookshelf_columns"
        static let verticalLayoutBase = "reader_pref_vertical_layout"
        static let selectedFontBase = "reader_pref_selected_font"
        static let fontSizeBase = "reader_pref_font_size"
        static let hideFuriganaBase = "reader_pref_hide_furigana"
        static let horizontalPaddingBase = "reader_pref_horizontal_padding"
        static let verticalPaddingBase = "reader_pref_vertical_padding"
        static let avoidPageBreakBase = "reader_pref_avoid_page_break"
        static let justifyTextBase = "reader_pref_justify_text"
        static let layoutAdvancedBase = "reader_pref_layout_advanced"
        static let lineHeightBase = "reader_pref_line_height"
        static let characterSpacingBase = "reader_pref_character_spacing"
        static let showTitleBase = "reader_pref_show_title"
        static let showPercentageBase = "reader_pref_show_percentage"
        static let showProgressTopBase = "reader_pref_show_progress_top"
        static let themeModeBase = "reader_pref_theme_mode"
        static let customContentColorBase = "reader_pref_custom_content_color"
        static let customBackgroundColorBase = "reader_pref_custom_background_color"
        static let customTextColorBase = "reader_pref_custom_text_color"
        static let customHintColorBase = "reader_pref_custom_hint_color"
        static let popupWidthBase = "reader_pref_popup_width"
        static let popupHeightBase = "reader_pref_popup_height"
        static let popupFontSizeBase = "reader_pref_popup_font_size"
        static let popupFrequencyFontSizeBase = "reader_pref_popup_frequency_font_size"
        static let popupContentFontSizeBase = "reader_pref_popup_content_font_size"
        static let popupDictionaryNameFontSizeBase = "reader_pref_popup_dictionary_name_font_size"
        static let popupKanaFontSizeBase = "reader_pref_popup_kana_font_size"
        static let popupFullWidthBase = "reader_pref_popup_full_width"
        static let popupSwipeToDismissBase = "reader_pref_popup_swipe_to_dismiss"
        static let popupCollapseDictionariesBase = "reader_pref_popup_collapse_dictionaries"
        static let popupCompactGlossariesBase = "reader_pref_popup_compact_glossaries"
        static let popupAudioSourcePresetBase = "reader_pref_popup_audio_source_preset"
        static let popupAudioSourceTemplateBase = "reader_pref_popup_audio_source_template"
        static let popupLocalAudioEnabledBase = "reader_pref_popup_local_audio_enabled"
        static let popupAudioAutoplayBase = "reader_pref_popup_audio_autoplay"
        static let popupAudioPlaybackModeBase = "reader_pref_popup_audio_playback_mode"
        static let popupDebugInfoEnabledBase = "reader_pref_popup_debug_info_enabled"
        static let dictionaryMaxResultsBase = "reader_pref_dictionary_max_results"
        static let dictionaryScanLengthBase = "reader_pref_dictionary_scan_length"
        static let lookupNoteTemplateBase = "reader_pref_lookup_note_template"
        static let enableStatisticsBase = "reader_pref_enable_statistics"
        static let statisticsAutostartModeBase = "reader_pref_statistics_autostart_mode"

        static let allBases = [
            showTabBase,
            tapLookupBase,
            sourceModeBase,
            deckIDBase,
            notetypeIDBase,
            bookIDFieldBase,
            bookTitleFieldBase,
            bookCoverFieldBase,
            chapterTitleFieldBase,
            chapterOrderFieldBase,
            contentFieldBase,
            languageFieldBase,
            bookshelfColumnsBase,
            verticalLayoutBase,
            selectedFontBase,
            fontSizeBase,
            hideFuriganaBase,
            horizontalPaddingBase,
            verticalPaddingBase,
            avoidPageBreakBase,
            justifyTextBase,
            layoutAdvancedBase,
            lineHeightBase,
            characterSpacingBase,
            showTitleBase,
            showPercentageBase,
            showProgressTopBase,
            themeModeBase,
            customContentColorBase,
            customBackgroundColorBase,
            customTextColorBase,
            customHintColorBase,
            popupWidthBase,
            popupHeightBase,
            popupFontSizeBase,
            popupFrequencyFontSizeBase,
            popupContentFontSizeBase,
            popupDictionaryNameFontSizeBase,
            popupKanaFontSizeBase,
            popupFullWidthBase,
            popupSwipeToDismissBase,
            popupCollapseDictionariesBase,
            popupCompactGlossariesBase,
            popupAudioSourcePresetBase,
            popupAudioSourceTemplateBase,
            popupLocalAudioEnabledBase,
            popupAudioAutoplayBase,
            popupAudioPlaybackModeBase,
            popupDebugInfoEnabledBase,
            dictionaryMaxResultsBase,
            dictionaryScanLengthBase,
            lookupNoteTemplateBase,
            enableStatisticsBase,
            statisticsAutostartModeBase,
        ]

        static var showTab: String { scoped(showTabBase) }
        static var tapLookup: String { scoped(tapLookupBase) }
        static var sourceMode: String { scoped(sourceModeBase) }
        static var deckID: String { scoped(deckIDBase) }
        static var notetypeID: String { scoped(notetypeIDBase) }
        static var bookIDField: String { scoped(bookIDFieldBase) }
        static var bookTitleField: String { scoped(bookTitleFieldBase) }
        static var bookCoverField: String { scoped(bookCoverFieldBase) }
        static var chapterTitleField: String { scoped(chapterTitleFieldBase) }
        static var chapterOrderField: String { scoped(chapterOrderFieldBase) }
        static var contentField: String { scoped(contentFieldBase) }
        static var languageField: String { scoped(languageFieldBase) }
        static var bookshelfColumns: String { scoped(bookshelfColumnsBase) }
        static var verticalLayout: String { scoped(verticalLayoutBase) }
        static var selectedFont: String { scoped(selectedFontBase) }
        static var fontSize: String { scoped(fontSizeBase) }
        static var hideFurigana: String { scoped(hideFuriganaBase) }
        static var horizontalPadding: String { scoped(horizontalPaddingBase) }
        static var verticalPadding: String { scoped(verticalPaddingBase) }
        static var avoidPageBreak: String { scoped(avoidPageBreakBase) }
        static var justifyText: String { scoped(justifyTextBase) }
        static var layoutAdvanced: String { scoped(layoutAdvancedBase) }
        static var lineHeight: String { scoped(lineHeightBase) }
        static var characterSpacing: String { scoped(characterSpacingBase) }
        static var showTitle: String { scoped(showTitleBase) }
        static var showPercentage: String { scoped(showPercentageBase) }
        static var showProgressTop: String { scoped(showProgressTopBase) }
        static var themeMode: String { scoped(themeModeBase) }
        static var customContentColor: String { scoped(customContentColorBase) }
        static var customBackgroundColor: String { scoped(customBackgroundColorBase) }
        static var customTextColor: String { scoped(customTextColorBase) }
        static var customHintColor: String { scoped(customHintColorBase) }
        static var popupWidth: String { scoped(popupWidthBase) }
        static var popupHeight: String { scoped(popupHeightBase) }
        static var popupFontSize: String { scoped(popupFontSizeBase) }
        static var popupFrequencyFontSize: String { scoped(popupFrequencyFontSizeBase) }
        static var popupContentFontSize: String { scoped(popupContentFontSizeBase) }
        static var popupDictionaryNameFontSize: String { scoped(popupDictionaryNameFontSizeBase) }
        static var popupKanaFontSize: String { scoped(popupKanaFontSizeBase) }
        static var popupFullWidth: String { scoped(popupFullWidthBase) }
        static var popupSwipeToDismiss: String { scoped(popupSwipeToDismissBase) }
        static var popupCollapseDictionaries: String { scoped(popupCollapseDictionariesBase) }
        static var popupCompactGlossaries: String { scoped(popupCompactGlossariesBase) }
        static var popupAudioSourcePreset: String { scoped(popupAudioSourcePresetBase) }
        static var popupAudioSourceTemplate: String { scoped(popupAudioSourceTemplateBase) }
        static var popupLocalAudioEnabled: String { scoped(popupLocalAudioEnabledBase) }
        static var popupAudioAutoplay: String { scoped(popupAudioAutoplayBase) }
        static var popupAudioPlaybackMode: String { scoped(popupAudioPlaybackModeBase) }
        static var popupDebugInfoEnabled: String { scoped(popupDebugInfoEnabledBase) }
        static var dictionaryMaxResults: String { scoped(dictionaryMaxResultsBase) }
        static var dictionaryScanLength: String { scoped(dictionaryScanLengthBase) }
        static var lookupNoteTemplate: String { scoped(lookupNoteTemplateBase) }
        static var enableStatistics: String { scoped(enableStatisticsBase) }
        static var statisticsAutostartMode: String { scoped(statisticsAutostartModeBase) }

        private static func scoped(_ base: String) -> String {
            ReaderPreferences.scopedKey(for: base, profileID: ReaderPreferences.currentProfileID())
        }
    }

    static let legacyMigrationMarkerBase = "reader_pref_legacy_migrated"

    static func migrateLegacyDefaultsIfNeeded(for user: String) {
        let defaults = UserDefaults.standard
        let profileID = currentProfileID(for: user)
        let markerKey = migrationMarkerKey(for: profileID)
        guard defaults.bool(forKey: markerKey) == false else { return }

        for base in Keys.allBases {
            let scopedKey = scopedKey(for: base, profileID: profileID)
            if defaults.object(forKey: scopedKey) == nil,
               let legacyValue = defaults.object(forKey: base) {
                defaults.set(legacyValue, forKey: scopedKey)
            }
            defaults.removeObject(forKey: base)
        }

        defaults.set(true, forKey: markerKey)
    }

    static func scopedKey(for base: String, profileID: String) -> String {
        "\(base).\(profileID)"
    }

    static func migrationMarkerKey(for profileID: String) -> String {
        scopedKey(for: legacyMigrationMarkerBase, profileID: profileID)
    }

    private static func currentProfileID() -> String {
        currentProfileID(for: AppUserStore.loadSelectedUser())
    }

    private static func currentProfileID(for user: String) -> String {
        AppUserStore.profileID(for: user)
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
        static let backgroundSyncEnabledBase = "sync_pref_background_sync_enabled"
        static let ioTimeoutSecsBase = "sync_pref_io_timeout_secs"
        static let mediaLastLogBase = "sync_pref_media_last_log"
        static let mediaLastSyncedAtBase = "sync_pref_media_last_synced_at"
        static let lastCollectionSyncedAtBase = "sync_pref_collection_last_synced_at"
        static let schemaPendingFullUploadBase = "sync_pref_schema_pending_full_upload"

        static func modeForCurrentUser() -> String {
            scoped(modeBase)
        }

        static func syncMediaForCurrentUser() -> String {
            scoped(syncMediaBase)
        }

        static func backgroundSyncEnabledForCurrentUser() -> String {
            scoped(backgroundSyncEnabledBase)
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

        static func schemaPendingFullUploadForCurrentUser() -> String {
            scoped(schemaPendingFullUploadBase)
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

    static func recordCollectionSync(date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.lastCollectionSyncedAtForCurrentUser())
    }
}
