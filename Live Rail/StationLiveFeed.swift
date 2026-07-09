import Foundation

/// Listens to the backend WebSocket for live station updates and fires a
/// coalesced callback whenever Darwin pushes new data for the subscribed
/// station. The REST board stays the source of truth — this only tells the
/// board *when* to re-fetch, so a platform change lands in seconds instead
/// of waiting for the next poll or a pull-to-refresh.
@MainActor
final class StationLiveFeed {
    /// Same host as APIClient, but the WebSocket endpoint lives at the root
    /// (`/ws`), not under `/api`.
    private static let url = URL(string: "wss://network-rail-adapter-production.up.railway.app/ws")!

    /// Minimum gap between refresh callbacks. Busy stations emit many
    /// station:update messages per minute; one board re-fetch per window
    /// is plenty, and the periodic fallback timer catches anything dropped.
    private static let notifyInterval: TimeInterval = 8

    private let crs: String
    private let onUpdate: () -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var closed = true
    private var lastNotified = Date.distantPast

    init(crs: String, onUpdate: @escaping () -> Void) {
        self.crs = crs
        self.onUpdate = onUpdate
    }

    func connect() {
        guard closed else { return }
        closed = false
        reconnectAttempts = 0
        open()
    }

    func disconnect() {
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func open() {
        guard !closed else { return }
        let task = URLSession.shared.webSocketTask(with: Self.url)
        self.task = task
        task.resume()

        let subscribe = #"{"action":"subscribe","topic":"crs:\#(crs)"}"#
        task.send(.string(subscribe)) { _ in }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                handle(message)
                reconnectAttempts = 0
            } catch {
                if !closed { scheduleReconnect() }
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message else { return }
        // The hub batches queued messages into a single frame separated by
        // newlines, so a frame can carry several JSON payloads.
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = json["event"] as? String else { continue }
            if event == "station:update" {
                notify()
            }
        }
    }

    private func notify() {
        let now = Date()
        guard now.timeIntervalSince(lastNotified) >= Self.notifyInterval else { return }
        lastNotified = now
        onUpdate()
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.closed else { return }
            self.open()
        }
    }
}
