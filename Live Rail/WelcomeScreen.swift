import SwiftUI

struct WelcomeScreen: View {
    let accent: Color
    let onContinue: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                featuresSection
                permissionsSection
                footerSection
            }
        }
        .background(Theme.cream)
        // The accent hero bleeds up behind the status bar.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandMark
            VStack(alignment: .leading, spacing: 10) {
                Text("Live departures, every platform.")
                    .font(.display(32, weight: .semibold))
                    .tracking(-0.6)
                    .lineSpacing(-2)
                Text("A clean, glanceable board for the UK rail network \u{2014} from your nearest station to the last stop on the line.")
                    .font(.ui(13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: 260, alignment: .leading)
            }
            chipRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 28,
                bottomTrailingRadius: 28, topTrailingRadius: 0
            )
        )
        .foregroundStyle(Theme.ink)
        // Bright brand hero in both colour schemes.
        .environment(\.colorScheme, .light)
    }

    private var brandMark: some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 16))
            Text("LIVE RAIL")
                .font(.mono(11, weight: .semibold))
                .tracking(1.5)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            WelcomeChip(text: "2,500+ stations")
            WelcomeChip(text: "Real-time")
            WelcomeChip(text: "Free")
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "WHAT YOU CAN DO", size: 10, tracking: 1.4)
                .padding(.bottom, 2)
            BulletRow(
                icon: "rectangle.split.3x1.fill",
                title: "Live departure boards",
                detail: "See the next hour of trains from any station \u{2014} platforms, operators, delays, and cancellations updated live.",
                accent: accent
            )
            BulletRow(
                icon: "tram.fill",
                title: "Full journey detail",
                detail: "Tap a service to see every calling point, carriage count, a route map, and live progress between stops.",
                accent: accent
            )
            BulletRow(
                icon: "mappin",
                title: "Find stations near you",
                detail: "Pinned shortcuts, recent stations, and a search of the full network.",
                accent: accent
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "PERMISSIONS WE'LL ASK FOR", size: 10, tracking: 1.4)
            VStack(spacing: 0) {
                PermissionRow(
                    icon: "mappin",
                    title: "Location",
                    detail: "So we can surface stations near you. We never store your location.",
                    required: false
                )
                PermissionRow(
                    icon: "exclamationmark.triangle",
                    title: "Notifications",
                    detail: "Optional alerts for delays, platform changes, and cancellations on the trains you're tracking.",
                    required: false
                )
                PermissionRow(
                    icon: "wifi",
                    title: "Network access",
                    detail: "Required to fetch live timetable and platform data from National Rail and operator feeds.",
                    required: true,
                    showDivider: false
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Text("Get started")
                        .font(.ui(15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.ink)
                .clipShape(Capsule())
            }

            Text("You can change permissions at any time in Settings.")
        }
        .font(.ui(10.5))
        .foregroundStyle(Theme.inkMute)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }
}

// MARK: - Sub-components

private struct WelcomeChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct BulletRow: View {
    let icon: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(14, weight: .semibold))
                    .tracking(-0.05)
                Text(detail)
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let required: Bool
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.ink.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.ui(13, weight: .semibold))
                        Text(required ? "REQUIRED" : "OPTIONAL")
                            .font(.mono(9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(required ? Theme.cream : Theme.inkSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(required ? Theme.ink : Theme.ink.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(detail)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .overlay(Theme.line)
            }
        }
    }
}
