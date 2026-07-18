import SwiftUI

/// One pinned home-station card on the Home screen: the station name and
/// its next few live departures, tappable through to the full board.
struct HomeStationCard: View {
    let station: Station
    let accent: Color
    let onOpen: (Station) -> Void
    let onRemove: (Station) -> Void
    /// Changing this id forces a refetch (foreground refresh).
    let refreshID: UUID

    @State private var services: [BoardService]?
    @State private var loadFailed = false

    private static let rowCount = 3

    var body: some View {
        Button {
            onOpen(station)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove(station)
            } label: {
                Label("Remove from home", systemImage: "minus.circle")
            }
        }
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String { "\(station.code)-\(refreshID.uuidString)" }

    private var header: some View {
        HStack(spacing: 10) {
            Text(station.code)
                .font(.mono(11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.display(18))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("NEXT DEPARTURES")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMute)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let services {
            if services.isEmpty {
                Text("No departures right now")
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkMute)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 8) {
                    ForEach(services) { service in
                        departureRow(service)
                    }
                }
            }
        } else if loadFailed {
            Text("Couldn't load departures — tap to open the board")
                .font(.ui(12))
                .foregroundStyle(Theme.inkMute)
                .padding(.vertical, 2)
        } else {
            HStack {
                Spacer()
                ProgressView()
                    .tint(Theme.inkMute)
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private func departureRow(_ service: BoardService) -> some View {
        HStack(spacing: 10) {
            Text(displayTime(service))
                .font(.mono(13, weight: .semibold))
                .foregroundStyle(timeColor(service))
                .strikethrough(service.isCancelled)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.destination)
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let note = statusNote(service) {
                    Text(note)
                        .font(.ui(10))
                        .foregroundStyle(timeColor(service))
                }
            }
            Spacer()
            if let platform = service.platform {
                Text("Plat \(platform)")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(Theme.inkMute)
            }
        }
    }

    /// Live time when the feed gives one, else scheduled.
    private func displayTime(_ service: BoardService) -> String {
        if let live = TimeFormat.parseClockTime(service.expectedTime) { return live }
        return service.scheduledTime
    }

    private func timeColor(_ service: BoardService) -> Color {
        if service.isCancelled { return Theme.cancelledText }
        if isDelayed(service) { return Theme.delayedText }
        return Theme.ink
    }

    private func isDelayed(_ service: BoardService) -> Bool {
        if let live = TimeFormat.parseClockTime(service.expectedTime) {
            return live != service.scheduledTime
        }
        return service.expectedTime.lowercased() == "delayed"
    }

    private func statusNote(_ service: BoardService) -> String? {
        if service.isCancelled { return "Cancelled" }
        if isDelayed(service) { return "Sched \(service.scheduledTime)" }
        return nil
    }

    private func load() async {
        loadFailed = false
        do {
            let board = try await APIClient.shared.getBoard(crs: station.code, rows: 10)
            withAnimation(.easeOut(duration: 0.2)) {
                services = Array(board.services.prefix(Self.rowCount))
            }
        } catch {
            if services == nil { loadFailed = true }
        }
    }
}
