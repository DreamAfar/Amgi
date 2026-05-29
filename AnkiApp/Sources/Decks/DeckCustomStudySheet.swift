import SwiftUI
import AnkiClients
import AnkiBackend
import AnkiKit
import AnkiProto
import Dependencies

enum DeckCustomStudyMode: String, CaseIterable, Identifiable {
    case newLimit
    case reviewLimit
    case forgot
    case ahead
    case preview
    case cram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newLimit: L("deck_custom_study_mode_new_limit")
        case .reviewLimit: L("deck_custom_study_mode_review_limit")
        case .forgot: L("deck_custom_study_mode_forgot")
        case .ahead: L("deck_custom_study_mode_ahead")
        case .preview: L("deck_custom_study_mode_preview")
        case .cram: L("deck_custom_study_mode_cram")
        }
    }

    var icon: String {
        switch self {
        case .newLimit: return "plus.rectangle.on.folder"
        case .reviewLimit: return "plus.rectangle.stack"
        case .forgot: return "arrow.counterclockwise.circle"
        case .ahead: return "forward.circle"
        case .preview: return "eye"
        case .cram: return "tag"
        }
    }
}

func makeDeckCustomStudyRequest(
    deckID: Int64,
    mode: DeckCustomStudyMode,
    amount: Int,
    cramKind: Anki_Scheduler_CustomStudyRequest.Cram.CramKind,
    includeTags: Set<String>,
    excludeTags: Set<String>
) -> Anki_Scheduler_CustomStudyRequest {
    var request = Anki_Scheduler_CustomStudyRequest()
    request.deckID = deckID

    switch mode {
    case .newLimit:
        request.newLimitDelta = Int32(amount)
    case .reviewLimit:
        request.reviewLimitDelta = Int32(amount)
    case .forgot:
        request.forgotDays = UInt32(amount)
    case .ahead:
        request.reviewAheadDays = UInt32(amount)
    case .preview:
        request.previewDays = UInt32(amount)
    case .cram:
        var cram = Anki_Scheduler_CustomStudyRequest.Cram()
        cram.kind = cramKind
        cram.cardLimit = UInt32(amount)
        cram.tagsToInclude = includeTags.sorted()
        cram.tagsToExclude = excludeTags.sorted()
        request.cram = cram
    }

    return request
}

func shouldAutoStartReview(for mode: DeckCustomStudyMode) -> Bool {
    switch mode {
    case .newLimit, .reviewLimit:
        return false
    case .forgot, .ahead, .preview, .cram:
        return true
    }
}

struct DeckCustomStudySheet: View {
    let deck: DeckInfo
    let onComplete: (_ targetDeck: Anki_Decks_Deck, _ startReview: Bool) -> Void

    @Dependency(\.deckClient) var deckClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var defaults: Anki_Scheduler_CustomStudyDefaultsResponse?
    @State private var mode: DeckCustomStudyMode = .newLimit
    @State private var amountText = ""
    @State private var cramKind: Anki_Scheduler_CustomStudyRequest.Cram.CramKind = .new
    @State private var includeTags = Set<String>()
    @State private var excludeTags = Set<String>()
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("deck_custom_study_loading"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
            } else if defaults == nil {
                ContentUnavailableView(
                    L("deck_custom_study_title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage ?? L("common_unknown_error"))
                )
                .background(palette.background)
            } else {
                formContent
            }
        }
        .navigationTitle(L("deck_custom_study_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if defaults == nil && !isLoading {
                    Button(L("btn_retry")) {
                        Task { await loadDefaults() }
                    }
                    .amgiToolbarTextButton()
                    .disabled(isWorking)
                } else {
                    Button(L("common_done")) {
                        Task { await submit() }
                    }
                    .disabled(isLoading || isWorking)
                }
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .task {
            await loadDefaults()
        }
    }

