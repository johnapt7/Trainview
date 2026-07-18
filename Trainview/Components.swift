import SwiftUI

/// How a station row presents itself; `.nearby` adds the distance readout.
enum StationRowStyle {
    case nearby, search, recent
}

/// The shared station list card: ink code tags, home-station toggles,
/// hairline dividers. Used by the home search/nearby/recent lists.
struct StationListCard: View {
    let stations: [Station]
    let style: StationRowStyle
    let accent: Color
    let homeStore: HomeStationsStore
    let onPick: (Station) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element.code) { index, station in
                HStack(spacing: 0) {
                    Button {
                        onPick(station)
                    } label: {
                        HStack(spacing: 12) {
                            Text(station.code)
                                .font(.mono(11, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.cream)
                                .frame(width: 42, height: 42)
                                .background(Theme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(station.name)
                                    .font(.display(18))
                                    .tracking(-0.1)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                if station.isInterchange {
                                    Text("Interchange station")
                                        .font(.ui(11))
                                        .foregroundStyle(Theme.inkMute)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if case .nearby = style, let dist = station.dist {
                                Text(dist < 1 ? String(format: "%.0fm", dist * 1000) : String(format: "%.1fkm", dist))
                                    .font(.mono(12, weight: .semibold))
                                    .tracking(-0.1)
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        // Rows have no background fill, so without an explicit
                        // shape only the drawn pixels are tappable.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Home-station badge: only rows that ARE home stations
                    // carry the house (tap to remove). Adding happens via the
                    // account sheet and the Home-stations section's plus.
                    if homeStore.contains(station) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                homeStore.remove(station)
                            }
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(accent)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    if index < stations.count - 1 {
                        Divider().overlay(Theme.line)
                    }
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

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
        // Status chips stay bright in dark mode — their fixed dark
        // foregrounds need the light variants of the chip backgrounds.
        .environment(\.colorScheme, .light)
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
