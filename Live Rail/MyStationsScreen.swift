import SwiftUI
import CoreLocation
import UIKit

/// Dedicated browse-and-manage view for stations: favourites, nearby, and
/// recents in full. The home screen keeps only a compact favourites chip
/// row and the door to here, so its dashboard stays glanceable.
struct MyStationsScreen: View {
    let accent: Color
    let onPickStation: (Station) -> Void
    let onBack: () -> Void

    @State private var locationManager = LocationManager()
    @State private var favouriteStore = FavouriteStationsStore()
    @State private var recentStore = RecentStationsStore()
    @State private var nearbyStations: [Station] = []
    @State private var nearbyDidLoad = false
    @State private var nearbyError = false
    @State private var nearbyTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    favouritesSection
                    nearbySection
                    if !recentStore.stations.isEmpty {
                        recentSection
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
        .task {
            if locationManager.hasPermission {
                if let coord = locationManager.location {
                    if !nearbyDidLoad {
                        fetchNearby(lat: coord.latitude, lng: coord.longitude)
                    }
                } else {
                    locationManager.requestLocation()
                }
            } else {
                locationManager.requestPermission()
            }
        }
        .onChange(of: locationManager.location) { _, coord in
            if let coord, !nearbyDidLoad {
                fetchNearby(lat: coord.latitude, lng: coord.longitude)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            IconButton(systemName: "chevron.left", size: 14, action: onBack)
            Spacer()
            Text("MY STATIONS")
                .font(.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.cream)
    }

    // MARK: - Favourites

    private var favouritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favourites")
                    .font(.display(22))
                    .tracking(-0.2)
                Spacer()
                if !favouriteStore.stations.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text("\(favouriteStore.stations.count) saved")
                            .font(.mono(10, weight: .semibold))
                            .tracking(0.4)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accent)
                    .clipShape(Capsule())
                }
            }
            if favouriteStore.stations.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "star")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.bottom, 2)
                    Text("No favourites yet")
                        .font(.display(18))
                    Text("Tap the star on any station to keep it here")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                StationListCard(
                    stations: favouriteStore.stations,
                    style: .favourite,
                    accent: accent,
                    favouriteStore: favouriteStore,
                    onPick: pick
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Nearby stations")
                    .font(.display(22))
                    .tracking(-0.2)
                Text("Based on your location")
                    .font(.mono(11, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkMute)
            }

            if !locationManager.hasPermission {
                locationPrompt
            } else if nearbyError {
                nearbyErrorCard
            } else if !nearbyDidLoad {
                loadingCard
            } else if nearbyStations.isEmpty {
                VStack(spacing: 4) {
                    Text("No stations nearby")
                        .font(.display(18))
                    Text("Try searching by name or code")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                StationListCard(
                    stations: nearbyStations,
                    style: .nearby,
                    accent: accent,
                    favouriteStore: favouriteStore,
                    onPick: pick
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    private var locationPrompt: some View {
        Button {
            if locationManager.isDenied {
                // The system prompt can't be shown again after a denial —
                // send the user to the app's page in Settings instead.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } else {
                locationManager.requestPermission()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationManager.isDenied ? "Location is off" : "Enable location")
                        .font(.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(locationManager.isDenied ? "Open Settings to allow location access" : "Find stations near you")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text("Finding nearby stations...")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var nearbyErrorCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkMute)
                .padding(.bottom, 2)
            Text("Couldn't load nearby stations")
                .font(.display(18))
            Text("Check your connection and try again")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
            Button {
                retryNearby()
            } label: {
                Text("Try again")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.display(22))
                .tracking(-0.2)
            StationListCard(
                stations: recentStore.stations,
                style: .recent,
                accent: accent,
                favouriteStore: favouriteStore,
                onPick: pick
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    // MARK: - Actions & data

    private func pick(_ station: Station) {
        recentStore.add(station)
        onPickStation(station)
    }

    private func fetchNearby(lat: Double, lng: Double) {
        nearbyTask?.cancel()
        nearbyError = false
        nearbyTask = Task {
            do {
                let wrapper = try await APIClient.shared.getNearbyStations(lat: lat, lng: lng, limit: 5)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    nearbyStations = (wrapper.stations ?? []).map { Station(from: $0) }
                    nearbyDidLoad = true
                    nearbyError = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                nearbyStations = []
                nearbyDidLoad = false
                nearbyError = true
            }
        }
    }

    private func retryNearby() {
        if let coord = locationManager.location {
            fetchNearby(lat: coord.latitude, lng: coord.longitude)
        } else {
            locationManager.requestLocation()
        }
    }
}
