import SwiftUI

/// Horizontal row of "fastest to X" tiles, one per favourite destination.
/// Sourced from `GET /api/board/{origin}/fastest?to=...`. Tiles render an
/// arriving-soonest service per destination; unavailable destinations get a
/// muted tile with the upstream reason.
struct FastestDeparturesCard: View {
    let originCrs: String
    let originName: String
    let favourites: [Station]
    let accent: Color
    let onOpenTrain: (Train) -> Void

    @State private var results: [FastestDeparturesResult] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var refetchKey: String {
        originCrs + ":" + favourites.map(\.code).joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .task(id: refetchKey) {
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text("FASTEST FROM \(originName.uppercased())")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
            }
            Text("Train arriving soonest at each destination")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            skeletonRow
        } else if loadError != nil && results.isEmpty {
            Text("Couldn't load fastest departures")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 18)
        } else if !results.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(results) { result in
                        tile(for: result)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var skeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<min(favourites.count, 3), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.ink.opacity(0.06))
                        .frame(width: 170, height: 132)
                        .shimmer()
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Tile

    @ViewBuilder
    private func tile(for result: FastestDeparturesResult) -> some View {
        if let service = result.service {
            availableTile(result: result, service: service)
        } else {
            unavailableTile(result: result)
        }
    }

    private func availableTile(result: FastestDeparturesResult, service: BoardService) -> some View {
        Button {
            onOpenTrain(Train(from: service))
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(result.destinationName.decodingHTMLEntities())
                    .font(.display(15))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                timesRow(for: service, result: result)

                if let duration = journeyDurationString(service: service, result: result) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.inkMute)
                        Text("\(duration) journey")
                            .font(.mono(10, weight: .medium))
                            .foregroundStyle(Theme.inkMute)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(service.operatorCode)
                        .font(.mono(9, weight: .bold))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if let platform = service.platform, !platform.isEmpty {
                        Text("Platform \(platform)")
                            .font(.mono(10, weight: .medium))
                            .foregroundStyle(Theme.inkMute)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(width: 170, height: 132, alignment: .topLeading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor(for: service), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func timesRow(for service: BoardService, result: FastestDeparturesResult) -> some View {
        let depart = displayDeparture(service)
        let arrive = arrivalString(for: result)

        return HStack(spacing: 5) {
            Text(depart)
                .font(.mono(15, weight: .semibold))
                .foregroundStyle(departureColor(for: service))
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
            Text(arrive ?? "—")
                .font(.mono(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    private func unavailableTile(result: FastestDeparturesResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.destinationName.decodingHTMLEntities())
                .font(.display(15))
                .tracking(-0.1)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(result.unavailableReason ?? "No services")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 170, height: 132, alignment: .topLeading)
        .background(Theme.ink.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Styling helpers

    private func borderColor(for service: BoardService) -> Color {
        switch service.status {
        case "cancelled": return Theme.cancelledText.opacity(0.4)
        case "delayed":   return Theme.delayedText.opacity(0.4)
        default:          return accent.opacity(0.45)
        }
    }

    private func departureColor(for service: BoardService) -> Color {
        switch service.status {
        case "cancelled": return Theme.cancelledText
        case "delayed":   return Theme.delayedText
        default:          return Theme.ink
        }
    }

    // MARK: - Time helpers

    /// Prefer the live HH:MM departure when LDBWS gives us one; fall back to
    /// scheduled. "On time", "Delayed", "Cancelled" don't parse as clock
    /// times and get dropped here.
    private func displayDeparture(_ service: BoardService) -> String {
        if let live = parseClockTime(service.expectedTime) { return live }
        return service.scheduledTime
    }

    private func arrivalString(for result: FastestDeparturesResult) -> String? {
        let cp = result.callingPoints.first(where: { $0.crs == result.destinationCrs })
            ?? result.callingPoints.last
        guard let cp else { return nil }
        if let actual = cp.actualTime, parseClockTime(actual) != nil { return actual }
        if let expected = cp.expectedTime, let live = parseClockTime(expected) { return live }
        return cp.scheduledTime
    }

    private func parseClockTime(_ s: String) -> String? {
        TimeFormat.parseClockTime(s)
    }

    private func journeyDurationString(service: BoardService, result: FastestDeparturesResult) -> String? {
        let depart = displayDeparture(service)
        guard let arrive = arrivalString(for: result) else { return nil }
        return TimeFormat.journeyDuration(from: depart, to: arrive)
    }

    // MARK: - Load

    private func load() async {
        guard !favourites.isEmpty else {
            results = []
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let destinations = Array(favourites.prefix(10)).map { $0.code }
            let response = try await APIClient.shared.getFastestDepartures(
                from: originCrs,
                to: destinations
            )
            withAnimation(.easeOut(duration: 0.3)) {
                results = response.results
            }
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? "Could not load"
            results = []
        }
    }
}
