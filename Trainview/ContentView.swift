import SwiftUI

enum AppScreen {
    case welcome
    case tabs
    case departures
    case journey
}

struct ContentView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var screen: AppScreen = .welcome
    @State private var activeTrain: Train?
    @State private var activeStation: Station = Station(code: "KGX", name: "King's Cross")
    @State private var pendingJourneyFilter: Station?
    // Owned here (not in BoardScreen) so departures/arrivals survives
    // navigating into a train and back; reset when a new board opens.
    @State private var boardMode: BoardMode = .departures
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
                    mode: $boardMode,
                    initialFilterDestination: pendingJourneyFilter,
                    onOpenTrain: { train in
                        activeTrain = train
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .journey
                        }
                    },
                    onBack: {
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
            // A notification tap that launched the app routes straight to the
            // journey; its didReceive ran before this view existed.
            if NotificationPresenter.shared.consumePendingJourneyOpen() {
                openTrackedJourney()
            } else {
                Task { _ = await tracker.resumeIfNeeded() }
            }
            // Pull synced stations (no-op when signed out).
            AccountStore.shared.refresh()
            #if DEBUG
            // Testing hook (debug builds only): `-openBoard <CRS>` jumps
            // straight to a departure board.
            let args = ProcessInfo.processInfo.arguments
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
            openTrackedJourney()
        }
        // Notification taps (departure reminders, delay/platform alerts) land
        // here via the delegate — same destination as a Live Activity tap.
        .onReceive(NotificationCenter.default.publisher(for: NotificationPresenter.journeyTapNotification)) { _ in
            _ = NotificationPresenter.shared.consumePendingJourneyOpen()
            openTrackedJourney()
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground: refresh immediately instead of
            // waiting out the poll loop's sleep, so the journey screen and
            // Live Activity snap up to date.
            if phase == .active {
                tracker.pollNow()
                // Foreground pull of synced stations (and retry of any
                // pending upload). No-op when signed out.
                AccountStore.shared.refresh()
            }
        }
    }

    /// Home IS the app's top level — no tab bar. Disruptions moved into a
    /// sheet behind a top-bar icon on Home, favourites were retired in
    /// favour of home stations.
    private var mainTabs: some View {
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
                // tracked journey anchored to the station whose board it
                // came from (the destination for tracked arrivals).
                guard let train = tracker.trackedTrain else { return }
                activeTrain = train
                if let anchor = tracker.boardStation ?? tracker.boardingStation {
                    activeStation = anchor
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    screen = .journey
                }
            }
        )
    }

    private func openBoard(_ station: Station) {
        activeStation = station
        pendingJourneyFilter = nil
        boardMode = .departures
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = .departures
        }
    }

    /// Lands on the tracked journey's screen, restoring tracking first if the
    /// app was relaunched. Shared by Live Activity taps (via liverail:// URL)
    /// and notification taps — both must always reach the live journey.
    private func openTrackedJourney() {
        Task {
            guard await tracker.resumeIfNeeded(),
                  let train = tracker.trackedTrain else { return }
            activeTrain = train
            // The journey screen's data is relative to the board station
            // (destination for arrivals) — anchor there, not where the
            // user boards.
            if let anchor = tracker.boardStation ?? tracker.boardingStation {
                activeStation = anchor
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                screen = .journey
            }
        }
    }
}

#Preview {
    ContentView()
}
