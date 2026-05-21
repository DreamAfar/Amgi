import SwiftUI

struct ReviewFinishedConfettiView: View {
    let startDate: Date

    private let duration: TimeInterval = 2.6
    private let pieces = ReviewConfettiPiece.defaults

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                let progress = min(elapsed / duration, 1)

                ZStack {
                    ForEach(pieces) { piece in
                        confettiPiece(piece, in: geometry.size, progress: progress)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func confettiPiece(_ piece: ReviewConfettiPiece, in size: CGSize, progress: Double) -> some View {
        let delayedProgress = max(progress - piece.delay, 0)
        let normalizedDuration = max(1 - piece.delay, 0.001)
        let localProgress = min(delayedProgress / normalizedDuration, 1)

        if localProgress > 0 && localProgress < 1 {
            let xBase = size.width * piece.startX
            let drift = CGFloat(sin((localProgress * piece.waveCycles * .pi * 2) + piece.phase)) * piece.waveAmplitude
            let verticalProgress = CGFloat(pow(localProgress, 0.92))
            let y = -40 + size.height * piece.fallDistance * verticalProgress
            let fadeIn = min(localProgress / 0.12, 1)
            let fadeOut = max((1 - localProgress) / 0.18, 0)
            let opacity = min(fadeIn, fadeOut)
            let rotation = piece.rotationStart + (360 * piece.rotationTurns * localProgress)
            let scale = CGFloat(0.82 + (0.22 * sin(localProgress * .pi)))

            confettiShape(for: piece)
                .frame(width: piece.size.width, height: piece.size.height)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .position(x: xBase + drift, y: y)
                .opacity(opacity)
                .shadow(color: piece.color.opacity(0.12), radius: 3, y: 1)
        }
    }

    @ViewBuilder
    private func confettiShape(for piece: ReviewConfettiPiece) -> some View {
        switch piece.shape {
        case .rectangle:
            RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                .fill(piece.color)
        case .capsule:
            Capsule(style: .continuous)
                .fill(piece.color)
        case .circle:
            Circle()
                .fill(piece.color)
        }
    }
}

private struct ReviewConfettiPiece: Identifiable {
    enum ShapeKind {
        case rectangle
        case capsule
        case circle
    }

    let id: Int
    let color: Color
    let shape: ShapeKind
    let startX: CGFloat
    let delay: Double
    let fallDistance: CGFloat
    let waveAmplitude: CGFloat
    let waveCycles: Double
    let phase: Double
    let size: CGSize
    let cornerRadius: CGFloat
    let rotationStart: Double
    let rotationTurns: Double

    static let defaults: [ReviewConfettiPiece] = {
        let palette: [Color] = [
            .green,
            .blue,
            .orange,
            .yellow,
            .mint,
            .cyan
        ]

        return (0..<42).map { index in
            let shape: ShapeKind
            switch index % 3 {
            case 0:
                shape = .rectangle
            case 1:
                shape = .capsule
            default:
                shape = .circle
            }

            let width = CGFloat(8 + ((index * 7) % 6))
            let height = CGFloat(10 + ((index * 11) % 8))

            return ReviewConfettiPiece(
                id: index,
                color: palette[index % palette.count],
                shape: shape,
                startX: CGFloat(0.06 + (Double((index * 37) % 88) / 100.0)),
                delay: Double((index * 13) % 16) / 40.0,
                fallDistance: CGFloat(0.72 + (Double((index * 17) % 24) / 100.0)),
                waveAmplitude: CGFloat(16 + ((index * 19) % 24)),
                waveCycles: 0.9 + (Double((index * 5) % 6) * 0.22),
                phase: Double((index * 29) % 360) * .pi / 180,
                size: CGSize(width: width, height: height),
                cornerRadius: min(width, height) * 0.24,
                rotationStart: Double((index * 23) % 180),
                rotationTurns: 1.6 + (Double((index * 31) % 7) * 0.3)
            )
        }
    }()
}
