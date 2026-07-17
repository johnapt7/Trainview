import Foundation

@Observable
final class FavouriteStationsStore {
    /// One instance app-wide: the tab bar keeps several screens alive at
    /// once, so they must observe the same list rather than each loading
    /// their own snapshot from UserDefaults.
    static let shared = FavouriteStationsStore()

    private static let key = "favouriteStations"

    var stations: [Station] = []

    private init() {
        load()
    }

    func contains(_ station: Station) -> Bool {
        stations.contains { $0.code == station.code }
    }

    func toggle(_ station: Station) {
        if contains(station) {
            stations.removeAll { $0.code == station.code }
        } else {
            stations.append(station)
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
