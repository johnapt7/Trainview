import SwiftUI
import CoreLocation

struct HomeScreen: View {
    let accent: Color
    let onPickStation: (Station) -> Void

    @State private var query = ""
    @State private var searchResults: [Station]?
    @State private var searchError: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbyStations: [Station] = []
    @State private var nearbyDidLoad = false
    @State private var nearbyError = false
    @State private var nearbyTask: Task<Void, Never>?
    @State private var locationManager = LocationManager()
    @State private var recentStore = RecentStationsStore()
    @State private var favouriteStore = FavouriteStationsStore()
    @State private var showFAQ = false
    @State private var tocIndicators: [TOCIndicator] = []
    @State private var showNetworkStatus = false
    @FocusState private var searchFocused: Bool

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            pinnedTopBar
            if !searchFocused && query.isEmpty {
                greetingHeader
            }
            searchBar
                .padding(.horizontal, 18)
                .padding(.top, searchFocused || !query.isEmpty ? 4 : 0)
                .padding(.bottom, 10)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !tocIndicators.isEmpty {
                        networkStatusRow
                    }
                    if let results = searchResults {
                        searchResultsSection(results)
                    } else {
                        if !favouriteStore.stations.isEmpty {
                            favouritesSection
                        }
                        nearbySection
                        if !recentStore.stations.isEmpty {
                            recentSection
                        }
                    }
                    footerView
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeOut(duration: 0.2), value: searchFocused)
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
        .onChange(of: query) { _, newValue in
            debounceSearch(newValue)
        }
        .sheet(isPresented: $showFAQ) {
            FAQSheet()
        }
        .sheet(isPresented: $showNetworkStatus) {
            NetworkStatusSheet(indicators: tocIndicators)
        }
        .task {
            tocIndicators = (try? await APIClient.shared.getTOCIndicators())?.indicators ?? []
        }
    }

    // MARK: - Data fetching

    private func debounceSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = nil
            searchError = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            do {
                let results = try await APIClient.shared.searchStations(query: trimmed, limit: 10)
                guard !Task.isCancelled else { return }
                searchError = false
                searchResults = results.map { Station(from: $0) }
            } catch {
                guard !Task.isCancelled else { return }
                searchError = true
                searchResults = []
            }
        }
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

    private func pickStation(_ station: Station) {
        recentStore.add(station)
        onPickStation(station)
    }

    // MARK: - Header

    /// Sits outside the ScrollView so it stays visible while content scrolls
    /// underneath, and clears the status bar / Dynamic Island via the top
    /// padding (matching the offset used elsewhere in the app).
    private var pinnedTopBar: some View {
        HStack {
            Color.clear.frame(width: 38, height: 38)
            Spacer()
            Text("RAIL BOARD")
                .font(.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            Spacer()
            IconButton(systemName: "info.circle", size: 14) { showFAQ = true }
        }
        .padding(.horizontal, 18)
        .padding(.top, 62)
        .padding(.bottom, 10)
        .background(Theme.cream)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting.uppercased())
                .font(.mono(11))
                .tracking(1.5)
                .foregroundStyle(Theme.inkMute)
            Text("Where are you\ntravelling from\(Text("?").foregroundColor(Theme.inkMute))")
                .font(.display(36, weight: .medium))
                .tracking(-1.3)
                .lineSpacing(-4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .offset(y: -10)))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(searchFocused || !query.isEmpty ? Theme.ink : Theme.inkMute)
            TextField("Search by station name or code", text: $query)
                .font(.ui(14))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.ink.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(14)
        .background(searchFocused || !query.isEmpty ? Color(hex: 0xFFFDF5) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(searchFocused || !query.isEmpty ? Theme.ink : .clear, lineWidth: 1)
        )
    }

    // MARK: - Search Results

    private func searchResultsSection(_ results: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.display(22))
                    .tracking(-0.2)
                Text("for \"\(query)\"")
                    .font(.mono(11, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkMute)
            }

            if results.isEmpty && searchError {
                VStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.bottom, 2)
                    Text("Connection error")
                        .font(.display(18))
                    Text("Check your connection and try again")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if results.isEmpty {
                VStack(spacing: 4) {
                    Text("No stations found")
                        .font(.display(18))
                    Text("Try a different name or 3-letter code")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                stationList(results, style: .search)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    // MARK: - Favourites

    private var favouritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favourites")
                    .font(.display(22))
                    .tracking(-0.2)
                Spacer()
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
            stationList(favouriteStore.stations, style: .favourite)
        }
        .id("favourites")
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    // MARK: - Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Nearby stations")
                        .font(.display(22))
                        .tracking(-0.2)
                    Spacer()
                    if !nearbyStations.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin")
                                .font(.system(size: 8))
                            Text("Near you")
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
                stationList(nearbyStations, style: .nearby)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    private var locationPrompt: some View {
        Button {
            locationManager.requestPermission()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location")
                        .font(.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Find stations near you")
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
            stationList(recentStore.stations, style: .recent)
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    // MARK: - Station List

    private enum StationRowStyle {
        case nearby, search, recent, favourite
    }

    private func stationList(_ stations: [Station], style: StationRowStyle) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element.code) { index, station in
                HStack(spacing: 0) {
                    Button {
                        pickStation(station)
                    } label: {
                        HStack(spacing: 12) {
                            Text(station.code)
                                .font(.mono(11, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.cream)
                                .frame(width: 42, height: 42)
                                .background(Theme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(station.name)
                                    .font(.display(18))
                                    .tracking(-0.1)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                if station.isInterchange {
                                    Text("Interchange station")
                                        .font(.ui(11))
                                        .foregroundStyle(Theme.inkMute)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if case .nearby = style, let dist = station.dist {
                                Text(dist < 1 ? String(format: "%.0fm", dist * 1000) : String(format: "%.1fkm", dist))
                                    .font(.mono(12, weight: .semibold))
                                    .tracking(-0.1)
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            favouriteStore.toggle(station)
                        }
                    } label: {
                        Image(systemName: favouriteStore.contains(station) ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(favouriteStore.contains(station) ? accent : Theme.inkMute)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    if index < stations.count - 1 {
                        Divider().overlay(Theme.line)
                    }
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Network Status

    private var disruptedCount: Int {
        tocIndicators.filter { $0.status != "Good service" }.count
    }

    private var networkStatusRow: some View {
        Button { showNetworkStatus = true } label: {
            HStack(spacing: 10) {
                Image(systemName: disruptedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(disruptedCount > 0 ? Theme.delayedText : Theme.perfGood)
                VStack(alignment: .leading, spacing: 2) {
                    Text(disruptedCount > 0 ? "\(disruptedCount) operator\(disruptedCount == 1 ? "" : "s") disrupted" : "All operators running normally")
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Network status")
                        .font(.mono(10, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkMute)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(14)
            .background(disruptedCount > 0 ? Theme.warn.opacity(0.25) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 6) {
            LiveDot(size: 9)
            Text("LIVE DATA \u{00B7} UPDATED \(timeString)")
                .font(.mono(10))
                .tracking(1.8)
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.top, 28)
        .padding(.bottom, 6)
    }
}

// MARK: - Network Status Sheet

struct NetworkStatusSheet: View {
    let indicators: [TOCIndicator]
    @Environment(\.dismiss) private var dismiss

    private var disrupted: [TOCIndicator] {
        indicators.filter { $0.status != "Good service" }
    }

    private var healthy: [TOCIndicator] {
        indicators.filter { $0.status == "Good service" }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Text("\(indicators.count)")
                            .font(.display(42))
                            .tracking(-1)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("operators")
                            Text("tracked")
                        }
                        .font(.mono(11))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        if !disrupted.isEmpty {
                            Text("\(disrupted.count) disrupted")
                                .font(.mono(11, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.delayedText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.warn.opacity(0.3))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 18)

                    if !disrupted.isEmpty {
                        tocSection("Disruptions", tocs: disrupted, showDescription: true)
                    }

                    tocSection("Good service", tocs: healthy, showDescription: false)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.cream)
            .navigationTitle("Network Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func tocSection(_ title: String, tocs: [TOCIndicator], showDescription: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(Array(tocs.enumerated()), id: \.element.tocCode) { index, toc in
                    let brand = OperatorBrand.brand(for: toc.tocCode)
                    HStack(spacing: 10) {
                        Text(toc.tocCode)
                            .font(.mono(9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(brand.fg)
                            .frame(width: 32, height: 26)
                            .background(brand.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toc.tocName)
                                .font(.ui(13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if showDescription {
                                Text(toc.statusDescription)
                                    .font(.ui(11))
                                    .foregroundStyle(Theme.inkSoft)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Circle()
                            .fill(toc.status == "Good service" ? Theme.perfGood : Theme.delayedText)
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if index < tocs.count - 1 {
                            Divider().overlay(Theme.line)
                        }
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 18)
        }
    }
}
