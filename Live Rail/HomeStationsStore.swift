import Foundation
import SwiftUI

@Observable
final class HomeStationsStore {
    /// One instance app-wide, same reasoning as FavouriteStationsStore.
    static let shared = HomeStationsStore()

    private static let key = "homeStations"

    /// Matches the server-side cap so a full sync can never be rejected.
    static let maxStations = 20

    var stations: [Station] = []

    private init() {
        load()
    }

    func contains(_ station: Station) -> Bool {
        stations.contains { $0.code == station.code }
    }

    func add(_ station: Station) {
        guard !contains(station), stations.count < Self.maxStations else { return }
        stations.append(station)
        save()
    }

    func remove(_ station: Station) {
        stations.removeAll { $0.code == station.code }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Applies a server pull without re-triggering a push (fromSync: true),
    /// or replaces wholesale from local UI with a push (fromSync: false).
    func replaceAll(_ newStations: [Station], fromSync: Bool) {
        stations = newStations
        guard let data = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        if !fromSync {
            AccountStore.shared.noteStationsChanged()
        }
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
        AccountStore.shared.noteStationsChanged()
    }
}
