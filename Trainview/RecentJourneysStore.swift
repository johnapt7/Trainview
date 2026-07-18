import Foundation

/// An origin→destination pair the user has travelled, recorded whenever they
/// filter a departure board by destination. Powers the one-tap "Your
/// journeys" shortcuts on the home screen.
struct RecentJourney: Identifiable, Codable, Equatable {
    let origin: Station
    let destination: Station

    var id: String { "\(origin.code)-\(destination.code)" }
}

@Observable
final class RecentJourneysStore {
    /// One instance app-wide — see HomeStationsStore.shared.
    static let shared = RecentJourneysStore()

    private static let key = "recentJourneys"
    private static let pinnedKey = "pinnedJourneyIDs"
    /// Cap applies to unpinned recents only; pinned journeys are kept
    /// indefinitely and never evicted by newer searches.
    private static let maxRecents = 4

    var journeys: [RecentJourney] = []
    private(set) var pinnedIDs: Set<String> = []

    /// Home-screen order: pinned journeys first (most recent first within
    /// each group), then unpinned recents.
    var displayJourneys: [RecentJourney] {
        journeys.filter { pinnedIDs.contains($0.id) }
            + journeys.filter { !pinnedIDs.contains($0.id) }
    }

    private init() {
        load()
    }

    func add(origin: Station, destination: Station) {
        guard origin.code != destination.code else { return }
        let journey = RecentJourney(origin: origin, destination: destination)
        journeys.removeAll { $0.id == journey.id }
        journeys.insert(journey, at: 0)
        evictOverflowingRecents()
        save()
    }

    func remove(_ journey: RecentJourney) {
        journeys.removeAll { $0.id == journey.id }
        pinnedIDs.remove(journey.id)
        save()
    }

    func isPinned(_ journey: RecentJourney) -> Bool {
        pinnedIDs.contains(journey.id)
    }

    func togglePin(_ journey: RecentJourney) {
        if pinnedIDs.contains(journey.id) {
            pinnedIDs.remove(journey.id)
            evictOverflowingRecents()
        } else {
            if !journeys.contains(where: { $0.id == journey.id }) {
                journeys.insert(journey, at: 0)
            }
            pinnedIDs.insert(journey.id)
        }
        save()
    }

    private func evictOverflowingRecents() {
        var recentsSeen = 0
        var keep: [RecentJourney] = []
        for journey in journeys {
            if pinnedIDs.contains(journey.id) {
                keep.append(journey)
            } else {
                recentsSeen += 1
                if recentsSeen <= Self.maxRecents {
                    keep.append(journey)
                }
            }
        }
        journeys = keep
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([RecentJourney].self, from: data) {
            journeys = decoded
        }
        if let ids = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            pinnedIDs = Set(ids)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(journeys) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        UserDefaults.standard.set(Array(pinnedIDs), forKey: Self.pinnedKey)
    }
}
