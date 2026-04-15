import SwiftUI
import AnkiClients
import AnkiKit
import AnkiProto
import Dependencies

/// View for editing deck configuration (daily new cards, review limits, FSRS settings, etc.)
@MainActor
struct DeckConfigView: View {
    let deckId: Int64
    let onDismiss: () -> Void
    
    @Dependency(\.deckClient) var deckClient
    
    @State private var config: Anki_DeckConfig_DeckConfig?
    @State private var deckConfigContext: Anki_DeckConfig_DeckConfigsForUpdate?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isSaving = false
    
    // Form state
    @State private var newCardsPerDay: Int32 = 20
    @State private var reviewsPerDay: Int32 = 200
    @State private var learningStepsText: String = "1m 10m"
    @State private var relearningStepsText: String = "10m"
    @State private var graduatingGoodDays: Int32 = 1
    @State private var graduatingEasyDays: Int32 = 4
    @State private var leechThreshold: Int32 = 8

    @State private var fsrsEnabled: Bool = false
    @State private var desiredRetentionPercent: Double = 90
    @State private var fsrsWeights: String = ""
    @State private var isOptimizingFsrs = false
    @State private var isSimulatingFsrs = false
    @State private var fsrsSimulationSearch: String = ""
    @State private var retentionWorkload: [(retention: UInt32, cost: Float)] = []

    @State private var newCardInsertOrder: Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder = .due
    @State private var newMix: Anki_DeckConfig_DeckConfig.Config.ReviewMix = .mixWithReviews
    @State private var reviewOrder: Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder = .day
    @State private var interdayLearningMix: Anki_DeckConfig_DeckConfig.Config.ReviewMix = .mixWithReviews
    @State private var leechAction: Anki_DeckConfig_DeckConfig.Config.LeechAction = .suspend

    @State private var buryNew = true
    @State private var buryReviews = true
    @State private var buryInterdayLearning = false

    @State private var showTimer = false
    @State private var capAnswerTimeToSecs: Int32 = 60
    @State private var stopTimerOnAnswer = true

    @State private var secondsToShowQuestion: Double = 0
    @State private var secondsToShowAnswer: Double = 0
    @State private var questionAction: Anki_DeckConfig_DeckConfig.Config.QuestionAction = .showAnswer
    @State private var answerAction: Anki_DeckConfig_DeckConfig.Config.AnswerAction = .buryCard

    @State private var maximumReviewIntervalDays: Int32 = 36500
    @State private var intervalMultiplierPercent: Double = 100
    @State private var hardMultiplierPercent: Double = 120
    @State private var easyMultiplierPercent: Double = 130
    @State private var configName: String = ""
    @State private var selectedPresetID: Int64 = 0
    @State private var presetUseCount: UInt32 = 0
    @State private var disableAutoplay = false
    @State private var waitForAudio = false
    @State private var skipQuestionWhenReplayingAnswer = false
    @State private var easyDayPercentages: [Double] = Array(repeating: 100, count: 7)
    @State private var applyToChildren = false
    @State private var isManagingPreset = false
    @State private var showDeletePresetConfirmation = false
    @State private var showRenamePresetPrompt = false
    @State private var renamePresetDraft = ""

