import SwiftUI

struct StatusPill: View {
    let status: TrainStatus
    let label: String

    private var colors: (bg: Color, fg: Color, dot: Color) {
        switch status {
        case .onTime:
            return (Theme.onTimeBg, Theme.ink, Theme.ink)
        case .delayed:
            return (Theme.warn, Color(hex: 0x3B2A05), Color(hex: 0x8A5A00))
        case .cancelled:
            return (Theme.bad, Color(hex: 0x4A1410), Theme.cancelledText)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colors.dot)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.ui(11, weight: .semibold))
                .tracking(0.1)
        }
        .padding(.horizontal, 10)
        .padding(.leading, -2)
        .padding(.vertical, 5)
        .background(colors.bg)
        .foregroundStyle(colors.fg)
        .clipShape(Capsule())
    }
}

struct IconButton: View {
    let systemName: String
    let size: CGFloat
    var heroStyle: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.ink.opacity(heroStyle ? 0.14 : 0.08))
                .clipShape(Circle())
        }
    }
}

struct CodeTag: View {
    let text: String
    var bg: Color = Theme.ink
    var fg: Color = Theme.cream

    var body: some View {
        Text(text)
            .font(.mono(9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct DotSeparator: View {
    var body: some View {
        Circle()
            .fill(Theme.inkMute.opacity(0.5))
            .frame(width: 3, height: 3)
    }
}

struct LiveDot: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.ink.opacity(0.4))
                .frame(width: size, height: size)
            Circle()
                .fill(Theme.ink)
                .frame(width: size * 0.43, height: size * 0.43)
        }
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.25), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: phase * 300)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Card

struct SkeletonTrainCard: View {
    private let bone = Theme.ink.opacity(0.07)

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Theme.ink.opacity(0.06))
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bone)
                        .frame(width: 72, height: 20)
                    Spacer()
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bone)
                        .frame(width: 70, height: 22)
                }
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bone)
                        .frame(width: 40, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bone)
                        .frame(width: 140, height: 18)
                }
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bone)
                        .frame(width: 28, height: 16)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bone)
                        .frame(width: 90, height: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shimmer()
    }
}

struct MonoLabel: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var tracking: CGFloat = 1.0
    var color: Color = Theme.inkMute

    var body: some View {
        Text(text)
            .font(.mono(size, weight: weight))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
