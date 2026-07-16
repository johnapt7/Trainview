import SwiftUI

/// Dedicated browse-and-manage view for the user's stations: favourites
/// and recents in full, with a note on how the lists fill up. Nearby
/// stations live on the home screen, where location context matters.
struct MyStationsScreen: View {
    let accent: Color
    let onPickStation: (Station) -> Void
    let onBack: () -> Void

    @State private var favouriteStore = FavouriteStationsStore()
    @State private var recentStore = RecentStationsStore()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    favouritesSection
                    if !recentStore.stations.isEmpty {
                        recentSection
                    }
                    howToNote
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
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

    // MARK: - How it fills up

    private var howToNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 1)
            Text("Tap the \(Image(systemName: "star")) star on any station — in search results, nearby stations, or the lists here — to add it to your favourites. Stations you open appear under Recent automatically.")
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    // MARK: - Actions

    private func pick(_ station: Station) {
        recentStore.add(station)
        onPickStation(station)
    }
}
