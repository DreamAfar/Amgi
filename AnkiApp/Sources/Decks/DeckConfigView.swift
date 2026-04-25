import SwiftUI
#if os(iOS)
import AudioToolbox
import UIKit
#endif
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
    @State private var fsrsHealthCheck = false
    @State private var showFsrsSimulator = false
    @State private var fsrsSimulatorMode: FsrsSimulatorMode = .review
    @State private var fsrsSimulatorDays = 365
    @State private var fsrsSimulatorAdditionalCards = 0
    @State private var fsrsSimulatorRetentionPercent: Double = 90
    @State private var fsrsSimulatorNewLimit = 20
    @State private var fsrsSimulatorReviewLimit = 9999
    @State private var fsrsSimulatorMaxInterval = 36500
    @State private var fsrsSimulatorSearch = ""
    @State private var fsrsSimulatorIgnoreNewLimit = false
    @State private var fsrsSimulatorReviewOrder: Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder = .day
    @State private var fsrsSimulatorSuspendLeeches = false
    @State private var fsrsSimulatorResult: FsrsSimulatorResult?

    @State private var newCardInsertOrder: Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder = .due
    @State private var newMix: Anki_DeckConfig_DeckConfig.Config.ReviewMix = .mixWithReviews
    @State private var newCardGatherPriority: Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority = .deck
    @State private var newCardSortOrder: Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder = .template
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
    @State private var minimumLapseIntervalDays: Int32 = 1
    @State private var newPerDayMinimum: Int32 = 0
    @State private var intervalMultiplierPercent: Double = 100
    @State private var initialEasePercent: Double = 250
    @State private var hardMultiplierPercent: Double = 120
    @State private var easyMultiplierPercent: Double = 130
    @State private var lapseMultiplierPercent: Double = 0
    @State private var historicalRetentionPercent: Double = 90
    @State private var configName: String = ""
    @State private var selectedPresetID: Int64 = 0
    @State private var presetUseCount: UInt32 = 0
    @State private var disableAutoplay = false
    @State private var waitForAudio = false
    @State private var skipQuestionWhenReplayingAnswer = false
    @State private var newCardsIgnoreReviewLimit = false
    @State private var applyAllParentLimits = false
    @State private var easyDayPercentages: [Double] = Array(repeating: 100, count: 7)
    @State private var applyToChildren = false
    @State private var isManagingPreset = false
    @State private var showDeletePresetConfirmation = false
    @State private var showRenamePresetPrompt = false
    @State private var renamePresetDraft = ""

    private enum FsrsSimulatorMode: String, CaseIterable, Identifiable {
        case review
        case workload

        var id: String { rawValue }
    }

    private struct FsrsSimulatorResult {
        var summary: [(String, String)]
        var rows: [(String, String, String)]
    }

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
                    .scrollContentBackground(.hidden)
                    .background(Color.amgiBackground)
                }
            }
            .background(Color.amgiBackground)
            .navigationTitle(L("deck_config_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { onDismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
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
                            Text(L("common_save"))
                                .bold()
                                .foregroundStyle(Color.amgiAccent)
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
            .sheet(isPresented: $showFsrsSimulator) {
                fsrsSimulatorSheet
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

    private var selectedPresetLabel: String {
        presetOptions.first(where: { $0.config.id == selectedPresetID })?.config.name ?? configName
    }

    private var newCardInsertOrderLabel: String {
        switch newCardInsertOrder {
        case .due:
            return L("deck_config_order_due")
        case .random:
            return L("deck_config_order_random")
        default:
            return L("deck_config_order_due")
        }
    }

    private var newMixLabel: String {
        reviewMixLabel(newMix)
    }

    private var newCardGatherPriorityLabel: String {
        switch newCardGatherPriority {
        case .deck:
            return L("deck_config_new_gather_priority_deck")
        case .deckThenRandomNotes:
            return L("deck_config_new_gather_priority_deck_then_random_notes")
        case .lowestPosition:
            return L("deck_config_new_gather_priority_position_lowest_first")
        case .highestPosition:
            return L("deck_config_new_gather_priority_position_highest_first")
        case .randomNotes:
            return L("deck_config_new_gather_priority_random_notes")
        case .randomCards:
            return L("deck_config_new_gather_priority_random_cards")
        default:
            return L("deck_config_new_gather_priority_deck")
        }
    }

    private var newCardSortOrderLabel: String {
        switch newCardSortOrder {
        case .template:
            return L("deck_config_sort_order_template_then_gather")
        case .noSort:
            return L("deck_config_sort_order_gather")
        case .templateThenRandom:
            return L("deck_config_sort_order_card_template_then_random")
        case .randomNoteThenTemplate:
            return L("deck_config_sort_order_random_note_then_template")
        case .randomCard:
            return L("deck_config_sort_order_random")
        default:
            return L("deck_config_sort_order_template_then_gather")
        }
    }

    private var leechActionLabel: String {
        switch leechAction {
        case .suspend:
            return L("deck_config_leech_suspend")
        case .tagOnly:
            return L("deck_config_leech_tag_only")
        default:
            return L("deck_config_leech_suspend")
        }
    }

    private var reviewOrderLabel: String {
        reviewOrderText(reviewOrder)
    }

    private func reviewOrderText(_ value: Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder) -> String {
        switch value {
        case .day:
            return L("deck_config_review_order_day")
        case .dayThenDeck:
            return L("deck_config_review_order_day_then_deck")
        case .deckThenDay:
            return L("deck_config_review_order_deck_then_day")
        case .intervalsAscending:
            return L("deck_config_review_order_asc")
        case .intervalsDescending:
            return L("deck_config_review_order_desc")
        case .easeAscending:
            return L("deck_config_review_order_ease_asc")
        case .easeDescending:
            return L("deck_config_review_order_ease_desc")
        case .retrievabilityAscending:
            return L("deck_config_review_order_retrievability_asc")
        case .retrievabilityDescending:
            return L("deck_config_review_order_retrievability_desc")
        case .random:
            return L("deck_config_order_random")
        case .added:
            return L("deck_config_review_order_added")
        case .reverseAdded:
            return L("deck_config_review_order_reverse_added")
        default:
            return L("deck_config_review_order_day")
        }
    }

    private var interdayLearningMixLabel: String {
        reviewMixLabel(interdayLearningMix)
    }

    private var questionActionLabel: String {
        switch questionAction {
        case .showAnswer:
            return L("deck_config_action_show_answer")
        case .showReminder:
            return L("deck_config_action_show_reminder")
        default:
            return L("deck_config_action_show_answer")
        }
    }

    private var answerActionLabel: String {
        switch answerAction {
        case .buryCard:
            return L("deck_config_action_bury")
        case .answerAgain:
            return L("deck_config_action_again")
        case .answerHard:
            return L("deck_config_action_hard")
        case .answerGood:
            return L("deck_config_action_good")
        case .showReminder:
            return L("deck_config_action_show_reminder")
        default:
            return L("deck_config_action_bury")
        }
    }

    private func reviewMixLabel(_ value: Anki_DeckConfig_DeckConfig.Config.ReviewMix) -> String {
        switch value {
        case .mixWithReviews:
            return L("deck_config_mix_with_reviews")
        case .afterReviews:
            return L("deck_config_mix_after_reviews")
        case .beforeReviews:
            return L("deck_config_mix_before_reviews")
        default:
            return L("deck_config_mix_with_reviews")
        }
    }

    private func optionCapsule(_ title: String) -> some View {
        HStack(spacing: AmgiSpacing.xs) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(AmgiFont.micro.font)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .amgiCapsuleControl()
    }

    private func editableNumberStepper(
        _ value: Binding<Int32>,
        in range: ClosedRange<Int32>,
        unitFormatKey: String? = nil
    ) -> some View {
        let boundedValue = Binding<Int32>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )

        return Stepper(value: boundedValue, in: range) {
            HStack(spacing: 4) {
                TextField("", value: boundedValue, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
                    .frame(minWidth: 52, idealWidth: 72, maxWidth: 96)

                if let unitFormatKey {
                    Text(unitLabel(from: unitFormatKey))
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
        .foregroundStyle(Color.amgiAccent)
    }

    private func unitLabel(from formatKey: String) -> String {
        L(formatKey, 1)
            .replacingOccurrences(of: "1", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func percentWheelPicker(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Int>
    ) -> some View {
        let intValue = Binding<Int>(
            get: { Int(value.wrappedValue.rounded()) },
            set: { value.wrappedValue = Double(min(max($0, range.lowerBound), range.upperBound)) }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(intValue.wrappedValue)%")
                    .foregroundStyle(Color.amgiAccent)
                    .monospacedDigit()
            }

            Picker(title, selection: intValue) {
                ForEach(Array(range), id: \.self) { percent in
                    Text("\(percent)%")
                        .tag(percent)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 96)
            .clipped()
            .onChange(of: intValue.wrappedValue) { _, _ in
                wheelPickerFeedback()
            }
        }
    }

    private func wheelPickerFeedback() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    // MARK: - Extracted Sections

    private var basicSection: some View {
        Section(L("deck_config_section_basic")) {
            LabeledContent(L("deck_config_preset")) {
                Menu {
                    Picker(L("deck_config_preset"), selection: presetSelectionBinding) {
                        ForEach(presetOptions, id: \.config.id) { option in
                            Text(option.config.name)
                                .foregroundStyle(Color.amgiAccent)
                                .tag(option.config.id)
                        }
                    }
                } label: {
                    optionCapsule(selectedPresetLabel)
                }
                .disabled(isManagingPreset || presetOptions.isEmpty)
            }

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
                            .foregroundStyle(Color.amgiAccent)
                    }
                }
            }

            LabeledContent(L("deck_config_name")) {
                TextField(L("deck_config_name_placeholder"), text: $configName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(L("deck_config_preset_usage")) {
                Text(L("deck_config_preset_used_by", Int(presetUseCount)))
                    .foregroundStyle(Color.amgiAccent)
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var dailyLimitsSection: some View {
        Section(L("deck_config_section_daily")) {
            LabeledContent(L("deck_config_daily_new")) {
                editableNumberStepper($newCardsPerDay, in: 0...9999)
            }
            LabeledContent(L("deck_config_daily_review")) {
                editableNumberStepper($reviewsPerDay, in: 0...9999)
            }
            LabeledContent(L("deck_config_new_per_day_minimum")) {
                editableNumberStepper($newPerDayMinimum, in: 0...9999)
            }
            Toggle(L("deck_config_new_cards_ignore_review_limit"), isOn: $newCardsIgnoreReviewLimit)
            Toggle(L("deck_config_apply_all_parent_limits"), isOn: $applyAllParentLimits)
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var newCardsSection: some View {
        Section(L("deck_config_section_new")) {
            LabeledContent(L("deck_config_learn_steps")) {
                TextField(L("deck_config_learn_steps_hint"), text: $learningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
                    .foregroundStyle(Color.amgiAccent)
            }
            LabeledContent(L("deck_config_good_interval")) {
                editableNumberStepper($graduatingGoodDays, in: 0...365, unitFormatKey: "deck_config_days_fmt")
            }
            LabeledContent(L("deck_config_easy_interval")) {
                editableNumberStepper($graduatingEasyDays, in: 0...365, unitFormatKey: "deck_config_days_fmt")
            }
            LabeledContent(L("deck_config_insert_order")) {
                Menu {
                    Picker(L("deck_config_insert_order"), selection: $newCardInsertOrder) {
                        Text(L("deck_config_order_due")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.due)
                        Text(L("deck_config_order_random")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder.random)
                    }
                } label: {
                    optionCapsule(newCardInsertOrderLabel)
                }
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var lapsesSection: some View {
        Section(L("deck_config_section_lapses")) {
            LabeledContent(L("deck_config_relearn_steps")) {
                TextField(L("deck_config_relearn_steps_hint"), text: $relearningStepsText)
                    .multilineTextAlignment(.trailing)
                    .font(.monospaced(.body)())
                    .foregroundStyle(Color.amgiAccent)
            }
            LabeledContent(L("deck_config_leech_threshold")) {
                editableNumberStepper($leechThreshold, in: 1...9999, unitFormatKey: "deck_config_times_fmt")
            }
            LabeledContent(L("deck_config_leech_action")) {
                Menu {
                    Picker(L("deck_config_leech_action"), selection: $leechAction) {
                        Text(L("deck_config_leech_suspend")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.suspend)
                        Text(L("deck_config_leech_tag_only")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.tagOnly)
                    }
                } label: {
                    optionCapsule(leechActionLabel)
                }
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var orderSection: some View {
        Section(L("deck_config_section_order")) {
            LabeledContent(L("deck_config_new_gather_priority")) {
                Menu {
                    Picker(L("deck_config_new_gather_priority"), selection: $newCardGatherPriority) {
                        Text(L("deck_config_new_gather_priority_deck")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.deck)
                        Text(L("deck_config_new_gather_priority_deck_then_random_notes")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.deckThenRandomNotes)
                        Text(L("deck_config_new_gather_priority_position_lowest_first")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.lowestPosition)
                        Text(L("deck_config_new_gather_priority_position_highest_first")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.highestPosition)
                        Text(L("deck_config_new_gather_priority_random_notes")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.randomNotes)
                        Text(L("deck_config_new_gather_priority_random_cards")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority.randomCards)
                    }
                } label: {
                    optionCapsule(newCardGatherPriorityLabel)
                }
            }
            LabeledContent(L("deck_config_new_card_sort_order")) {
                Menu {
                    Picker(L("deck_config_new_card_sort_order"), selection: $newCardSortOrder) {
                        Text(L("deck_config_sort_order_template_then_gather")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder.template)
                        Text(L("deck_config_sort_order_gather")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder.noSort)
                        Text(L("deck_config_sort_order_card_template_then_random")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder.templateThenRandom)
                        Text(L("deck_config_sort_order_random_note_then_template")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder.randomNoteThenTemplate)
                        Text(L("deck_config_sort_order_random")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder.randomCard)
                    }
                } label: {
                    optionCapsule(newCardSortOrderLabel)
                }
            }
            LabeledContent(L("deck_config_new_mix")) {
                Menu {
                    Picker(L("deck_config_new_mix"), selection: $newMix) {
                        Text(L("deck_config_mix_with_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                        Text(L("deck_config_mix_after_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                        Text(L("deck_config_mix_before_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
                    }
                } label: {
                    optionCapsule(newMixLabel)
                }
            }
            LabeledContent(L("deck_config_review_order")) {
                Menu {
                    Picker(L("deck_config_review_order"), selection: $reviewOrder) {
                        Text(L("deck_config_review_order_day")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.day)
                        Text(L("deck_config_review_order_day_then_deck")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.dayThenDeck)
                        Text(L("deck_config_review_order_deck_then_day")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.deckThenDay)
                        Text(L("deck_config_review_order_asc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsAscending)
                        Text(L("deck_config_review_order_desc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsDescending)
                        Text(L("deck_config_review_order_ease_asc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.easeAscending)
                        Text(L("deck_config_review_order_ease_desc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.easeDescending)
                        Text(L("deck_config_review_order_retrievability_asc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.retrievabilityAscending)
                        Text(L("deck_config_review_order_retrievability_desc")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.retrievabilityDescending)
                        Text(L("deck_config_order_random")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.random)
                        Text(L("deck_config_review_order_added")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.added)
                        Text(L("deck_config_review_order_reverse_added")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.reverseAdded)
                    }
                } label: {
                    optionCapsule(reviewOrderLabel)
                }
            }
            LabeledContent(L("deck_config_interday_mix")) {
                Menu {
                    Picker(L("deck_config_interday_mix"), selection: $interdayLearningMix) {
                        Text(L("deck_config_mix_with_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.mixWithReviews)
                        Text(L("deck_config_mix_after_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.afterReviews)
                        Text(L("deck_config_mix_before_reviews")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.ReviewMix.beforeReviews)
                    }
                } label: {
                    optionCapsule(interdayLearningMixLabel)
                }
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var fsrsSection: some View {
        Section(L("deck_config_section_fsrs")) {
            Toggle(L("deck_config_fsrs_enable"), isOn: $fsrsEnabled)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_desired_retention"))
                    Spacer()
                    Text("\(Int(desiredRetentionPercent))%")
                        .foregroundStyle(Color.amgiAccent)
                }
                Slider(value: $desiredRetentionPercent, in: 70...97, step: 1)
                    .tint(Color.amgiAccent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_historical_retention"))
                    Spacer()
                    Text("\(Int(historicalRetentionPercent))%")
                        .foregroundStyle(Color.amgiAccent)
                }
                Slider(value: $historicalRetentionPercent, in: 70...100, step: 1)
                    .tint(Color.amgiAccent)
            }
            if fsrsEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("deck_config_fsrs_weights"))

                    TextField(L("deck_config_fsrs_weights_hint"), text: $fsrsWeights, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.monospaced(.caption)())
                        .foregroundStyle(Color.amgiAccent)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("deck_config_fsrs_simulator_section"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)

                    Button {
                        openFsrsSimulator(.workload)
                    } label: {
                        Text(L("deck_config_fsrs_help_decide"))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.amgiAccent)

                    Button {
                        openFsrsSimulator(.review)
                    } label: {
                        Text(L("deck_config_fsrs_simulator_open"))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.amgiAccent)
                }

                Button {
                    Task { await optimizeCurrentFsrsPreset() }
                } label: {
                    HStack {
                        if isOptimizingFsrs {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isOptimizingFsrs ? L("deck_config_fsrs_optimize_running") : L("deck_config_fsrs_optimize_current"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.amgiAccent)
                .disabled(isOptimizingFsrs)

                Toggle(L("deck_config_fsrs_health_check"), isOn: $fsrsHealthCheck)

                Button {
                    Task { await optimizeAllFsrsPresets() }
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
                .tint(Color.amgiAccent)
                .disabled(isOptimizingFsrs)
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var fsrsSimulatorSheet: some View {
        NavigationStack {
            Form {
                Section(L("deck_config_fsrs_simulator_settings")) {
                    Picker(L("deck_config_fsrs_simulator_type"), selection: $fsrsSimulatorMode) {
                        Text(L("deck_config_fsrs_simulator_type_review")).tag(FsrsSimulatorMode.review)
                        Text(L("deck_config_fsrs_simulator_type_workload")).tag(FsrsSimulatorMode.workload)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent(L("deck_config_fsrs_simulator_days")) {
                        TextField("", value: $fsrsSimulatorDays, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent(L("deck_config_fsrs_simulator_additional_cards")) {
                        TextField("", value: $fsrsSimulatorAdditionalCards, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if fsrsSimulatorMode == .review {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L("deck_config_desired_retention"))
                                Spacer()
                                Text("\(Int(fsrsSimulatorRetentionPercent))%")
                                    .foregroundStyle(Color.amgiAccent)
                            }
                            Slider(value: $fsrsSimulatorRetentionPercent, in: 70...99, step: 1)
                                .tint(Color.amgiAccent)
                        }
                    }

                    LabeledContent(L("deck_config_daily_new")) {
                        TextField("", value: $fsrsSimulatorNewLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent(L("deck_config_daily_review")) {
                        TextField("", value: $fsrsSimulatorReviewLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    TextField(L("deck_config_fsrs_simulator_search_hint"), text: $fsrsSimulatorSearch, axis: .vertical)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(L("deck_config_section_advanced")) {
                    LabeledContent(L("deck_config_max_interval")) {
                        TextField("", value: $fsrsSimulatorMaxInterval, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker(L("deck_config_review_order"), selection: $fsrsSimulatorReviewOrder) {
                        Text(reviewOrderText(.day)).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.day)
                        Text(reviewOrderText(.intervalsAscending)).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsAscending)
                        Text(reviewOrderText(.intervalsDescending)).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.intervalsDescending)
                        Text(reviewOrderText(.retrievabilityDescending)).tag(Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder.retrievabilityDescending)
                    }

                    Toggle(L("deck_config_new_cards_ignore_review_limit"), isOn: $fsrsSimulatorIgnoreNewLimit)
                    Toggle(L("deck_config_fsrs_simulator_suspend_leeches"), isOn: $fsrsSimulatorSuspendLeeches)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            Task { await runFsrsSimulator() }
                        } label: {
                            if isSimulatingFsrs {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(L("deck_config_fsrs_simulator_run"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.amgiAccent)
                        .disabled(isSimulatingFsrs)

                        Button(L("deck_config_fsrs_simulator_clear")) {
                            fsrsSimulatorResult = nil
                        }
                        .buttonStyle(.bordered)

                        Button(L("deck_config_fsrs_simulator_save_to_preset")) {
                            Task { await saveFsrsSimulatorSettingsToPreset() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section(L("deck_config_fsrs_simulator_result")) {
                    if let fsrsSimulatorResult {
                        ForEach(fsrsSimulatorResult.summary, id: \.0) { item in
                            LabeledContent(item.0, value: item.1)
                        }

                        ForEach(fsrsSimulatorResult.rows, id: \.0) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.0)
                                    .font(.headline)
                                HStack {
                                    Text(row.1)
                                    Spacer()
                                    Text(row.2)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                }
                                .amgiFont(.caption)
                            }
                        }
                    } else {
                        Text(L("deck_config_fsrs_simulator_empty"))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
            }
            .navigationTitle(L("deck_config_fsrs_simulator_section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) {
                        showFsrsSimulator = false
                    }
                }
            }
        }
    }

    private var burySection: some View {
        Section(L("deck_config_section_bury")) {
            Toggle(L("deck_config_bury_new"), isOn: $buryNew)
            Toggle(L("deck_config_bury_reviews"), isOn: $buryReviews)
            Toggle(L("deck_config_bury_interday"), isOn: $buryInterdayLearning)
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var timerSection: some View {
        Section(L("deck_config_section_timer")) {
            Toggle(L("deck_config_show_timer"), isOn: $showTimer)
            LabeledContent(L("deck_config_timer_cap")) {
                editableNumberStepper($capAnswerTimeToSecs, in: 5...600, unitFormatKey: "deck_config_seconds_fmt")
            }
            Toggle(L("deck_config_stop_timer_on_answer"), isOn: $stopTimerOnAnswer)
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var autoAdvanceSection: some View {
        Section(L("deck_config_section_auto_advance")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_question_secs"))
                    Spacer()
                    Text(String(format: "%.1f s", secondsToShowQuestion))
                        .foregroundStyle(Color.amgiAccent)
                }
                Slider(value: $secondsToShowQuestion, in: 0...60, step: 0.5)
                    .tint(Color.amgiAccent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("deck_config_answer_secs"))
                    Spacer()
                    Text(String(format: "%.1f s", secondsToShowAnswer))
                        .foregroundStyle(Color.amgiAccent)
                }
                Slider(value: $secondsToShowAnswer, in: 0...60, step: 0.5)
                    .tint(Color.amgiAccent)
            }
            LabeledContent(L("deck_config_after_question")) {
                Menu {
                    Picker(L("deck_config_after_question"), selection: $questionAction) {
                        Text(L("deck_config_action_show_answer")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showAnswer)
                        Text(L("deck_config_action_show_reminder")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.QuestionAction.showReminder)
                    }
                } label: {
                    optionCapsule(questionActionLabel)
                }
            }
            LabeledContent(L("deck_config_after_answer")) {
                Menu {
                    Picker(L("deck_config_after_answer"), selection: $answerAction) {
                        Text(L("deck_config_action_bury")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.buryCard)
                        Text(L("deck_config_action_again")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerAgain)
                        Text(L("deck_config_action_hard")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerHard)
                        Text(L("deck_config_action_good")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.answerGood)
                        Text(L("deck_config_action_show_reminder")).foregroundStyle(Color.amgiAccent).tag(Anki_DeckConfig_DeckConfig.Config.AnswerAction.showReminder)
                    }
                } label: {
                    optionCapsule(answerActionLabel)
                }
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var advancedSection: some View {
        Section(L("deck_config_section_advanced")) {
            Toggle(L("deck_config_disable_autoplay"), isOn: $disableAutoplay)
            Toggle(L("deck_config_wait_audio"), isOn: $waitForAudio)
            Toggle(L("deck_config_skip_question_audio"), isOn: $skipQuestionWhenReplayingAnswer)
            LabeledContent(L("deck_config_max_interval")) {
                editableNumberStepper($maximumReviewIntervalDays, in: 1...36500, unitFormatKey: "deck_config_days_fmt")
            }
            LabeledContent(L("deck_config_minimum_lapse_interval")) {
                editableNumberStepper($minimumLapseIntervalDays, in: 1...36500, unitFormatKey: "deck_config_days_fmt")
            }
            percentWheelPicker(L("deck_config_initial_ease"), value: $initialEasePercent, in: 130...400)
            percentWheelPicker(L("deck_config_interval_mult"), value: $intervalMultiplierPercent, in: 50...200)
            percentWheelPicker(L("deck_config_lapse_multiplier"), value: $lapseMultiplierPercent, in: 0...100)
            percentWheelPicker(L("deck_config_hard_mult"), value: $hardMultiplierPercent, in: 80...200)
            percentWheelPicker(L("deck_config_easy_mult"), value: $easyMultiplierPercent, in: 100...300)
        }
        .listRowBackground(Color.amgiSurfaceElevated)
    }

    private var easyDaysSection: some View {
        Section(L("deck_config_section_easy_days")) {
            ForEach(0..<7, id: \.self) { idx in
                percentWheelPicker(
                    weekdayName(idx),
                    value: Binding(
                        get: { easyDayPercentages[idx] },
                        set: { easyDayPercentages[idx] = $0 }
                    ),
                    in: 50...150
                )
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(Color.amgiSurfaceElevated)
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
                newPerDayMinimum = Int32(cfg.newPerDayMinimum)
                learningStepsText = formatSteps(cfg.learnSteps)
                relearningStepsText = formatSteps(cfg.relearnSteps)
                graduatingGoodDays = Int32(cfg.graduatingIntervalGood)
                graduatingEasyDays = Int32(cfg.graduatingIntervalEasy)
                leechThreshold = Int32(cfg.leechThreshold)

                newCardInsertOrder = cfg.newCardInsertOrder
                newMix = cfg.newMix
                newCardGatherPriority = cfg.newCardGatherPriority
                newCardSortOrder = cfg.newCardSortOrder
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
                minimumLapseIntervalDays = Int32(max(cfg.minimumLapseInterval, 1))
                initialEasePercent = cfg.initialEase > 0 ? Double(cfg.initialEase * 100) : 250
                intervalMultiplierPercent = Double(cfg.intervalMultiplier * 100)
                lapseMultiplierPercent = Double(cfg.lapseMultiplier * 100)
                hardMultiplierPercent = Double(cfg.hardMultiplier * 100)
                easyMultiplierPercent = Double(cfg.easyMultiplier * 100)
                historicalRetentionPercent = cfg.historicalRetention > 0 ? Double(cfg.historicalRetention * 100) : 90
                newCardsIgnoreReviewLimit = effectiveContext.newCardsIgnoreReviewLimit
                applyAllParentLimits = effectiveContext.applyAllParentLimits
                fsrsHealthCheck = effectiveContext.fsrsHealthCheck
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

    private func optimizeCurrentFsrsPreset() async {
        guard let config else { return }

        isOptimizingFsrs = true
        defer { isOptimizingFsrs = false }

        do {
            let cfg = config.config
            var req = Anki_Scheduler_ComputeFsrsParamsRequest()
            req.search = fsrsSimulatorSearchText(from: cfg)
            req.currentParams = effectiveFsrsWeights(from: cfg)
            req.ignoreRevlogsBeforeMs = ignoreRevlogsBeforeMs(from: cfg.ignoreRevlogsBeforeDate)
            req.numOfRelearningSteps = relearningStepsInDay(cfg.relearnSteps)
            req.healthCheck = fsrsHealthCheck

            let response = try deckClient.computeFsrsParams(req)
            guard !response.params.isEmpty else {
                errorMessage = L("deck_config_fsrs_optimize_no_reviews")
                showError = true
                return
            }

            fsrsWeights = response.params.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            if response.hasHealthCheckPassed && !response.healthCheckPassed {
                errorMessage = L("deck_config_fsrs_health_check_failed")
                showError = true
            }
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func optimizeAllFsrsPresets() async {
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

    private func openFsrsSimulator(_ mode: FsrsSimulatorMode) {
        fsrsSimulatorMode = mode
        fsrsSimulatorDays = 365
        fsrsSimulatorAdditionalCards = 0
        fsrsSimulatorRetentionPercent = desiredRetentionPercent
        fsrsSimulatorNewLimit = Int(max(0, newCardsPerDay))
        fsrsSimulatorReviewLimit = mode == .workload ? 9999 : Int(max(0, reviewsPerDay))
        fsrsSimulatorMaxInterval = Int(max(1, maximumReviewIntervalDays))
        fsrsSimulatorSearch = fsrsSimulationSearch.isEmpty ? defaultFsrsSearch : fsrsSimulationSearch
        fsrsSimulatorIgnoreNewLimit = newCardsIgnoreReviewLimit
        fsrsSimulatorReviewOrder = reviewOrder
        fsrsSimulatorSuspendLeeches = leechAction == .suspend
        fsrsSimulatorResult = nil
        showFsrsSimulator = true
    }

    private func runFsrsSimulator() async {
        guard let config else { return }

        let weights = effectiveFsrsWeights(from: config.config)
        guard !weights.isEmpty else {
            fsrsSimulatorResult = FsrsSimulatorResult(summary: [], rows: [])
            return
        }

        isSimulatingFsrs = true
        defer { isSimulatingFsrs = false }

        do {
            var req = Anki_Scheduler_SimulateFsrsReviewRequest()
            req.params = weights
            req.desiredRetention = Float(fsrsSimulatorRetentionPercent / 100)
            req.deckSize = UInt32(max(0, fsrsSimulatorAdditionalCards))
            req.daysToSimulate = UInt32(max(1, fsrsSimulatorDays))
            req.newLimit = UInt32(max(0, fsrsSimulatorNewLimit))
            req.reviewLimit = UInt32(max(0, fsrsSimulatorReviewLimit))
            req.maxInterval = UInt32(max(1, fsrsSimulatorMaxInterval))
            req.search = fsrsSimulatorSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            req.newCardsIgnoreReviewLimit = fsrsSimulatorIgnoreNewLimit
            req.easyDaysPercentages = easyDayPercentages.map { Float($0 / 100) }
            req.reviewOrder = fsrsSimulatorReviewOrder
            req.historicalRetention = Float(historicalRetentionPercent / 100)
            req.learningStepCount = UInt32(parseSteps(learningStepsText).count)
            req.relearningStepCount = UInt32(parseSteps(relearningStepsText).count)
            if fsrsSimulatorSuspendLeeches {
                req.suspendAfterLapseCount = UInt32(max(1, leechThreshold))
            }

            switch fsrsSimulatorMode {
            case .review:
                let response = try deckClient.simulateFsrsReview(req)
                fsrsSimulatorResult = renderReviewSimulation(response)
            case .workload:
                let response = try deckClient.simulateFsrsWorkload(req)
                fsrsSimulatorResult = renderWorkloadSimulation(response)
            }
        } catch {
            errorMessage = L("deck_config_error_save", error.localizedDescription)
            showError = true
        }
    }

    private func saveFsrsSimulatorSettingsToPreset() async {
        if fsrsSimulatorMode == .review {
            desiredRetentionPercent = fsrsSimulatorRetentionPercent
        }
        newCardsPerDay = Int32(max(0, fsrsSimulatorNewLimit))
        reviewsPerDay = Int32(max(0, fsrsSimulatorReviewLimit))
        maximumReviewIntervalDays = Int32(max(1, fsrsSimulatorMaxInterval))
        fsrsSimulationSearch = fsrsSimulatorSearch
        newCardsIgnoreReviewLimit = fsrsSimulatorIgnoreNewLimit
        reviewOrder = fsrsSimulatorReviewOrder
        leechAction = fsrsSimulatorSuspendLeeches ? .suspend : .tagOnly

        guard let updatedConfig = makeEditedConfigDraft() else { return }
        await persistConfig(updatedConfig, dismissOnSuccess: false)
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
        cfg.newPerDayMinimum = UInt32(max(0, newPerDayMinimum))
        cfg.learnSteps = parseSteps(learningStepsText)
        cfg.relearnSteps = parseSteps(relearningStepsText)
        cfg.graduatingIntervalGood = UInt32(max(0, graduatingGoodDays))
        cfg.graduatingIntervalEasy = UInt32(max(0, graduatingEasyDays))
        cfg.leechThreshold = UInt32(max(1, leechThreshold))

        cfg.newCardInsertOrder = newCardInsertOrder
        cfg.newMix = newMix
        cfg.newCardGatherPriority = newCardGatherPriority
        cfg.newCardSortOrder = newCardSortOrder
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
        cfg.minimumLapseInterval = UInt32(max(1, minimumLapseIntervalDays))
        cfg.initialEase = Float(initialEasePercent / 100)
        cfg.intervalMultiplier = Float(intervalMultiplierPercent / 100)
        cfg.lapseMultiplier = Float(lapseMultiplierPercent / 100)
        cfg.hardMultiplier = Float(hardMultiplierPercent / 100)
        cfg.easyMultiplier = Float(easyMultiplierPercent / 100)
        cfg.easyDaysPercentages = easyDayPercentages.map { Float($0 / 100) }

        cfg.desiredRetention = Float(desiredRetentionPercent / 100)
        cfg.historicalRetention = Float(historicalRetentionPercent / 100)
        cfg.paramSearch = fsrsSimulationSearch.trimmingCharacters(in: .whitespacesAndNewlines)

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
            try deckClient.updateDeckConfig(
                deckId,
                updatedConfig,
                applyToChildren,
                fsrsEnabled,
                newCardsIgnoreReviewLimit,
                applyAllParentLimits,
                fsrsHealthCheck
            )
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

    private var defaultFsrsSearch: String {
        let escapedName = configName.replacingOccurrences(of: "\"", with: "\\\"")
        return "preset:\"\(escapedName)\" -is:suspended"
    }

    private func fsrsSimulatorSearchText(from cfg: Anki_DeckConfig_DeckConfig.Config) -> String {
        let search = cfg.paramSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? defaultFsrsSearch : search
    }

    private func effectiveFsrsWeights(from cfg: Anki_DeckConfig_DeckConfig.Config) -> [Float] {
        let editedWeights = parseFloatArray(fsrsWeights)
        if !editedWeights.isEmpty { return editedWeights }
        if !cfg.fsrsParams6.isEmpty { return cfg.fsrsParams6 }
        if !cfg.fsrsParams5.isEmpty { return cfg.fsrsParams5 }
        return cfg.fsrsParams4
    }

    private func ignoreRevlogsBeforeMs(from value: String) -> Int64 {
        guard !value.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: value) else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func relearningStepsInDay(_ steps: [Float]) -> UInt32 {
        var count: UInt32 = 0
        var accumulated: Float = 0
        for step in steps {
            accumulated += step
            if accumulated >= 1440 { break }
            count += 1
        }
        return count
    }

    private func renderReviewSimulation(_ response: Anki_Scheduler_SimulateFsrsReviewResponse) -> FsrsSimulatorResult {
        let totalNew = response.dailyNewCount.reduce(0, +)
        let totalReview = response.dailyReviewCount.reduce(0, +)
        let totalTime = response.dailyTimeCost.reduce(0, +)
        let memorized = response.accumulatedKnowledgeAcquisition.last ?? 0
        let days = max(response.dailyReviewCount.count, 1)

        return FsrsSimulatorResult(
            summary: [
                (L("deck_config_fsrs_simulator_total_new"), "\(totalNew)"),
                (L("deck_config_fsrs_simulator_total_reviews"), "\(totalReview)"),
                (L("deck_config_fsrs_simulator_avg_reviews"), String(format: "%.1f", Double(totalReview) / Double(days))),
                (L("deck_config_fsrs_simulator_total_time"), String(format: "%.1f", Double(totalTime))),
                (L("deck_config_fsrs_simulator_memorized"), String(format: "%.1f", Double(memorized)))
            ],
            rows: []
        )
    }

    private func renderWorkloadSimulation(_ response: Anki_Scheduler_SimulateFsrsWorkloadResponse) -> FsrsSimulatorResult {
        let rows = response.cost.keys.sorted().map { retention in
            let cost = response.cost[retention] ?? 0
            let count = response.reviewCount[retention] ?? 0
            let memorized = response.memorized[retention] ?? 0
            return (
                "\(retention)%",
                L("deck_config_fsrs_simulator_workload_cost", String(format: "%.2f", Double(cost))),
                L("deck_config_fsrs_simulator_workload_cards", count, String(format: "%.1f", Double(memorized)))
            )
        }

        return FsrsSimulatorResult(
            summary: [(L("deck_config_fsrs_simulator_points"), "\(rows.count)")],
            rows: rows
        )
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
