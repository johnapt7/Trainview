import SwiftUI

/// A two-leg route: an outgoing train from the origin, a change at a shared
/// calling point, and an incoming train that reaches the destination.
struct TransferOption: Identifiable {
    let leg1: BoardService
    let changeCrs: String
    let changeName: String
    /// Leg 1's arrival time at the change station (HH:MM).
    let leg1ArrivalAtChange: String
    let leg2: BoardService
    /// Leg 2's departure time from the change station (HH:MM).
    let leg2DepartureAtChange: String
    /// Leg 2's arrival at the destination (HH:MM).
    let arrivalAtDestination: String
    let waitMinutes: Int

    var id: String { leg1.serviceId + "-" + leg2.serviceId }
}

/// Composes two-leg routes from plain boards — there is no journey-planning
/// endpoint. Departures from the origin carry each train's upcoming stops;
/// arrivals at the destination carry each train's previous stops. A station
/// on both lists with enough change time is a valid transfer.
enum TransferPlanner {
    /// Change margins: at least 5 minutes to cross a station, and no more
    /// than 3 hours — beyond that the midnight-wrapped arithmetic is more
    /// likely mispairing days than describing a real connection.
    static let minChangeMinutes = 5
    static let maxChangeMinutes = 180

    static func plan(
        departures: [BoardService],
        arrivals: [BoardService],
        destinationCrs: String,
        minChangeMinutes: Int = TransferPlanner.minChangeMinutes,
        max maxOptions: Int = 3
    ) -> [TransferOption] {
        // Leg-2 candidates: (change crs -> departures from there that reach
        // the destination). Plain rows without calling points can't be
        // matched and drop out here.
        struct Leg2 {
            let service: BoardService
            let departureAtChange: String
            let arrivalAtDestination: String
        }
        var leg2ByChange: [String: [Leg2]] = [:]
        for service in arrivals where !service.isCancelled && service.status != "cancelled" {
            guard let arrival = TimeFormat.parseClockTime(service.expectedTime)
                ?? TimeFormat.parseClockTime(service.scheduledTime) else { continue }
            for cp in service.previousCallingPoints ?? [] where !cp.isCancelled {
                guard let dep = bestTime(cp) else { continue }
                leg2ByChange[cp.crs, default: []].append(
                    Leg2(service: service, departureAtChange: dep, arrivalAtDestination: arrival)
                )
            }
        }
        guard !leg2ByChange.isEmpty else { return [] }

        // Reference point for ordering arrivals across midnight: the first
        // departure on the board.
        let t0 = departures.first.flatMap {
            TimeFormat.parseClockTime($0.expectedTime) ?? TimeFormat.parseClockTime($0.scheduledTime)
        } ?? "00:00"

        var options: [TransferOption] = []
        for leg1 in departures where !leg1.isCancelled && leg1.status != "cancelled" {
            // A train already serving the destination is a direct train,
            // not a transfer.
            guard !AlternativeFinder.serves(destinationCrs, service: leg1, trustedWhenUnknown: false) else { continue }

            var best: TransferOption?
            for cp in leg1.subsequentCallingPoints ?? [] where !cp.isCancelled {
                guard cp.crs != destinationCrs,
                      let arriveChange = bestTime(cp),
                      let connections = leg2ByChange[cp.crs] else { continue }
                for leg2 in connections {
                    guard leg2.service.serviceId != leg1.serviceId,
                          let wait = minutesBetween(arriveChange, leg2.departureAtChange),
                          wait >= minChangeMinutes, wait <= maxChangeMinutes else { continue }
                    let option = TransferOption(
                        leg1: leg1,
                        changeCrs: cp.crs,
                        changeName: cp.station.decodingHTMLEntities(),
                        leg1ArrivalAtChange: arriveChange,
                        leg2: leg2.service,
                        leg2DepartureAtChange: leg2.departureAtChange,
                        arrivalAtDestination: leg2.arrivalAtDestination,
                        waitMinutes: wait
                    )
                    if best == nil || sortKey(option, from: t0) < sortKey(best!, from: t0) {
                        best = option
                    }
                }
            }
            if let best { options.append(best) }
        }

        return Array(options.sorted { sortKey($0, from: t0) < sortKey($1, from: t0) }.prefix(maxOptions))
    }

