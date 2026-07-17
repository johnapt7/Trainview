import SwiftUI

/// Full network-health view: summary stats, disruption alerts at the
/// user's favourite stations, and per-operator service indicators with
/// expandable detail. Replaces the old NetworkStatusSheet.
struct DisruptionsScreen: View {
    let accent: Color

    @State private var indicators: [TOCIndicator] = []
    @State private var indicatorsLoaded = false
    @State private var loadError = false
    @State private var favouriteStore = FavouriteStationsStore.shared
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
                            operatorSection("Disruptions", tocs: disrupted, disrupted: true)
                        }
                        operatorSection("Good service", tocs: healthy, disrupted: false)
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
        Text("DISRUPTIONS")
            .font(.mono(11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
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
                Text(stationDisplayName(alert))
                    .font(.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                let alertCount = alert.disruptions.count + (alert.announcements?.count ?? 0)
                Text("\(alertCount) alert\(alertCount == 1 ? "" : "s")")
                    .font(.mono(10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.delayedText)
            }
            ForEach(Array((alert.announcements ?? []).prefix(3).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.top, 3)
                    Text(message.decodingHTMLEntities())
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(4)
                }
            }
            ForEach(alert.disruptions.prefix(3)) { disruption in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(severityColor(disruption.severity))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(disruption.title.decodingHTMLEntities())
                            .font(.ui(12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The feed's title usually embeds the description
                    // ("Operator: message") — only repeat it when it adds
                    // something the title doesn't already say.
                    if !disruption.description.isEmpty,
                       !disruption.title.contains(disruption.description) {
                        Text(disruption.description.decodingHTMLEntities())
                            .font(.ui(11))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(4)
                            .padding(.leading, 12)
                    }
                    if let url = disruptionLink(disruption) {
                        travelNewsLink(url, label: disruption.customerAdvice)
                            .padding(.leading, 12)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// The backend echoes the CRS code back as `stationName`, so resolve the
    /// full name from the favourite it came from.
    private func stationDisplayName(_ alert: StationDisruptionsResponse) -> String {
        favouriteStore.stations.first { $0.code == alert.crs }?.name ?? alert.stationName
    }

    private func disruptionLink(_ disruption: StationDisruption) -> URL? {
        guard let raw = disruption.detailURL, !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
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

    private func operatorSection(_ title: String, tocs: [TOCIndicator], disrupted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(tocs.enumerated()), id: \.element.tocCode) { index, toc in
                    operatorRow(toc, disrupted: disrupted)
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

    /// The feed reports "Custom" when an operator writes its own message
    /// instead of picking a canned status — the real wording is in the
    /// description, so surface that rather than the literal "Custom".
    private func displayStatus(_ toc: TOCIndicator) -> String {
        guard toc.status == "Custom" else { return toc.status }
        return toc.statusDescription.isEmpty ? "Disruption" : toc.statusDescription
    }

    /// Everything worth knowing sits directly in the row — no disclosure.
    /// Disrupted rows show the full status message plus a link to the
    /// operator's live travel news page when the backend provides one.
    @ViewBuilder
    private func operatorRow(_ toc: TOCIndicator, disrupted: Bool) -> some View {
        let brand = OperatorBrand.brand(for: toc.tocCode)
        let statusLine = displayStatus(toc)

        HStack(alignment: .top, spacing: 10) {
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
                Text(statusLine.decodingHTMLEntities())
                    .font(.ui(11))
                    .foregroundStyle(disrupted ? Theme.delayedText : Theme.onTimeSub)
                    .lineLimit(disrupted ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if disrupted, !toc.statusDescription.isEmpty, toc.statusDescription != statusLine {
                    Text(toc.statusDescription.decodingHTMLEntities())
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if disrupted, let url = detailLink(toc) {
                    travelNewsLink(url, label: toc.additionalInfo)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// A valid, tappable detail URL — nil hides the link entirely, so the
    /// row degrades gracefully while the backend doesn't send one.
    private func detailLink(_ toc: TOCIndicator) -> URL? {
        guard let raw = toc.detailURL, !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private func travelNewsLink(_ url: URL, label: String?) -> some View {
        let text = (label?.isEmpty == false) ? label! : "Latest travel news"
        return Link(destination: url) {
            HStack(spacing: 4) {
                Text(text.decodingHTMLEntities())
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.ui(11, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .underline()
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
                // A station earns a card for incidents OR announcements —
                // the board screen shows both, so this screen must too.
                if let result,
                   !result.disruptions.isEmpty || !(result.announcements ?? []).isEmpty {
                    alerts.append(result)
                }
            }
        }
        stationAlerts = alerts.sorted { $0.stationName < $1.stationName }
        stationsChecked = true
    }
}