    private var formContent: some View {
        Form {
            Section(L("deck_custom_study_section_mode")) {
                ForEach(DeckCustomStudyMode.allCases) { candidate in
                    Button {
                        mode = candidate
                        applyDefaults(for: candidate)
                    } label: {
                        HStack(spacing: 12) {
                            Label(candidate.title, systemImage: candidate.icon)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if mode == candidate {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(L("deck_custom_study_section_options")) {
                if let descriptionText {
                    Text(descriptionText)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Text(amountPrompt)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 12)
                    TextField("", text: $amountText)
                        .keyboardType(allowsNegativeInput ? .numbersAndPunctuation : .numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 88)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(amountUnit)
                        .foregroundStyle(palette.textSecondary)
                }

                if mode == .cram {
                    Picker(L("deck_custom_study_cram_kind"), selection: $cramKind) {
                        ForEach(Anki_Scheduler_CustomStudyRequest.Cram.CramKind.allCases, id: \.self) { kind in
                            Text(cramKindTitle(kind)).tag(kind)
                        }
                    }

                    NavigationLink {
                        DeckCustomStudyTagPickerView(
                            title: L("deck_custom_study_include_tags"),
                            allTags: availableTags,
                            selectedTags: $includeTags,
                            oppositeTags: $excludeTags
                        )
                    } label: {
                        HStack {
                            Text(L("deck_custom_study_include_tags"))
                            Spacer()
                            Text(tagSummary(includeTags))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }

                    NavigationLink {
                        DeckCustomStudyTagPickerView(
                            title: L("deck_custom_study_exclude_tags"),
                            allTags: availableTags,
                            selectedTags: $excludeTags,
                            oppositeTags: $includeTags
                        )
                    } label: {
                        HStack {
                            Text(L("deck_custom_study_exclude_tags"))
                            Spacer()
                            Text(tagSummary(excludeTags))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(isWorking)
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                    ProgressView()
                        .padding(20)
                        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var availableTags: [String] {
        defaults?.tags.map(\.name) ?? []
    }

    private var allowsNegativeInput: Bool {
        mode == .newLimit || mode == .reviewLimit
    }

    private var amountPrompt: String {
        switch mode {
        case .newLimit:
            return L("deck_custom_study_prompt_new_limit")
        case .reviewLimit:
            return L("deck_custom_study_prompt_review_limit")
        case .forgot:
            return L("deck_custom_study_prompt_forgot")
        case .ahead:
            return L("deck_custom_study_prompt_ahead")
        case .preview:
            return L("deck_custom_study_prompt_preview")
        case .cram:
            return L("deck_custom_study_prompt_cram")
        }
    }

    private var amountUnit: String {
        switch mode {
        case .newLimit, .reviewLimit, .cram:
            return L("deck_custom_study_unit_cards")
        case .forgot, .ahead, .preview:
            return L("deck_custom_study_unit_days")
        }
    }

    private var descriptionText: String? {
        guard let defaults else { return nil }

        switch mode {
        case .newLimit:
            return L("deck_custom_study_available_new_cards", countSummary(parent: defaults.availableNew, children: defaults.availableNewInChildren))
        case .reviewLimit:
            return L("deck_custom_study_available_review_cards", countSummary(parent: defaults.availableReview, children: defaults.availableReviewInChildren))
        case .forgot:
            return L("deck_custom_study_hint_forgot")
        case .ahead:
            return L("deck_custom_study_hint_ahead")
        case .preview:
            return L("deck_custom_study_hint_preview")
        case .cram:
            return availableTags.isEmpty ? L("deck_custom_study_no_tags") : L("deck_custom_study_hint_cram")
        }
    }

    private func loadDefaults() async {
        isLoading = true
        defer { isLoading = false }

        let deckClient = self.deckClient
        do {
            let response = try await Task.detached(priority: .userInitiated) {
                try deckClient.fetchCustomStudyDefaults(deck.id)
            }.value
            defaults = response
            includeTags = Set(response.tags.filter { $0.include }.map(\.name))
            excludeTags = Set(response.tags.filter { $0.exclude }.map(\.name))
            applyDefaults(for: mode)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func applyDefaults(for mode: DeckCustomStudyMode) {
        guard let defaults else { return }

        switch mode {
        case .newLimit:
            amountText = String(Int(defaults.extendNew))
        case .reviewLimit:
            amountText = String(Int(defaults.extendReview))
        case .forgot, .ahead, .preview:
            amountText = "1"
        case .cram:
            amountText = "100"
        }
    }

    private func submit() async {
        guard !isWorking else { return }
        guard defaults != nil else {
            errorMessage = L("deck_custom_study_load_failed")
            showError = true
            return
        }

        do {
            let amount = try validatedAmount()
            let request = makeDeckCustomStudyRequest(
                deckID: deck.id,
                mode: mode,
                amount: amount,
                cramKind: cramKind,
                includeTags: includeTags,
                excludeTags: excludeTags
            )
            let shouldStartReview = shouldAutoStartReview(for: mode)
            let deckClient = self.deckClient

            isWorking = true
            let targetDeck = try await Task.detached(priority: .userInitiated) {
                try deckClient.customStudy(request)
            }.value
            isWorking = false

            dismiss()
            onComplete(targetDeck, shouldStartReview)
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func validatedAmount() throws -> Int {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Int(trimmed) else {
            throw BackendError(kind: .invalidInput, message: L("deck_custom_study_invalid_number"))
        }

        switch mode {
        case .newLimit, .reviewLimit:
            guard (-99_999...99_999).contains(amount) else {
                throw BackendError(kind: .invalidInput, message: L("deck_custom_study_invalid_delta"))
            }
        case .forgot:
            guard (1...30).contains(amount) else {
                throw BackendError(kind: .invalidInput, message: L("deck_custom_study_invalid_forgot_days"))
            }
        case .ahead, .preview, .cram:
            guard (1...99_999).contains(amount) else {
                throw BackendError(kind: .invalidInput, message: L("deck_custom_study_invalid_positive"))
            }
        }

        return amount
    }

    private func countSummary(parent: UInt32, children: UInt32) -> String {
        if children > 0 {
            return "\(parent) \(L("deck_custom_study_available_child_count", Int(children)))"
        }
        return "\(parent)"
    }

    private func cramKindTitle(_ kind: Anki_Scheduler_CustomStudyRequest.Cram.CramKind) -> String {
        switch kind {
        case .new:
            return L("deck_custom_study_cram_new")
        case .due:
            return L("deck_custom_study_cram_due")
        case .review:
            return L("deck_custom_study_cram_review")
        case .all:
            return L("deck_custom_study_cram_all")
        case .UNRECOGNIZED:
            return L("deck_custom_study_cram_unknown")
        }
    }

    private func tagSummary(_ tags: Set<String>) -> String {
        if tags.isEmpty {
            return L("common_none")
        }
        if tags.count == 1, let tag = tags.first {
            return tag
        }
        return L("deck_custom_study_selected_tags_count", tags.count)
    }
}

private struct DeckCustomStudyTagPickerView: View {
    let title: String
    let allTags: [String]
    @Binding var selectedTags: Set<String>
    @Binding var oppositeTags: Set<String>
    @Environment(\.palette) private var palette

    @State private var searchText = ""

    private var filteredTags: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allTags }
        return allTags.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if allTags.isEmpty {
                ContentUnavailableView(
                    title,
                    systemImage: "tag.slash",
                    description: Text(L("deck_custom_study_no_tags"))
                )
            } else {
                List(filteredTags, id: \.self) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack {
                            Text(tag)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(palette.background)
                .searchable(text: $searchText, prompt: L("deck_custom_study_search_tags"))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
            oppositeTags.remove(tag)
        }
    }
}
