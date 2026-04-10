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
    @State private var disableAutoplay = false
    @State private var waitForAudio = false
    @State private var skipQuestionWhenReplayingAnswer = false
    @State private var easyDayPercentages: [Double] = Array(repeating: 100, count: 7)
    @State private var applyToChildren = false

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
                        Button(L("common_save")) {
                            saveConfig()
                        }
                        .bold()
                    }
                }
            }
            .alert(L("deck_config_save_failed"), isPresented: $showError) {
                Button(L("common_ok")) { }
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .task {
                await loadConfig()
            }
        }
    }

    // MARK: - Extracted Sections

    private var basicSection: some View {
        Section(L("deck_config_section_basic")) {
            LabeledContent(L("deck_config_name")) {
                TextField(L("deck_config_name_placeholder"), text: $configName)
                    .multilineTextAlignment(.trailing)
            }
            Toggle(L("deck_config_apply_children"), isOn: $applyToChildren)
        }
    }

    private var dailyLimitsSection: some View {
        Section(L("deck_config_section_daily")) {
            LabeledContent(L("deck_config_daily_new")) {
                Stepper("\(newCardsPerDay)", value: $newCardsPerDay, in: 0...1000)
            }
            LabeledContent(L("deck_config_daily_review")) {
                Stepper("\(reviewsPerDay)", value: $reviewsPerDay, in: 0...10000)
            }
        }
    }

    private var newCardsSection: some View {
        Section(L("deck_config_section_new")) {
            LabeledContent(L("deck_config_learn_steps")) {
                TextField(L("deck_config_learn_steps_hint"), text: $learningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
            }
            LabeledContent(L("deck_config_good_interval")) {
                Stepper(L("deck_config_days_fmt", graduatingGoodDays), value: $graduatingGoodDays, in: 0...365)
            }
            LabeledContent(L("deck_config_easy_interval")) {
                Stepper(L("deck_config_days_fmt", graduatingEasyDays), value: $graduatingEasyDays, in: 0...365)
            }
            Picker(L("deck_config_insert_order"), selection: $newCardInsertOrder) {
                Text(L("deck_config_order_due")).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.due)
                Text(L("deck_config_order_random")).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.random)
            }
            Picker(L("deck_config_new_mix"), selection: $newMix) {
                Text(L("deck_config_mix_with_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                Text(L("deck_config_mix_after_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                Text(L("deck_config_mix_before_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
            }
        }
    }

    private var lapsesSection: some View {
        Section(L("deck_config_section_lapses")) {
            LabeledContent(L("deck_config_relearn_steps")) {
                TextField(L("deck_config_relearn_steps_hint"), text: $relearningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
            }
            LabeledContent(L("deck_config_leech_threshold")) {
                Stepper(L("deck_config_times_fmt", leechThreshold), value: $leechThreshold, in: 1...50)
            }
            Picker(L("deck_config_leech_action"), selection: $leechAction) {
                Text(L("deck_config_leech_suspend")).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.suspend)
                Text(L("deck_config_leech_tag_only")).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.tagOnly)
            }
        }
    }

    private var orderSection: some View {
        DisclosureGroup(L("deck_config_section_order"), isExpanded: $orderExpanded) {
            Picker(L("deck_config_review_order"), selection: $reviewOrder) {
                Text(L("deck_config_review_order_day")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.day)
                Text(L("deck_config_review_order_asc")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsAscending)
                Text(L("deck_config_review_order_desc")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsDescending)
                Text(L("deck_config_order_random")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.random)
            }
            Picker(L("deck_config_interday_mix"), selection: $interdayLearningMix) {
                Text(L("deck_config_mix_with_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                Text(L("deck_config_mix_after_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                Text(L("deck_config_mix_before_reviews")).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
            }
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
                        .foregroundStyle(.secondary)
                }
                Slider(value: $desiredRetentionPercent, in: 70...97, step: 1)
            }
            if fsrsEnabled {
                LabeledContent(L("deck_config_fsrs_weights")) {
                    TextField(L("deck_config_fsrs_weights_hint"), text: $fsrsWeights)
                        .multilineTextAlignment(.trailing)
                        .font(.monospaced(.caption)())
                }
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
                        .foregroundStyle(.secondary)
                }
                Slider(value: $secondsToShowQuestion, in: 0...60, step: 0.5)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_answer_secs"))
                    Spacer()
                    Text(String(format: "%.1f s", secondsToShowAnswer))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $secondsToShowAnswer, in: 0...60, step: 0.5)
            }
            Picker(L("deck_config_after_question"), selection: $questionAction) {
                Text(L("deck_config_action_show_answer")).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showAnswer)
                Text(L("deck_config_action_show_reminder")).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showReminder)
            }
            Picker(L("deck_config_after_answer"), selection: $answerAction) {
                Text(L("deck_config_action_bury")).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.buryCard)
                Text(L("deck_config_action_again")).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerAgain)
                Text(L("deck_config_action_hard")).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerHard)
                Text(L("deck_config_action_good")).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerGood)
                Text(L("deck_config_action_show_reminder")).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.showReminder)
            }
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
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_interval_mult"))
                    Spacer()
                    Text("\(Int(intervalMultiplierPercent))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $intervalMultiplierPercent, in: 50...200, step: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_hard_mult"))
                    Spacer()
                    Text("\(Int(hardMultiplierPercent))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $hardMultiplierPercent, in: 80...200, step: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_easy_mult"))
                    Spacer()
                    Text("\(Int(easyMultiplierPercent))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $easyMultiplierPercent, in: 100...300, step: 1)
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
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { easyDayPercentages[idx] },
                        set: { easyDayPercentages[idx] = $0 }
                    ), in: 50...150, step: 1)
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
            let loadedConfig = try deckClient.getDeckConfig(deckId)
            Swift.print("[DeckConfigView] Loaded config: \(loadedConfig.name), id=\(loadedConfig.id)")
            await MainActor.run {
                config = loadedConfig
                let cfg = loadedConfig.config
                configName = loadedConfig.name
                
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
                
                // FSRS settings
                fsrsEnabled = !cfg.fsrsParams4.isEmpty || !cfg.fsrsParams5.isEmpty || !cfg.fsrsParams6.isEmpty
                desiredRetentionPercent = Double(cfg.desiredRetention * 100)
                if !cfg.fsrsParams6.isEmpty {
                    fsrsWeights = cfg.fsrsParams6.map { String($0) }.joined(separator: " ")
                } else if !cfg.fsrsParams5.isEmpty {
                    fsrsWeights = cfg.fsrsParams5.map { String($0) }.joined(separator: " ")
                } else {
                    fsrsWeights = cfg.fsrsParams4.map { String($0) }.joined(separator: " ")
                }
                
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
    
    private func saveConfig() {
        guard var config else { return }
        
        isSaving = true
        
        // Update config with new values
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
            cfg.fsrsParams6 = weights
            cfg.fsrsParams5 = []
            cfg.fsrsParams4 = []
        } else {
            cfg.fsrsParams6 = []
            cfg.fsrsParams5 = []
            cfg.fsrsParams4 = []
        }

        config.config = cfg
        
        do {
            try deckClient.updateDeckConfig(deckId, config, applyToChildren)
            onDismiss()
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
            isSaving = false
        }
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
