import SwiftUI

/// Full network-health view: summary stats, disruption alerts at the
/// user's favourite stations, and per-operator service indicators with
/// expandable detail. Replaces the old NetworkStatusSheet.
struct DisruptionsScreen: View {
    let accent: Color
    let onBack: () -> Void

    @State private var indicators: [TOCIndicator] = []
    @State private var indicatorsLoaded = false
    @State private var loadError = false
    @State private var expandedTOC: String?
    @State private var favouriteStore = FavouriteStationsStore()
    @State private var stationAlerts: [StationDisruptionsResponse] = []
    @State private var stationsChecked = false

    private var disrupted: [TOCIndicator] {
        indicators.filter { $0.status != "Good service" }
    }

    private var healthy: [TOCIndicator] {
        indicators.filter { $0.status == "Good service" }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if loadError {
                        errorCard
                    } else if !indicatorsLoaded {
                        loadingCard
                    } else {
                        summaryHeader
                        if !favouriteStore.stations.isEmpty {
                            favouriteAlertsSection
                        }
                        if !disrupted.isEmpty {
                            operatorSection("Disruptions", tocs: disrupted, expandable: true)
                        }
                        operatorSection("Good service", tocs: healthy, expandable: false)
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            IconButton(systemName: "chevron.left", size: 14, action: onBack)
            Spacer()
            Text("DISRUPTIONS")
                .font(.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.cream)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Text("\(indicators.count)")
                .font(.display(42))
                .tracking(-1)
            VStack(alignment: .leading, spacing: 0) {
                Text("operators")
                Text("tracked")
            }
            .font(.mono(11))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
            Spacer()
            if disrupted.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("All clear")
                        .font(.mono(11, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(Theme.perfGood)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.perfGood.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Text("\(disrupted.count) disrupted")
                    .font(.mono(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.delayedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.warn.opacity(0.3))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Favourite station alerts

    @ViewBuilder
    private var favouriteAlertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR STATIONS")
                .font(.mono(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 18)

            if !stationsChecked {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.ink)
                    Text("Checking your favourite stations...")
                        .font(.ui(13))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18)
            } else if stationAlerts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.perfGood)
                    Text("No alerts at your favourite stations")
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18)
            } else {
                VStack(spacing: 10) {
                    ForEach(stationAlerts, id: \.crs) { alert in
                        stationAlertCard(alert)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 20)
    }

    private func stationAlertCard(_ alert: StationDisruptionsResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(alert.crs)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.cream)
                    .frame(width: 32, height: 26)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(alert.stationName)
                    .font(.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(alert.disruptions.count) alert\(alert.disruptions.count == 1 ? "" : "s")")
                    .font(.mono(10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.delayedText)
            }
            ForEach(alert.disruptions.prefix(3)) { disruption in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(severityColor(disruption.severity))
                            .frame(width: 6, height: 6)
                        Text(disruption.title)
                            .font(.ui(12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }
                    Text(disruption.description)
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high", "severe", "major":
            return Theme.cancelledText
        case "normal", "medium", "minor":
            return Theme.delayedText
        default:
            return Theme.inkMute
        }
    }

    // MARK: - Operators

    private func operatorSection(_ title: String, tocs: [TOCIndicator], expandable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(tocs.enumerated()), id: \.element.tocCode) { index, toc in
                    operatorRow(toc, expandable: expandable)
                        .overlay(alignment: .bottom) {
                            if index < tocs.count - 1 {
                                Divider().overlay(Theme.line)
                            }
                        }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 18)
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func operatorRow(_ toc: TOCIndicator, expandable: Bool) -> some View {
        let brand = OperatorBrand.brand(for: toc.tocCode)
        let isExpanded = expandedTOC == toc.tocCode
        let hasDetail = expandable && (toc.additionalInfo?.isEmpty == false || !toc.statusDescription.isEmpty)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasDetail else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedTOC = isExpanded ? nil : toc.tocCode
                }
            } label: {
                HStack(spacing: 10) {
                    Text(toc.tocCode)
                        .font(.mono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(brand.fg)
                        .frame(width: 32, height: 26)
                        .background(brand.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toc.tocName)
                            .font(.ui(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(toc.status)
                            .font(.ui(11))
                            .foregroundStyle(toc.status == "Good service" ? Theme.onTimeSub : Theme.delayedText)
                    }
                    Spacer()
                    if hasDetail {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkMute)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !toc.statusDescription.isEmpty {
                        Text(toc.statusDescription)
                            .font(.ui(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if let info = toc.additionalInfo, !info.isEmpty {
                        Text(info)
                            .font(.ui(11))
                            .foregroundStyle(Theme.inkMute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Loading & error

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text("Checking the network...")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var errorCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkMute)
                .padding(.bottom, 2)
            Text("Couldn't load network status")
                .font(.display(18))
            Text("Check your connection and try again")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
            Button {
                Task { await load() }
            } label: {
                Text("Try again")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Data

    private func load() async {
        loadError = false
        do {
            indicators = try (await APIClient.shared.getTOCIndicators()).indicators
            indicatorsLoaded = true
        } catch {
            if !indicatorsLoaded { loadError = true }
        }

        // Check each favourite station for live disruption messages; only
        // stations with alerts are shown. Failures degrade to "no alert"
        // rather than blocking the screen.
        let favourites = Array(favouriteStore.stations.prefix(6))
        guard !favourites.isEmpty else {
            stationsChecked = true
            return
        }
        var alerts: [StationDisruptionsResponse] = []
        await withTaskGroup(of: StationDisruptionsResponse?.self) { group in
            for station in favourites {
                group.addTask {
                    try? await APIClient.shared.getStationDisruptions(crs: station.code)
                }
            }
            for await result in group {
                if let result, !result.disruptions.isEmpty {
                    alerts.append(result)
                }
            }
        }
        stationAlerts = alerts.sorted { $0.stationName < $1.stationName }
        stationsChecked = true
    }
}
