import SwiftUI

/// Pure selection logic for re-route suggestions, kept off the view so the
/// filtering rules are inspectable in one place.
enum AlternativeFinder {
    struct Alternative: Identifiable {
        let service: BoardService
        /// Best-known arrival at the journey's destination, from the board's
        /// inline calling points; nil when the backend served a plain board
        /// row without details.
        let arrivalTime: String?

        var id: String { service.serviceId }
    }

    /// Picks up to `max` viable alternatives from a destination-filtered
    /// board: drops the disrupted service itself and anything cancelled.
    /// Board order is already soonest-first, so order is preserved.
    ///
    /// `serverFiltered` is whether the backend confirmed applying the
    /// destination filter (it echoes `filterCrs` back). When it did, a
    /// service is trusted to call at the destination unless its inline
    /// calling points prove otherwise; when it didn't, only services that
    /// provably serve the destination survive — an unfiltered board must
    /// never be passed off as alternatives.
    static func pick(
        from services: [BoardService],
        excludingServiceId: String,
        destinationCrs: String,
        serverFiltered: Bool,
        max: Int = 3
    ) -> [Alternative] {
        services
            .filter { $0.serviceId != excludingServiceId }
            .filter { !$0.isCancelled && $0.status != "cancelled" }
            .filter { serves(destinationCrs, service: $0, trustedWhenUnknown: serverFiltered) }
            .prefix(max)
            .map { Alternative(service: $0, arrivalTime: arrival(at: destinationCrs, in: $0)) }
    }

    /// Whether a service serves the destination: terminates there, or its
    /// inline calling points include it. With no calling points to check,
    /// falls back to `trustedWhenUnknown`.
    static func serves(_ crs: String, service: BoardService, trustedWhenUnknown: Bool) -> Bool {
        if service.destinationCrs == crs { return true }
        guard let cps = service.subsequentCallingPoints, !cps.isEmpty else {
            return trustedWhenUnknown
        }
        return cps.contains { $0.crs == crs }
    }

    /// Arrival time at the destination: actual, else live expected, else
    /// scheduled — mirroring the fastest-departures tiles.
    static func arrival(at crs: String, in service: BoardService) -> String? {
        guard let cp = service.subsequentCallingPoints?.first(where: { $0.crs == crs })
        else { return nil }
        if let actual = cp.actualTime, TimeFormat.parseClockTime(actual) != nil { return actual }
        if let expected = cp.expectedTime, let live = TimeFormat.parseClockTime(expected) { return live }
        return cp.scheduledTime
    }
}

/// "Alternative trains" card shown on a cancelled or badly delayed journey:
/// the next direct services from the user's boarding station that call at
/// the journey's destination. Tapping a row swaps the journey screen to
/// that train via `onSelectTrain`.
struct AlternativesSection: View {
    let boardingStation: Station
    let destinationCrs: String
    let destinationName: String
    let excludedServiceId: String
    let accent: Color
    let onSelectTrain: (Train) -> Void

    @State private var alternatives: [AlternativeFinder.Alternative] = []
    /// Two-leg fallback, populated only when no direct alternative exists —
    /// a stranded passenger's next-best option.
    @State private var transferOptions: [TransferOption] = []
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
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .task(id: boardingStation.code + ":" + destinationCrs) {
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text("ALTERNATIVE TRAINS")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
            }
            Text("Next direct trains from \(boardingStation.name) to \(destinationName.decodingHTMLEntities())")
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.ink.opacity(0.06))
                        .frame(height: 44)
                        .shimmer()
                }
            }
        } else if alternatives.isEmpty && !transferOptions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No direct trains — via a change:")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkSoft)
                ForEach(transferOptions) { option in
                    TransferOptionRow(option: option, onSelectTrain: onSelectTrain)
                }
            }
        } else if alternatives.isEmpty {
            Text(loadError ?? "No direct alternatives found right now — check the departure board for connections.")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 6) {
                ForEach(alternatives) { alternative in
                    row(alternative)
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ alternative: AlternativeFinder.Alternative) -> some View {
        let service = alternative.service
        let depart = TimeFormat.parseClockTime(service.expectedTime) ?? service.scheduledTime
        let duration = alternative.arrivalTime.flatMap {
            TimeFormat.journeyDuration(from: depart, to: $0)
        }

        return Button {
            onSelectTrain(Train(from: service))
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(depart)
                            .font(.mono(15, weight: .semibold))
                            .foregroundStyle(service.status == "delayed" ? Theme.delayedText : Theme.ink)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkMute)
                        Text(alternative.arrivalTime ?? "—")
                            .font(.mono(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if let duration {
                            Text(duration)
                                .font(.mono(10, weight: .medium))
                                .foregroundStyle(Theme.inkMute)
                        }
                    }
                    Text("to \(service.destination.decodingHTMLEntities())")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(service.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                if let platform = service.platform, !platform.isEmpty {
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

    // MARK: - Load

    private func load() async {
        guard !destinationCrs.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        do {
            let board = try await APIClient.shared.getBoard(
                crs: boardingStation.code,
                filterCrs: destinationCrs
            )
            let found = AlternativeFinder.pick(
                from: board.services,
                excludingServiceId: excludedServiceId,
                destinationCrs: destinationCrs,
                serverFiltered: board.filterCrs != nil
            )
            // No direct option left — try a two-leg route before giving up.
            var transfers: [TransferOption] = []
            if found.isEmpty {
                transfers = (try? await TransferPlanner.fetchOptions(
                    from: boardingStation.code,
                    destinationCrs: destinationCrs
                )) ?? []
                transfers.removeAll { $0.leg1.serviceId == excludedServiceId }
            }
            withAnimation(.easeOut(duration: 0.3)) {
                alternatives = found
                transferOptions = transfers
            }
        } catch {
            loadError = "Couldn't load alternatives — check the departure board."
            alternatives = []
            transferOptions = []
        }
        isLoading = false
    }
}
