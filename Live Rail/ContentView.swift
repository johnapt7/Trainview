import SwiftUI

enum AppScreen {
    case welcome
    case home
    case departures
    case journey
}

struct ContentView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var screen: AppScreen = .welcome
    @State private var activeTrain: Train?
    @State private var activeStation: Station = Station(code: "KGX", name: "King's Cross")
    @State private var pendingJourneyFilter: Station?
    @State private var tracker = TrainTracker()

    private let accent = Theme.accent

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeScreen(accent: accent) {
                    hasSeenWelcome = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        screen = .home
                    }
                }
            case .home:
                HomeScreen(
                    accent: accent,
                    onPickStation: { station in
                        activeStation = station
                        pendingJourneyFilter = nil
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .departures
                        }
                    },
                    onPickJourney: { journey in
                        activeStation = journey.origin
                        pendingJourneyFilter = journey.destination
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .departures
                        }
                    }
                )
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .home
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
                screen = .home
            }
            #if DEBUG
            // Testing hook (debug builds only):
            // `simctl launch <udid> <bundle> -openBoard <CRS>` jumps straight
            // to that station's departure board.
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
            guard url.scheme == "liverail",
                  url.host == "journey",
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
}

#Preview {
    ContentView()
}
