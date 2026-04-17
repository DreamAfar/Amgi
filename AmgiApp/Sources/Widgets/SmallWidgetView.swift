// AmgiApp/Sources/Widgets/SmallWidgetView.swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Streak row
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.system(size: 17))
                Text("\(snapshot.streak)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.orange)
                Text("day streak")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Hero due count
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.totalDue)")
                    .font(.system(size: 54, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .kerning(-2)
                Text("cards due")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Deck name
            Text(snapshot.deckName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "amgi://review?deckId=\(snapshot.deckId)"))
    }
}

#Preview(as: .systemSmall) {
    AmgiWidget()
} timeline: {
    WidgetEntry(date: Date(), snapshot: .placeholder)
}
