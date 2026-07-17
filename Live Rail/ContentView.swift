import SwiftUI

enum AppScreen {
    case welcome
    case tabs
    case departures
    case journey
}

enum AppTab {
    case home
    case favourites
    case disruptions
}

struct ContentView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var screen: AppScreen = .welcome
    @State private var tab: AppTab = .home
    @State private var activeTrain: Train?
    @State private var activeStation: Station = Station(code: "KGX", name: "King's Cross")
    @State private var pendingJourneyFilter: Station?
    @State private var tracker = TrainTracker()
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Theme.accent

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeScreen(accent: accent) {
                    hasSeenWelcome = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        screen = .tabs
                    }
                }
            case .tabs:
                mainTabs
            case .departures:
                BoardScreen(
                    station: activeStation,
                    accent: accent,
                    initialFilterDestination: pendingJourneyFilter,
                    onOpenTrain: { train in
                        activeTrain = train
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .journey
                        }
                    },
                    onBack: {
                        // Returns to whichever tab the board was opened from —
                        // tab selection persists underneath the board.
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .tabs
                        }
                    }
                )
            case .journey:
                if let train = activeTrain {
                    JourneyScreen(
                        train: train,
                        boardingStation: activeStation,
                        accent: accent,
                        tracker: tracker,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                screen = .departures
                            }
                        },
                        onSelectTrain: { alternative in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeTrain = alternative
                            }
                        }
                    )
                    // Re-create the screen when an alternative is picked so
                    // its loaded details don't leak across trains.
                    .id(train.serviceId)
                }
            }
        }
        .onAppear {
            if hasSeenWelcome {
                screen = .tabs
            }
            // Pick tracking back up after a relaunch so a live journey (and
            // its Live Activity) survives force-quits and Xcode reruns.
            Task { _ = await tracker.resumeIfNeeded() }
            #if DEBUG
            // Testing hooks (debug builds only):
            // `simctl launch <udid> <bundle> -openTab disruptions` lands on
            // that tab; `-openBoard <CRS>` jumps to a departure board.
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "-openTab"), idx + 1 < args.count {
                switch args[idx + 1] {
                case "favourites": tab = .favourites
                case "disruptions": tab = .disruptions
                default: break
                }
            }
            if let idx = args.firstIndex(of: "-openBoard"), idx + 1 < args.count {
                let crs = args[idx + 1]
                Task {
                    let name = (try? await APIClient.shared.searchStations(query: crs, limit: 1))?
                        .first?.name ?? crs
                    activeStation = Station(code: crs, name: name)
                    screen = .departures
                }
            }
            #endif
        }
        .onOpenURL { url in
            guard url.scheme == "liverail", url.host == "journey" else { return }
            // Restore tracking first if the app was relaunched — the tap on
            // the Live Activity must always land on its journey.
            Task {
                guard await tracker.resumeIfNeeded(),
                      let train = tracker.trackedTrain else { return }
                activeTrain = train
                if let boarding = tracker.boardingStation {
                    activeStation = boarding
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    screen = .journey
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground: refresh immediately instead of
            // waiting out the poll loop's sleep, so the journey screen and
            // Live Activity snap up to date.
            if phase == .active {
                tracker.pollNow()
            }
        }
    }

    /// Root tab bar (iOS 26 Liquid Glass). The departure board and journey
    /// screens replace the whole view rather than pushing within a tab, so
    /// the bar only shows at the app's top level.
    private var mainTabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeScreen(
                    accent: accent,
                    tracker: tracker,
                    onPickStation: openBoard,
                    onPickJourney: { journey in
                        activeStation = journey.origin
                        pendingJourneyFilter = journey.destination
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .departures
                        }
                    },
                    onOpenTrackedTrain: {
                        // Mirrors the Live Activity deep link: land on the
                        // tracked journey with its original boarding station.
                        guard let train = tracker.trackedTrain else { return }
                        activeTrain = train
                        if let boarding = tracker.boardingStation {
                            activeStation = boarding
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .journey
                        }
                    }
                )
            }
            Tab("Favourites", systemImage: "star.fill", value: AppTab.favourites) {
                FavouritesScreen(
                    accent: accent,
                    onPickStation: openBoard
                )
            }
            Tab("Disruptions", systemImage: "exclamationmark.triangle.fill", value: AppTab.disruptions) {
                DisruptionsScreen(accent: accent)
            }
        }
        .tint(Theme.ink)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func openBoard(_ station: Station) {
        activeStation = station
        pendingJourneyFilter = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = .departures
        }
    }
}

#Preview {
    ContentView()
}
