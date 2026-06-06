// AmgiApp/Sources/Widgets/AmgiWidget.swift
import WidgetKit
import SwiftUI
import AmgiTheme

struct AmgiWidget: Widget {
    let kind = "AmgiWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: AmgiWidgetIntent.self,
            provider: WidgetTimelineProvider()
        ) { entry in
            AmgiWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Amgi")
        .description("See your cards due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AmgiWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: entry.snapshot)
            case .systemLarge:
                LargeWidgetView(snapshot: entry.snapshot)
            default:
                SmallWidgetView(snapshot: entry.snapshot)
            }
        }
        .environment(\.palette, ThemeManager.shared.palette(for: colorScheme))
    }
}

enum WidgetLocalization {
    static let hostAppBundle: Bundle = {
        let bundleURL = Bundle.main.bundleURL
        let hostAppURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: hostAppURL) ?? .main
    }()

    static let bundle: Bundle = {
        let base = hostAppBundle

        if let raw = UserDefaults.amgiAppGroup.string(forKey: "app_language"),
           raw != "system",
           let path = base.path(forResource: raw, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let preferred = Bundle.preferredLocalizations(from: base.localizations).first
        guard let preferred,
              let path = base.path(forResource: preferred, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return base
        }
        return bundle
    }()
}

func WL(_ key: String) -> String {
    NSLocalizedString(key, bundle: WidgetLocalization.bundle, comment: "")
}

func WL(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: WidgetLocalization.bundle, comment: "")
    return String(format: format, arguments: args)
}

func widgetPlaceholderSnapshot() -> WidgetSnapshot {
    var snapshot = WidgetSnapshot.placeholder
    snapshot.deckName = WL("widget_all_decks")
    return snapshot
}
