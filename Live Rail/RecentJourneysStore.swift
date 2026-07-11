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
    private static let key = "recentJourneys"
    private static let maxJourneys = 4

    var journeys: [RecentJourney] = []

    init() {
        load()
    }

    func add(origin: Station, destination: Station) {
        guard origin.code != destination.code else { return }
        let journey = RecentJourney(origin: origin, destination: destination)
        journeys.removeAll { $0.id == journey.id }
        journeys.insert(journey, at: 0)
        if journeys.count > Self.maxJourneys {
            journeys = Array(journeys.prefix(Self.maxJourneys))
        }
        save()
    }

    func remove(_ journey: RecentJourney) {
        journeys.removeAll { $0.id == journey.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([RecentJourney].self, from: data) else {
            return
        }
        journeys = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(journeys) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