    // Collapsible section expanded states
    @State private var orderExpanded = false
    @State private var fsrsExpanded = false
    @State private var buryExpanded = false
    @State private var timerExpanded = false
    @State private var autoAdvanceExpanded = false
    @State private var advancedExpanded = false
    @State private var easyDaysExpanded = false

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        basicSection
                        dailyLimitsSection
                        newCardsSection
                        lapsesSection
                        orderSection
                        fsrsSection
                        burySection
                        timerSection
                        autoAdvanceSection
                        advancedSection
                        easyDaysSection
                    }
                }
            }
            .navigationTitle(L("deck_config_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Menu {
                            Button {
                                saveConfig(applyToChildren: false)
                            } label: {
                                Label(L("common_save"), systemImage: "checkmark")
                            }
                            Button {
                                saveConfig(applyToChildren: true)
                            } label: {
                                Label(L("deck_config_apply_children"), systemImage: "rectangle.stack")
                            }
                        } label: {
                            Text(L("common_save")).bold()
                        } primaryAction: {
                            saveConfig(applyToChildren: false)
                        }
                    }
                }
            }
            .alert(L("deck_config_save_failed"), isPresented: $showError) {
                Button(L("common_ok")) { }
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .alert(L("deck_config_preset_delete_title"), isPresented: $showDeletePresetConfirmation) {
                Button(L("common_delete"), role: .destructive) {
                    Task { await deleteSelectedPreset() }
                }
                Button(L("common_cancel"), role: .cancel) { }
            } message: {
                Text(deletePresetMessage)
            }
            .alert(L("deck_config_preset_rename"), isPresented: $showRenamePresetPrompt) {
                TextField(L("deck_config_name_placeholder"), text: $renamePresetDraft)
                Button(L("common_cancel"), role: .cancel) { }
                Button(L("common_save")) {
                    Task { await renameSelectedPreset() }
                }
            } message: {
                Text(L("deck_config_name"))
            }
            .task {
                await loadConfig()
            }
        }
    }

    private var presetOptions: [Anki_DeckConfig_DeckConfigsForUpdate.ConfigWithExtra] {
        (deckConfigContext?.allConfig ?? [])
            .sorted { $0.config.name.localizedCaseInsensitiveCompare($1.config.name) == .orderedAscending }
    }

    private var presetSelectionBinding: Binding<Int64> {
        Binding(
            get: { selectedPresetID },
            set: { newValue in
                let previousID = selectedPresetID
                selectedPresetID = newValue
                guard newValue != previousID else { return }
                Task { await selectPreset(from: previousID, to: newValue) }
            }
        )
    }

    private var canDeleteSelectedPreset: Bool {
        selectedPresetID != 1 && presetOptions.count > 1
    }

    private var deleteFallbackPreset: Anki_DeckConfig_DeckConfig? {
        presetOptions.first(where: { $0.config.id == 1 && $0.config.id != selectedPresetID })?.config
        ?? presetOptions.first(where: { $0.config.id != selectedPresetID })?.config
    }

    private var deletePresetMessage: String {
        let presetName = config?.name ?? configName
        let fallbackName = deleteFallbackPreset?.name ?? L("deck_config_preset_new_default_name")
        return L("deck_config_preset_delete_message", presetName, fallbackName)
    }

    // MARK: - Extracted Sections

    private var basicSection: some View {
        Section(L("deck_config_section_basic")) {
            Picker(L("deck_config_preset"), selection: presetSelectionBinding) {
                ForEach(presetOptions, id: \.config.id) { option in
                    Text(option.config.name)
                        .foregroundStyle(.blue)
                        .tag(option.config.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.blue)
            .disabled(isManagingPreset || presetOptions.isEmpty)

            LabeledContent(L("deck_config_preset_manage")) {
                if isManagingPreset {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        Button {
                            Task { await createPresetFromDefaults() }
                        } label: {
                            Label(L("deck_config_preset_add"), systemImage: "plus")
                        }

                        Button {
                            Task { await duplicateSelectedPreset() }
                        } label: {
                            Label(L("deck_config_preset_duplicate"), systemImage: "plus.square.on.square")
                        }
                        .disabled(config == nil)

                        Button {
                            renamePresetDraft = configName
                            showRenamePresetPrompt = true
                        } label: {
                            Label(L("deck_config_preset_rename"), systemImage: "pencil")
                        }
                        .disabled(config == nil)

                        Button(role: .destructive) {
                            showDeletePresetConfirmation = true
                        } label: {
                            Label(L("common_delete"), systemImage: "trash")
                        }
                        .disabled(!canDeleteSelectedPreset)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            LabeledContent(L("deck_config_name")) {
                TextField(L("deck_config_name_placeholder"), text: $configName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(L("deck_config_preset_usage")) {
                Text(L("deck_config_preset_used_by", Int(presetUseCount)))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var dailyLimitsSection: some View {
        Section(L("deck_config_section_daily")) {
            LabeledContent(L("deck_config_daily_new")) {
                Stepper("\(newCardsPerDay)", value: $newCardsPerDay, in: 0...1000)
                    .foregroundStyle(.blue)
            }
            LabeledContent(L("deck_config_daily_review")) {
                Stepper("\(reviewsPerDay)", value: $reviewsPerDay, in: 0...10000)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var newCardsSection: some View {
        Section(L("deck_config_section_new")) {
            LabeledContent(L("deck_config_learn_steps")) {
                TextField(L("deck_config_learn_steps_hint"), text: $learningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
                    .foregroundStyle(.blue)
            }
            LabeledContent(L("deck_config_good_interval")) {
                Stepper(L("deck_config_days_fmt", graduatingGoodDays), value: $graduatingGoodDays, in: 0...365)
                    .foregroundStyle(.blue)
            }
            LabeledContent(L("deck_config_easy_interval")) {
                Stepper(L("deck_config_days_fmt", graduatingEasyDays), value: $graduatingEasyDays, in: 0...365)
                    .foregroundStyle(.blue)
            }
            Picker(L("deck_config_insert_order"), selection: $newCardInsertOrder) {
                Text(L("deck_config_order_due")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.due)
                Text(L("deck_config_order_random")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.random)
            }
            .pickerStyle(.menu)
            .tint(.blue)
            Picker(L("deck_config_new_mix"), selection: $newMix) {
                Text(L("deck_config_mix_with_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                Text(L("deck_config_mix_after_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                Text(L("deck_config_mix_before_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
    }

    private var lapsesSection: some View {
        Section(L("deck_config_section_lapses")) {
            LabeledContent(L("deck_config_relearn_steps")) {
                TextField(L("deck_config_relearn_steps_hint"), text: $relearningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
                    .foregroundStyle(.blue)
            }
            LabeledContent(L("deck_config_leech_threshold")) {
                Stepper(L("deck_config_times_fmt", leechThreshold), value: $leechThreshold, in: 1...50)
                    .foregroundStyle(.blue)
            }
            Picker(L("deck_config_leech_action"), selection: $leechAction) {
                Text(L("deck_config_leech_suspend")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.suspend)
                Text(L("deck_config_leech_tag_only")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.tagOnly)
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
    }

    private var orderSection: some View {
        DisclosureGroup(L("deck_config_section_order"), isExpanded: $orderExpanded) {
            Picker(L("deck_config_review_order"), selection: $reviewOrder) {
                Text(L("deck_config_review_order_day")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.day)
                Text(L("deck_config_review_order_asc")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsAscending)
                Text(L("deck_config_review_order_desc")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsDescending)
                Text(L("deck_config_order_random")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.random)
            }
            .pickerStyle(.menu)
            .tint(.blue)
            Picker(L("deck_config_interday_mix"), selection: $interdayLearningMix) {
                Text(L("deck_config_mix_with_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                Text(L("deck_config_mix_after_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                Text(L("deck_config_mix_before_reviews")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var fsrsSection: some View {
        DisclosureGroup(L("deck_config_section_fsrs"), isExpanded: $fsrsExpanded) {
            Toggle(L("deck_config_fsrs_enable"), isOn: $fsrsEnabled)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_desired_retention"))
                    Spacer()
                    Text("\(Int(desiredRetentionPercent))%")
                        .foregroundStyle(.blue)
                }
                Slider(value: $desiredRetentionPercent, in: 70...97, step: 1)
                    .tint(.blue)
            }
            if fsrsEnabled {
                LabeledContent(L("deck_config_fsrs_weights")) {
                    TextField(L("deck_config_fsrs_weights_hint"), text: $fsrsWeights)
                        .multilineTextAlignment(.trailing)
                        .font(.monospaced(.caption)())
                        .foregroundStyle(.blue)
                }

                Section(L("deck_config_fsrs_simulator_section")) {
                    TextField(L("deck_config_fsrs_simulator_search_hint"), text: $fsrsSimulationSearch)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await runFsrsSimulation() }
                    } label: {
                        HStack {
                            if isSimulatingFsrs {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSimulatingFsrs ? L("deck_config_fsrs_simulator_running") : L("deck_config_fsrs_simulator_run"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSimulatingFsrs)

                    if !retentionWorkload.isEmpty {
                        ForEach(retentionWorkload, id: \.retention) { row in
                            HStack {
                                Text("\(row.retention)%")
                                Spacer()
                                Text(String(format: "%.2f", row.cost))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    } else {
                        Text(L("deck_config_fsrs_simulator_empty"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await optimizeFsrsPresets() }
                } label: {
                    HStack {
                        if isOptimizingFsrs {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isOptimizingFsrs ? L("deck_config_fsrs_optimize_running") : L("deck_config_fsrs_optimize_presets"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOptimizingFsrs)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var burySection: some View {
        DisclosureGroup(L("deck_config_section_bury"), isExpanded: $buryExpanded) {
            Toggle(L("deck_config_bury_new"), isOn: $buryNew)
            Toggle(L("deck_config_bury_reviews"), isOn: $buryReviews)
            Toggle(L("deck_config_bury_interday"), isOn: $buryInterdayLearning)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var timerSection: some View {
        DisclosureGroup(L("deck_config_section_timer"), isExpanded: $timerExpanded) {
            Toggle(L("deck_config_show_timer"), isOn: $showTimer)
            LabeledContent(L("deck_config_timer_cap")) {
                Stepper(L("deck_config_seconds_fmt", capAnswerTimeToSecs), value: $capAnswerTimeToSecs, in: 5...600)
                    .foregroundStyle(.blue)
            }
            Toggle(L("deck_config_stop_timer_on_answer"), isOn: $stopTimerOnAnswer)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var autoAdvanceSection: some View {
        DisclosureGroup(L("deck_config_section_auto_advance"), isExpanded: $autoAdvanceExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_question_secs"))
                    Spacer()
                    Text(String(format: "%.1f s", secondsToShowQuestion))
                        .foregroundStyle(.blue)
                }
                Slider(value: $secondsToShowQuestion, in: 0...60, step: 0.5)
                    .tint(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_answer_secs"))
                    Spacer()
                    Text(String(format: "%.1f s", secondsToShowAnswer))
                        .foregroundStyle(.blue)
                }
                Slider(value: $secondsToShowAnswer, in: 0...60, step: 0.5)
                    .tint(.blue)
            }
            Picker(L("deck_config_after_question"), selection: $questionAction) {
                Text(L("deck_config_action_show_answer")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showAnswer)
                Text(L("deck_config_action_show_reminder")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showReminder)
            }
            .pickerStyle(.menu)
            .tint(.blue)
            Picker(L("deck_config_after_answer"), selection: $answerAction) {
                Text(L("deck_config_action_bury")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.buryCard)
                Text(L("deck_config_action_again")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerAgain)
                Text(L("deck_config_action_hard")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerHard)
                Text(L("deck_config_action_good")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerGood)
                Text(L("deck_config_action_show_reminder")).foregroundStyle(.blue).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.showReminder)
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var advancedSection: some View {
        DisclosureGroup(L("deck_config_section_advanced"), isExpanded: $advancedExpanded) {
            Toggle(L("deck_config_disable_autoplay"), isOn: $disableAutoplay)
            Toggle(L("deck_config_wait_audio"), isOn: $waitForAudio)
            Toggle(L("deck_config_skip_question_audio"), isOn: $skipQuestionWhenReplayingAnswer)
            LabeledContent(L("deck_config_max_interval")) {
                Stepper(L("deck_config_days_fmt", maximumReviewIntervalDays), value: $maximumReviewIntervalDays, in: 1...36500)
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_interval_mult"))
                    Spacer()
                    Text("\(Int(intervalMultiplierPercent))%")
                        .foregroundStyle(.blue)
                }
                Slider(value: $intervalMultiplierPercent, in: 50...200, step: 1)
                    .tint(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_hard_mult"))
                    Spacer()
                    Text("\(Int(hardMultiplierPercent))%")
                        .foregroundStyle(.blue)
                }
                Slider(value: $hardMultiplierPercent, in: 80...200, step: 1)
                    .tint(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_easy_mult"))
                    Spacer()
                    Text("\(Int(easyMultiplierPercent))%")
                        .foregroundStyle(.blue)
                }
                Slider(value: $easyMultiplierPercent, in: 100...300, step: 1)
                    .tint(.blue)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }

    private var easyDaysSection: some View {
        DisclosureGroup(L("deck_config_section_easy_days"), isExpanded: $easyDaysExpanded) {
            ForEach(0..<7, id: \.self) { idx in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(weekdayName(idx))
                        Spacer()
                        Text("\(Int(easyDayPercentages[idx]))%")
                            .foregroundStyle(.blue)
                    }
                    Slider(value: Binding(
                        get: { easyDayPercentages[idx] },
                        set: { easyDayPercentages[idx] = $0 }
                    ), in: 50...150, step: 1)
                    .tint(.blue)
                }
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.vertical, 10)
    }
    
    private func loadConfig() async {
        do {
            Swift.print("[DeckConfigView] Loading config for deckId=\(deckId)")
            let initialContext = try? deckClient.fetchDeckConfigContext(deckId)
            if initialContext == nil {
                Swift.print("[DeckConfigView] Initial deck config context fetch failed for deckId=\(deckId); retrying after config load")
            }
            let loadedConfig = try deckClient.getDeckConfig(deckId)
            let retryContext = initialContext ?? (try? deckClient.fetchDeckConfigContext(deckId))
            if retryContext == nil {
                Swift.print("[DeckConfigView] Using fallback deck config context for deckId=\(deckId), configId=\(loadedConfig.id), configName=\(loadedConfig.name)")
            }
            let effectiveContext = retryContext ?? fallbackDeckConfigContext(from: loadedConfig)
            let effectiveConfig: Anki_DeckConfig_DeckConfig
            if effectiveContext.currentDeck.configID != 0,
               let matched = effectiveContext.allConfig.first(where: { $0.config.id == effectiveContext.currentDeck.configID })?.config {
                effectiveConfig = matched
            } else {
                effectiveConfig = loadedConfig
            }
            Swift.print("[DeckConfigView] Loaded config: \(effectiveConfig.name), id=\(effectiveConfig.id)")
            await MainActor.run {
                deckConfigContext = effectiveContext
                config = effectiveConfig
                selectedPresetID = effectiveConfig.id
                presetUseCount = effectiveContext.allConfig.first(where: { $0.config.id == effectiveConfig.id })?.useCount ?? 0
                let cfg = effectiveConfig.config
                configName = effectiveConfig.name
                
                // Extract values from config
                newCardsPerDay = Int32(cfg.newPerDay)
                reviewsPerDay = Int32(cfg.reviewsPerDay)
                learningStepsText = formatSteps(cfg.learnSteps)
                relearningStepsText = formatSteps(cfg.relearnSteps)
                graduatingGoodDays = Int32(cfg.graduatingIntervalGood)
                graduatingEasyDays = Int32(cfg.graduatingIntervalEasy)
                leechThreshold = Int32(cfg.leechThreshold)

                newCardInsertOrder = cfg.newCardInsertOrder
                newMix = cfg.newMix
                reviewOrder = cfg.reviewOrder
                interdayLearningMix = cfg.interdayLearningMix
                leechAction = cfg.leechAction

                buryNew = cfg.buryNew
                buryReviews = cfg.buryReviews
                buryInterdayLearning = cfg.buryInterdayLearning

                showTimer = cfg.showTimer
                capAnswerTimeToSecs = Int32(cfg.capAnswerTimeToSecs)
                stopTimerOnAnswer = cfg.stopTimerOnAnswer
                disableAutoplay = cfg.disableAutoplay
                waitForAudio = cfg.waitForAudio
                skipQuestionWhenReplayingAnswer = cfg.skipQuestionWhenReplayingAnswer

                secondsToShowQuestion = Double(cfg.secondsToShowQuestion)
                secondsToShowAnswer = Double(cfg.secondsToShowAnswer)
                questionAction = cfg.questionAction
                answerAction = cfg.answerAction

                maximumReviewIntervalDays = Int32(cfg.maximumReviewInterval)
                intervalMultiplierPercent = Double(cfg.intervalMultiplier * 100)
                hardMultiplierPercent = Double(cfg.hardMultiplier * 100)
                easyMultiplierPercent = Double(cfg.easyMultiplier * 100)
                if cfg.easyDaysPercentages.count == 7 {
                    easyDayPercentages = cfg.easyDaysPercentages.map { Double($0) * 100 }
                } else {
                    easyDayPercentages = Array(repeating: 100, count: 7)
                }
                
                // FSRS settings: global toggle should come from DeckConfigsForUpdate.fsrs,
                // not from whether params arrays are empty.
                fsrsEnabled = effectiveContext.fsrs
                if effectiveContext.hasCurrentDeck,
                   effectiveContext.currentDeck.hasLimits,
                   effectiveContext.currentDeck.limits.hasDesiredRetention {
                    desiredRetentionPercent = Double(effectiveContext.currentDeck.limits.desiredRetention * 100)
                } else {
                    desiredRetentionPercent = Double(cfg.desiredRetention * 100)
                }
                if !cfg.fsrsParams6.isEmpty {
                    fsrsWeights = cfg.fsrsParams6.map { String($0) }.joined(separator: " ")
                } else if !cfg.fsrsParams5.isEmpty {
                    fsrsWeights = cfg.fsrsParams5.map { String($0) }.joined(separator: " ")
                } else {
                    fsrsWeights = cfg.fsrsParams4.map { String($0) }.joined(separator: " ")
                }
                fsrsSimulationSearch = cfg.paramSearch
                retentionWorkload = []
                
                isLoading = false
                Swift.print("[DeckConfigView] Configuration loaded successfully")
            }
        } catch {
            Swift.print("[DeckConfigView] Failed to load config: \(error)")
            await MainActor.run {
                errorMessage = L("deck_config_error_load", error.localizedDescription)
                showError = true
                isLoading = false
            }
        }
    }

    private func fallbackDeckConfigContext(from loadedConfig: Anki_DeckConfig_DeckConfig) -> Anki_DeckConfig_DeckConfigsForUpdate {
        var context = Anki_DeckConfig_DeckConfigsForUpdate()
        var configWithExtra = Anki_DeckConfig_DeckConfigsForUpdate.ConfigWithExtra()
        configWithExtra.config = loadedConfig
        configWithExtra.useCount = 0

        context.allConfig = [configWithExtra]
        context.defaults = loadedConfig

        var currentDeck = Anki_DeckConfig_DeckConfigsForUpdate.CurrentDeck()
        currentDeck.name = loadedConfig.name
        currentDeck.configID = loadedConfig.id
        context.currentDeck = currentDeck

        let cfg = loadedConfig.config
        context.fsrs = !cfg.fsrsParams6.isEmpty || !cfg.fsrsParams5.isEmpty || !cfg.fsrsParams4.isEmpty
        return context
    }

    private func createPresetFromDefaults() async {
        guard let defaults = deckConfigContext?.defaults else { return }

        isManagingPreset = true
        defer { isManagingPreset = false }

        do {
            try deckClient.createDeckPreset(
                deckId,
                defaults,
                uniquePresetName(L("deck_config_preset_new_default_name")),
                applyToChildren
            )
            await loadConfig()
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func duplicateSelectedPreset() async {
        guard let editedConfig = makeEditedConfigDraft() else { return }

        isManagingPreset = true
        defer { isManagingPreset = false }

        do {
            try deckClient.createDeckPreset(
                deckId,
                editedConfig,
                uniquePresetName(L("deck_config_preset_duplicate_name", editedConfig.name)),
                applyToChildren
            )
            await loadConfig()
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func deleteSelectedPreset() async {
        guard let currentConfig = config,
              let fallbackConfig = deleteFallbackPreset else { return }

        isManagingPreset = true
        defer { isManagingPreset = false }

        do {
            try deckClient.deleteDeckPreset(
                deckId,
                currentConfig.id,
                fallbackConfig,
                applyToChildren
            )
            await loadConfig()
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func selectPreset(from previousID: Int64, to newID: Int64) async {
        guard let selectedConfig = presetOptions.first(where: { $0.config.id == newID })?.config else {
            selectedPresetID = previousID
            return
        }

        isManagingPreset = true
        defer { isManagingPreset = false }

        do {
            try deckClient.selectDeckPreset(deckId, selectedConfig, applyToChildren)
            await loadConfig()
        } catch {
            selectedPresetID = previousID
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func renameSelectedPreset() async {
        guard var updatedConfig = makeEditedConfigDraft() else { return }

        let trimmedName = renamePresetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = L("deck_config_error_save", L("deck_config_name_placeholder"))
            showError = true
            return
        }

        updatedConfig.name = trimmedName
        configName = trimmedName
        await persistConfig(updatedConfig, dismissOnSuccess: false)
    }

    private func optimizeFsrsPresets() async {
        guard let config else { return }

        isOptimizingFsrs = true
        defer { isOptimizingFsrs = false }

        do {
            try deckClient.optimizeFsrsPresets(deckId, config)
            await loadConfig()
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func runFsrsSimulation() async {
        guard fsrsEnabled else { return }

        isSimulatingFsrs = true
        defer { isSimulatingFsrs = false }

        do {
            let weights = parseFloatArray(fsrsWeights)
            let effectiveWeights: [Float]
            if !weights.isEmpty {
                effectiveWeights = weights
            } else if let loaded = config {
                let cfg = loaded.config
                if !cfg.fsrsParams6.isEmpty {
                    effectiveWeights = cfg.fsrsParams6
                } else if !cfg.fsrsParams5.isEmpty {
                    effectiveWeights = cfg.fsrsParams5
                } else if !cfg.fsrsParams4.isEmpty {
                    effectiveWeights = cfg.fsrsParams4
                } else {
                    effectiveWeights = []
                }
            } else {
                effectiveWeights = []
            }

            guard !effectiveWeights.isEmpty else {
                retentionWorkload = []
                return
            }

            let workload = try deckClient.getRetentionWorkload(
                effectiveWeights,
                fsrsSimulationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            retentionWorkload = workload
                .map { (retention: $0.key, cost: $0.value) }
                .sorted { $0.retention < $1.retention }
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }
    
    private func saveConfig(applyToChildren: Bool = false) {
        guard let config = makeEditedConfigDraft() else { return }
        Task { await persistConfig(config, applyToChildren: applyToChildren, dismissOnSuccess: true) }
    }

    private func makeEditedConfigDraft() -> Anki_DeckConfig_DeckConfig? {
        guard var config else { return nil }

        var cfg = config.config
        config.name = configName.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.disableAutoplay = disableAutoplay
        cfg.waitForAudio = waitForAudio
        cfg.skipQuestionWhenReplayingAnswer = skipQuestionWhenReplayingAnswer
        cfg.newPerDay = UInt32(max(0, newCardsPerDay))
        cfg.reviewsPerDay = UInt32(max(0, reviewsPerDay))
        cfg.learnSteps = parseSteps(learningStepsText)
        cfg.relearnSteps = parseSteps(relearningStepsText)
        cfg.graduatingIntervalGood = UInt32(max(0, graduatingGoodDays))
        cfg.graduatingIntervalEasy = UInt32(max(0, graduatingEasyDays))
        cfg.leechThreshold = UInt32(max(1, leechThreshold))

        cfg.newCardInsertOrder = newCardInsertOrder
        cfg.newMix = newMix
        cfg.reviewOrder = reviewOrder
        cfg.interdayLearningMix = interdayLearningMix
        cfg.leechAction = leechAction

        cfg.buryNew = buryNew
        cfg.buryReviews = buryReviews
        cfg.buryInterdayLearning = buryInterdayLearning

        cfg.showTimer = showTimer
        cfg.capAnswerTimeToSecs = UInt32(max(5, capAnswerTimeToSecs))
        cfg.stopTimerOnAnswer = stopTimerOnAnswer

        cfg.secondsToShowQuestion = Float(max(0, secondsToShowQuestion))
        cfg.secondsToShowAnswer = Float(max(0, secondsToShowAnswer))
        cfg.questionAction = questionAction
        cfg.answerAction = answerAction

        cfg.maximumReviewInterval = UInt32(max(1, maximumReviewIntervalDays))
        cfg.intervalMultiplier = Float(intervalMultiplierPercent / 100)
        cfg.hardMultiplier = Float(hardMultiplierPercent / 100)
        cfg.easyMultiplier = Float(easyMultiplierPercent / 100)
        cfg.easyDaysPercentages = easyDayPercentages.map { Float($0 / 100) }

        cfg.desiredRetention = Float(desiredRetentionPercent / 100)

        if fsrsEnabled {
            let weights = parseFloatArray(fsrsWeights)
            if !weights.isEmpty {
                cfg.fsrsParams6 = weights
                cfg.fsrsParams5 = []
                cfg.fsrsParams4 = []
            } else if cfg.fsrsParams6.isEmpty && cfg.fsrsParams5.isEmpty && cfg.fsrsParams4.isEmpty {
                let defaults = deckConfigContext?.defaults.config
                if let defaults, !defaults.fsrsParams6.isEmpty {
                    cfg.fsrsParams6 = defaults.fsrsParams6
                }
            }
        } else {
            cfg.fsrsParams6 = []
            cfg.fsrsParams5 = []
            cfg.fsrsParams4 = []
        }

        config.config = cfg
        return config
    }

    private func persistConfig(_ updatedConfig: Anki_DeckConfig_DeckConfig, applyToChildren: Bool = false, dismissOnSuccess: Bool) async {
        isSaving = true

        do {
            try deckClient.updateDeckConfig(deckId, updatedConfig, applyToChildren, fsrsEnabled)
            if dismissOnSuccess {
                onDismiss()
            } else {
                await loadConfig()
                isSaving = false
            }
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
            isSaving = false
        }
    }

    private func uniquePresetName(_ base: String) -> String {
        let normalizedNames = Set(presetOptions.map { $0.config.name.lowercased() })
        if !normalizedNames.contains(base.lowercased()) {
            return base
        }

        var index = 2
        while normalizedNames.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func parseSteps(_ text: String) -> [Float] {
        text
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .compactMap { token -> Float? in
                let t = String(token).lowercased()
                if t.hasSuffix("m"), let v = Float(t.dropLast()) { return v }
                if t.hasSuffix("h"), let v = Float(t.dropLast()) { return v * 60 }
                if t.hasSuffix("d"), let v = Float(t.dropLast()) { return v * 1440 }
                return Float(t)
            }
    }

    private func formatSteps(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "" }
        return values.map { "\(Int($0))m" }.joined(separator: " ")
    }

    private func parseFloatArray(_ text: String) -> [Float] {
        text
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .compactMap { Float($0) }
    }

    private func weekdayName(_ idx: Int) -> String {
        let keys = ["weekday_mon", "weekday_tue", "weekday_wed", "weekday_thu", "weekday_fri", "weekday_sat", "weekday_sun"]
        if idx >= 0 && idx < keys.count { return L(keys[idx]) }
        return L("weekday_other", idx + 1)
    }
}

#Preview {
    DeckConfigView(
        deckId: 1,
        onDismiss: { print("Dismissed") }
    )
    .preferredColorScheme(.dark)
}
