import SwiftUI

/// Favourites tab: the user's starred stations, one tap to a board.
/// Replaces the old My Stations screen — recents now live on the home
/// screen and nearby always did.
struct FavouritesScreen: View {
    let accent: Color
    let onPickStation: (Station) -> Void

    @State private var favouriteStore = FavouriteStationsStore.shared
    @State private var recentStore = RecentStationsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    favouritesSection
                    howToNote
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
    }

    // MARK: - Top bar

    private var topBar: some View {
        Text("FAVOURITES")
            .font(.mono(11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
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

    // MARK: - How it fills up

    private var howToNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 1)
            Text("Tap the \(Image(systemName: "star")) star on any station — in search results, nearby or recent stations, or the list here — to add it to your favourites.")
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
