import Foundation

@Observable
final class RecentStationsStore {
    /// One instance app-wide — see HomeStationsStore.shared.
    static let shared = RecentStationsStore()

    private static let key = "recentStations"
    private static let maxRecents = 5

    var stations: [Station] = []

    private init() {
        load()
    }

    func add(_ station: Station) {
        stations.removeAll { $0.code == station.code }
        stations.insert(station, at: 0)
        if stations.count > Self.maxRecents {
            stations = Array(stations.prefix(Self.maxRecents))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Station].self, from: data) else {
            return
        }
        stations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
