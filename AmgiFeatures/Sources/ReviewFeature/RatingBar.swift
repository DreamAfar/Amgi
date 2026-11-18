//
//  RatingBar.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 20.07.2026.
//

import SwiftUI
import Theme
import AnkiKit

/// R11 rating row: four elevated cards — surface background, hairline ring,
/// 3px colored top border, next-interval caption above the label.
struct RatingBar: View {
    let intervals: [Rating: String]
    let showIntervals: Bool
    let isDisabled: Bool
    let onRate: (Rating) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Choice {
        let rating: Rating
        let label: String
    }

    private var choices: [Choice] {
        [
            Choice(rating: .again, label: String(localized: "Again", bundle: .module)),
            Choice(rating: .hard, label: String(localized: "Hard", bundle: .module)),
            Choice(rating: .good, label: String(localized: "Good", bundle: .module)),
            Choice(rating: .easy, label: String(localized: "Easy", bundle: .module)),
        ]
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
        if dynamicTypeSize.isAccessibilitySize {
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
        // Keys reach these through the reviewer's input map, not
        // `.keyboardShortcut`, which only fires while the card isn't focused.
        ratingCard(choice.rating, label: choice.label, color: color(for: choice.rating))
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
        .accessibilityLabel("\(label)\(showIntervals ? String(localized: ", next in \(intervals[rating] ?? "")", bundle: .module) : "")")
    }
}

#if DEBUG
#Preview("Rating bar") {
    RatingBar(
        intervals: [.again: "<1m", .hard: "8m", .good: "10m", .easy: "4d"],
        showIntervals: true,
        isDisabled: false,
        onRate: { _ in }
    )
}

#Preview("Rating bar · accessibility size") {
    RatingBar(
        intervals: [.again: "<1m", .hard: "8m", .good: "10m", .easy: "4d"],
        showIntervals: true,
        isDisabled: false,
        onRate: { _ in }
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
