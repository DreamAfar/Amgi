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
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section("系统设置") {
                            TextField("配置名称", text: $configName)
                            Toggle("禁用自动播放音频", isOn: $disableAutoplay)
                            Toggle("等待音频播放完成", isOn: $waitForAudio)
                            Toggle("重放答案时跳过问题音频", isOn: $skipQuestionWhenReplayingAnswer)
                            Toggle("应用到子牌组", isOn: $applyToChildren)
                        }

                        Section("每日上限") {
                            Stepper(
                                "New cards per day: \(newCardsPerDay)",
                                value: $newCardsPerDay,
                                in: 0...1000
                            )
                            
                            Stepper(
                                "Reviews per day: \(reviewsPerDay)",
                                value: $reviewsPerDay,
                                in: 0...10000
                            )
                        }
                        
                        Section("新卡片") {
                            TextField("Steps (space-separated)", text: $learningStepsText)
                                .font(.monospaced(.body)())

                            Stepper("Good 间隔（天）: \(graduatingGoodDays)", value: $graduatingGoodDays, in: 0...365)
                            Stepper("Easy 间隔（天）: \(graduatingEasyDays)", value: $graduatingEasyDays, in: 0...365)

                            Picker("新卡插入顺序", selection: $newCardInsertOrder) {
                                Text("按到期").tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.due)
                                Text("随机").tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.random)
                            }

                            Picker("新卡与复习混合", selection: $newMix) {
                                Text("与复习混合").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                                Text("复习后").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                                Text("复习前").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
                            }
                        }
                        
                        Section("遗忘") {
                            TextField("Steps (space-separated)", text: $relearningStepsText)
                                .font(.monospaced(.body)())

                            Stepper("记忆阈值（leech）: \(leechThreshold)", value: $leechThreshold, in: 1...50)

                            Picker("记忆阈值后动作", selection: $leechAction) {
                                Text("暂停卡片").tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.suspend)
                                Text("仅打标签").tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.tagOnly)
                            }
                        }
                        
                        Section("展示顺序") {
                            Picker("复习卡片顺序", selection: $reviewOrder) {
                                Text("按天").tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.day)
                                Text("按间隔升序").tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsAscending)
                                Text("按间隔降序").tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsDescending)
                                Text("随机").tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.random)
                            }

                            Picker("跨天学习卡片", selection: $interdayLearningMix) {
                                Text("与复习混合").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                                Text("复习后").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                                Text("复习前").tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
                            }
                        }

                        Section("FSRS") {
                            Toggle("Enable FSRS", isOn: $fsrsEnabled)

                            HStack {
                                Text("目标记忆保持率")
                                Spacer()
                                Text("\(Int(desiredRetentionPercent))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $desiredRetentionPercent, in: 70...97, step: 1)
                            
                            if fsrsEnabled {
                                TextField("FSRS Weights", text: $fsrsWeights)
                                    .font(.monospaced(.caption)())
                                    .lineLimit(3)
                            }
                        }

                        Section("搁置") {
                            Toggle("新卡片与当天复习卡片", isOn: $buryNew)
                            Toggle("复习卡与当天复习卡片", isOn: $buryReviews)
                            Toggle("跨天学习与当天复习卡片", isOn: $buryInterdayLearning)
                        }

                        Section("计时器") {
                            Toggle("显示计时器", isOn: $showTimer)
                            Stepper("答题时间记录上限（秒）: \(capAnswerTimeToSecs)", value: $capAnswerTimeToSecs, in: 5...600)
                            Toggle("回答后停止计时", isOn: $stopTimerOnAnswer)
                        }

                        Section("自动前进") {
                            HStack {
                                Text("问题显示秒数")
                                Spacer()
                                Text(String(format: "%.1f", secondsToShowQuestion))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $secondsToShowQuestion, in: 0...60, step: 0.5)

                            HStack {
                                Text("答案显示秒数")
                                Spacer()
                                Text(String(format: "%.1f", secondsToShowAnswer))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $secondsToShowAnswer, in: 0...60, step: 0.5)

                            Picker("显示问题后", selection: $questionAction) {
                                Text("显示答案").tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showAnswer)
                                Text("显示提醒").tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showReminder)
                            }

                            Picker("显示答案后", selection: $answerAction) {
                                Text("搁置卡片").tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.buryCard)
                                Text("选择 Again").tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerAgain)
                                Text("选择 Hard").tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerHard)
                                Text("选择 Good").tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerGood)
                                Text("显示提醒").tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.showReminder)
                            }
                        }

                        Section("高级") {
                            Stepper("最大复习间隔（天）: \(maximumReviewIntervalDays)", value: $maximumReviewIntervalDays, in: 1...36500)

                            HStack {
                                Text("间隔倍率")
                                Spacer()
                                Text("\(Int(intervalMultiplierPercent))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $intervalMultiplierPercent, in: 50...200, step: 1)

                            HStack {
                                Text("Hard 倍率")
                                Spacer()
                                Text("\(Int(hardMultiplierPercent))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $hardMultiplierPercent, in: 80...200, step: 1)

                            HStack {
                                Text("Easy 倍率")
                                Spacer()
                                Text("\(Int(easyMultiplierPercent))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $easyMultiplierPercent, in: 100...300, step: 1)
                        }

                        Section("轻松日") {
                            ForEach(0..<7, id: \.self) { idx in
                                VStack(alignment: .leading, spacing: 6) {
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
                        
                        Section {
                            Button(action: saveConfig) {
                                if isSaving {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Save Configuration")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .disabled(isSaving)
                        }
                    }
                }
            }
            .navigationTitle("Deck Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveConfig()
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Configuration Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .task {
                await loadConfig()
            }
        }
    }
    
    private func loadConfig() async {
        do {
            let loadedConfig = try deckClient.getDeckConfig(deckId)
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
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load deck configuration: \(error.localizedDescription)"
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
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
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
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        if idx >= 0 && idx < names.count { return names[idx] }
        return "周\(idx + 1)"
    }
}

#Preview {
    DeckConfigView(
        deckId: 1,
        onDismiss: { print("Dismissed") }
    )
    .preferredColorScheme(.dark)
}
