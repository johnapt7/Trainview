import SwiftUI

enum AppScreen {
    case welcome
    case home
    case departures
    case journey
}

struct ContentView: View {
    @State private var screen: AppScreen = .welcome
    @State private var activeTrain: Train?
    @State private var activeStation: Station = Station(code: "KGX", name: "King's Cross")

    private let accent = Theme.accent

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeScreen(accent: accent) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        screen = .home
                    }
                }
            case .home:
                HomeScreen(accent: accent) { station in
                    activeStation = station
                    withAnimation(.easeInOut(duration: 0.25)) {
                        screen = .departures
                    }
                }
            case .departures:
                BoardScreen(
                    station: activeStation,
                    accent: accent,
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
                    JourneyScreen(train: train, accent: accent) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = .departures
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
