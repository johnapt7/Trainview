import SwiftUI
import MapKit

struct JourneyMapSection: View {
    let stationPins: [StationPin]
    let isLoading: Bool
    let accent: Color

    @State private var showFullMap = false

    private var hasEnoughPins: Bool { stationPins.count >= 2 }

    private var region: MKCoordinateRegion {
        guard hasEnoughPins else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 53.0, longitude: -1.5),
                span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
            )
        }
        let lats = stationPins.map(\.coordinate.latitude)
        let lngs = stationPins.map(\.coordinate.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Route map")
                    .font(.display(26))
                    .tracking(-0.2)
                Spacer()
                if hasEnoughPins && !isLoading {
                    HStack(spacing: 5) {
                        Image(systemName: "map")
                            .font(.system(size: 8))
                        Text("\(stationPins.count - 1) stops")
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

            if isLoading {
                skeletonMap
            } else if !hasEnoughPins {
                unavailableCard
            } else {
                mapCard
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .sheet(isPresented: $showFullMap) {
            fullScreenMap
        }
    }

    // MARK: - Inline Map

    private var mapCard: some View {
        ZStack(alignment: .topTrailing) {
            Map(initialPosition: .region(region)) {
                ForEach(stationPins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .bottom) {
                        StationMarker(
                            type: pin.type,
                            accent: accent,
                            showLabel: pin.type == .origin || pin.type == .destination
                        )
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)

            Button {
                showFullMap = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(10)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Full Screen

    private var fullScreenMap: some View {
        NavigationStack {
            Map(initialPosition: .region(region)) {
                ForEach(stationPins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .bottom) {
                        StationMarker(
                            type: pin.type,
                            accent: accent,
                            showLabel: true
                        )
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFullMap = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("ROUTE MAP")
                        .font(.mono(11, weight: .semibold))
                        .tracking(1.5)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - States

    private var skeletonMap: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Theme.ink.opacity(0.07))
            .frame(height: 280)
            .shimmer()
    }

    private var unavailableCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "map")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkMute)
                .padding(.bottom, 2)
            Text("Route map unavailable")
                .font(.display(18))
            Text("Station coordinates could not be loaded")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Station Marker

private struct StationMarker: View {
    let type: StopType
    let accent: Color
    let showLabel: Bool

    private var isEndpoint: Bool {
        type == .origin || type == .destination
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(isEndpoint ? accent : Theme.cream)
                    .frame(width: isEndpoint ? 14 : 10, height: isEndpoint ? 14 : 10)
                    .overlay(
                        Circle()
                            .stroke(isEndpoint ? Theme.ink : Theme.inkMute, lineWidth: isEndpoint ? 2 : 1.5)
                    )
                if isEndpoint {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
