import SwiftUI
import Charts
import Foundation

struct StatsMeasuredHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        for (key, height) in nextValue() {
            value[key] = max(value[key] ?? 0, height)
        }
    }
}

private struct StatsCardMinHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var statsCardMinHeight: CGFloat? {
        get { self[StatsCardMinHeightKey.self] }
        set { self[StatsCardMinHeightKey.self] = newValue }
    }
}

enum StatsBarLayoutSupport {
    static func displayedSlotCount(
        lowerBound: Int,
        upperBound: Int,
        bucketSize: Int
    ) -> Int {
        guard bucketSize > 0, upperBound >= lowerBound else { return 1 }
        let inclusiveSpan = upperBound - lowerBound + 1
        return max(1, Int(ceil(Double(inclusiveSpan) / Double(bucketSize))))
    }

    static func barWidth(
        slotCount: Int,
        automaticThreshold: Int = 24,
        availableWidth: CGFloat? = nil,
        minimum: Double = 2.5,
        fillRatio: Double = 0.72,
        maximumOverride: Double? = nil
    ) -> MarkDimension {
        guard slotCount > automaticThreshold else { return .automatic }
        let resolvedWidth = Double(max(availableWidth ?? 390, 180))
        let plotWidth = max(resolvedWidth - 56, 120)
        let slotWidth = plotWidth / Double(max(slotCount, 1))
        let maximum: Double = maximumOverride ?? {
            switch plotWidth {
            case ..<300:
                return 7
            case ..<420:
                return 9
            case ..<820:
                return 12
            case ..<1180:
                return 16
            default:
                return 22
            }
        }()
        let adjustedFillRatio: Double
        switch slotCount {
        case 0..<24:
            adjustedFillRatio = 0.64
        case 24..<48:
            adjustedFillRatio = fillRatio
        case 48..<96:
            adjustedFillRatio = min(fillRatio + 0.08, 0.82)
        default:
            adjustedFillRatio = min(fillRatio + 0.14, 0.88)
        }
        let width = max(minimum, min(maximum, slotWidth * adjustedFillRatio))
        return .fixed(width)
    }
}

private struct StatsMeasuredWidthModifier: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        width = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newValue in
                        width = newValue
                    }
            }
        )
    }
}

private struct StatsMeasuredHeightModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: StatsMeasuredHeightPreferenceKey.self,
                        value: [id: geometry.size.height]
                    )
            }
        )
    }
}

private struct StatsCardModifier: ViewModifier {
    let elevated: Bool
    @Environment(\.statsCardMinHeight) private var minHeight

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .amgiCard(elevated: elevated)
    }
}

extension View {
    func statsTrackWidth(_ width: Binding<CGFloat>) -> some View {
        modifier(StatsMeasuredWidthModifier(width: width))
    }

    func statsMeasureHeight(id: String) -> some View {
        modifier(StatsMeasuredHeightModifier(id: id))
    }

    func statsCard(elevated: Bool = false) -> some View {
        modifier(StatsCardModifier(elevated: elevated))
    }

    func statsCardMinHeight(_ height: CGFloat?) -> some View {
        environment(\.statsCardMinHeight, height)
    }
}
