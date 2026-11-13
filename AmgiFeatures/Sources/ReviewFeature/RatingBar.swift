//
//  RatingBar.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 20.07.2026.
//

import SwiftUI
import Theme
import AnkiKit

/// How the rating row draws its buttons. Stored by raw value in
/// `ReviewPreferences.Keys.answerButtonStyle`.
public enum AnswerButtonStyle: String, CaseIterable, Sendable {
    /// R11: elevated surface cards with a colored top border.
    case cards
    /// Filled buttons in each rating's color, matching Show Answer.
    case filled
}

/// R11 rating row: four elevated cards — surface background, hairline ring,
/// 3px colored top border, next-interval caption above the label. The
/// `filled` style swaps them for solid buttons in each rating's color, and
/// `showsHardAndEasy: false` cuts the row down to Again and Good.
struct RatingBar: View {
    let intervals: [Rating: String]
    let showIntervals: Bool
    let isDisabled: Bool
    let shortcutsEnabled: Bool
    var style: AnswerButtonStyle = .cards
    var showsHardAndEasy = true
    let onRate: (Rating) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Choice {
        let rating: Rating
        let label: String
        let key: Character
    }

    private var choices: [Choice] {
        let all = [
            Choice(rating: .again, label: String(localized: "Again", bundle: .module), key: "1"),
            Choice(rating: .hard, label: String(localized: "Hard", bundle: .module), key: "2"),
            Choice(rating: .good, label: String(localized: "Good", bundle: .module), key: "3"),
            Choice(rating: .easy, label: String(localized: "Easy", bundle: .module), key: "4"),
        ]
        return showsHardAndEasy ? all : all.filter { $0.rating == .again || $0.rating == .good }
    }

    private func color(for rating: Rating) -> Color {
        switch rating {
        case .again: palette.danger
        case .hard: palette.warning
        case .good: palette.positive
        case .easy: palette.info
        }
    }

    var body: some View {
        layout
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize && choices.count == 4 {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    ratingCard(choices[0])
                    ratingCard(choices[1])
                }
                GridRow {
                    ratingCard(choices[2])
                    ratingCard(choices[3])
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(choices, id: \.rating) { ratingCard($0) }
            }
        }
    }

    private func ratingCard(_ choice: Choice) -> some View {
        Group {
            switch style {
            case .cards:
                ratingCard(choice.rating, label: choice.label, color: color(for: choice.rating))
            case .filled:
                filledButton(choice.rating, label: choice.label, color: color(for: choice.rating))
            }
        }
        .keyboardShortcut(
            shortcutsEnabled
                ? KeyboardShortcut(KeyEquivalent(choice.key), modifiers: [])
                : nil
        )
    }

    private func ratingCard(_ rating: Rating, label: String, color: Color) -> some View {
        Button {
            onRate(rating)
        } label: {
            VStack(spacing: 4) {
                if showIntervals {
                    Text(intervals[rating] ?? " ")
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(label)
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(palette.surface)
            .overlay(alignment: .top) {
                color
                    .frame(height: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous)
                    .strokeBorder(palette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.pressScale)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(rating, label: label))
    }

    /// Same shape as the Show Answer button, tinted with the rating's color.
    private func filledButton(_ rating: Rating, label: String, color: Color) -> some View {
        Button {
            onRate(rating)
        } label: {
            VStack(spacing: 2) {
                if showIntervals {
                    Text(intervals[rating] ?? " ")
                        .amgiFont(.caption)
                        .opacity(0.85)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(label)
                    .amgiFont(.bodyEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(rating, label: label))
    }

    private func accessibilityLabel(_ rating: Rating, label: String) -> String {
        "\(label)\(showIntervals ? String(localized: ", next in \(intervals[rating] ?? "")", bundle: .module) : "")"
    }
}

#if DEBUG
#Preview("Rating bar") {
    RatingBar(
        intervals: [.again: "<1m", .hard: "8m", .good: "10m", .easy: "4d"],
        showIntervals: true,
        isDisabled: false,
        shortcutsEnabled: true,
        onRate: { _ in }
    )
}

#Preview("Rating bar · filled, two buttons") {
    RatingBar(
        intervals: [.again: "<1m", .hard: "8m", .good: "10m", .easy: "4d"],
        showIntervals: true,
        isDisabled: false,
        shortcutsEnabled: true,
        style: .filled,
        showsHardAndEasy: false,
        onRate: { _ in }
    )
}

#Preview("Rating bar · accessibility size") {
    RatingBar(
        intervals: [.again: "<1m", .hard: "8m", .good: "10m", .easy: "4d"],
        showIntervals: true,
        isDisabled: false,
        shortcutsEnabled: true,
        onRate: { _ in }
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