    /// The two board fetches behind `plan`: origin departures (unfiltered —
    /// a destination-filtered board is empty in exactly the situations this
    /// runs) and destination arrivals.
    static func fetchOptions(from originCrs: String, destinationCrs: String) async throws -> [TransferOption] {
        async let departures = APIClient.shared.getBoard(crs: originCrs)
        async let arrivals = APIClient.shared.getBoard(crs: destinationCrs, type: "arrivals")
        return plan(
            departures: try await departures.services,
            arrivals: try await arrivals.services,
            destinationCrs: destinationCrs
        )
    }

    /// Best-known clock time at a calling point: actual, else live expected,
    /// else scheduled. Darwin's "On time"/"Delayed" strings parse to nil and
    /// fall through.
    static func bestTime(_ cp: CallingPointResponse) -> String? {
        if let actual = cp.actualTime, TimeFormat.parseClockTime(actual) != nil { return actual }
        if let expected = cp.expectedTime, let live = TimeFormat.parseClockTime(expected) { return live }
        return TimeFormat.parseClockTime(cp.scheduledTime)
    }

    /// Minutes from t1 to t2, wrapping forward past midnight.
    static func minutesBetween(_ t1: String, _ t2: String) -> Int? {
        guard let m1 = TimeFormat.minutesOfDay(t1), let m2 = TimeFormat.minutesOfDay(t2) else { return nil }
        var delta = m2 - m1
        if delta < 0 { delta += 24 * 60 }
        return delta
    }

    private static func sortKey(_ option: TransferOption, from t0: String) -> Int {
        minutesBetween(t0, option.arrivalAtDestination) ?? Int.max
    }
}

// MARK: - Row

/// One two-leg route, in the same row idiom as the alternatives card.
/// Tapping hands the leg-1 train to `onSelectTrain` — that's the train the
/// user needs to board first.
struct TransferOptionRow: View {
    let option: TransferOption
    let onSelectTrain: (Train) -> Void

    var body: some View {
        let depart = TimeFormat.parseClockTime(option.leg1.expectedTime) ?? option.leg1.scheduledTime
        let duration = TimeFormat.journeyDuration(from: depart, to: option.arrivalAtDestination)

        Button {
            onSelectTrain(Train(from: option.leg1))
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(depart)
                            .font(.mono(15, weight: .semibold))
                            .foregroundStyle(option.leg1.status == "delayed" ? Theme.delayedText : Theme.ink)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkMute)
                        Text(option.arrivalAtDestination)
                            .font(.mono(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if let duration {
                            Text(duration)
                                .font(.mono(10, weight: .medium))
                                .foregroundStyle(Theme.inkMute)
                        }
                    }
                    Text("change at \(option.changeName) · \(option.waitMinutes) min wait")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(option.leg1.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                if let platform = option.leg1.platform, !platform.isEmpty {
                    Text("Plat. \(platform)")
                        .font(.mono(10, weight: .medium))
                        .foregroundStyle(Theme.inkMute)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.ink.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section

/// "Via a change" card shown when a destination-filtered board has no
/// direct trains. Self-loading, hides its rows when no connection exists
/// within the boards' time window.
struct TransferSection: View {
    let originStation: Station
    let destinationCrs: String
    let destinationName: String
    let accent: Color
    let onSelectTrain: (Train) -> Void

    @State private var options: [TransferOption] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.4), lineWidth: 1)
        )
        .task(id: originStation.code + ":" + destinationCrs) {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text("VIA A CHANGE")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
            }
            Text("Two-train routes from \(originStation.name) to \(destinationName.decodingHTMLEntities())")
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.ink.opacity(0.06))
                        .frame(height: 52)
                        .shimmer()
                }
            }
        } else if options.isEmpty {
            Text(loadError ?? "No connecting routes found in the next couple of hours.")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 6) {
                ForEach(options) { option in
                    TransferOptionRow(option: option, onSelectTrain: onSelectTrain)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let found = try await TransferPlanner.fetchOptions(
                from: originStation.code,
                destinationCrs: destinationCrs
            )
            withAnimation(.easeOut(duration: 0.3)) {
                options = found
            }
        } catch {
            loadError = "Couldn't look up connections."
            options = []
        }
        isLoading = false
    }
}
