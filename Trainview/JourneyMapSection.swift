import SwiftUI
import MapKit

struct JourneyMapSection: View {
    let stationPins: [StationPin]
    let legPaths: [String: [CLLocationCoordinate2D]]
    let isLoading: Bool
    let accent: Color
    let tracker: TrainTracker
    let serviceId: String

    @State private var showFullMap = false
    @State private var split: RouteSplit?

    private var hasEnoughPins: Bool { stationPins.count >= 2 }

    private var isTrackingThis: Bool { tracker.isTrackingService(serviceId) }
    private var isDelayed: Bool { isTrackingThis && tracker.trainStatus == .delayed }

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
                Text(isTrackingThis ? "Live map" : "Route map")
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
            RouteMapFullScreen(
                stationPins: stationPins,
                legPaths: legPaths,
                accent: accent,
                tracker: tracker,
                serviceId: serviceId,
                initialRegion: region
            )
        }
    }

    // MARK: - Inline Map

    private var mapCard: some View {
        Map(initialPosition: .region(region)) {
            if let split {
                RouteMapContent(
                    stationPins: stationPins,
                    split: split,
                    accent: accent,
                    labelAll: false,
                    isDelayed: isDelayed
                )
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        // Recompute the split every second and animate into it, so the train
        // marker glides continuously instead of stepping between refreshes.
        .task(id: "\(isTrackingThis)-\(stationPins.count)-\(legPaths.count)") {
            while !Task.isCancelled {
                let next = TrainMapMath.split(
                    pins: stationPins, legPaths: legPaths,
                    tracker: tracker, serviceId: serviceId, date: .now
                )
                withAnimation(.linear(duration: 1)) { split = next }
                guard isTrackingThis else { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .overlay(alignment: .topLeading) {
            if isTrackingThis {
                HStack(spacing: 5) {
                    LiveDot(size: 7)
                    Text("LIVE")
                        .font(.mono(9, weight: .semibold))
                        .tracking(1.2)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
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
        .overlay(alignment: .bottomTrailing) {
            MapKeyChip(
                accent: accent,
                isDelayed: isDelayed,
                showsCovered: (split?.covered.count ?? 0) >= 2
            )
            .padding(10)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18))
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

// MARK: - Route Math

/// The tracked train's interpolated position along the route.
/// Equatable on coordinates only so camera-follow reacts to actual movement.
struct TrainMapPosition: Equatable {
    let latitude: Double
    let longitude: Double
    /// Index of the last pin at or behind the train.
    let lastPinIndex: Int
    /// Index of the pin the train is heading toward (== lastPinIndex at rest).
    let nextPinIndex: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: TrainMapPosition, rhs: TrainMapPosition) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// The route split at the train's position: the line behind it, the line
/// ahead of it, and the marker itself (nil when not tracking this service).
struct RouteSplit {
    let marker: TrainMapPosition?
    let covered: [CLLocationCoordinate2D]
    let remaining: [CLLocationCoordinate2D]
}

enum TrainMapMath {
    /// Path for the leg between pins[i] and pins[i+1]: the real track shape
    /// when the backend supplied one, a straight segment otherwise.
    static func legPath(
        pins: [StationPin],
        legPaths: [String: [CLLocationCoordinate2D]],
        leg i: Int
    ) -> [CLLocationCoordinate2D] {
        let a = pins[i], b = pins[i + 1]
        if let path = legPaths["\(a.crs)-\(b.crs)"], path.count >= 2 {
            return path
        }
        return [a.coordinate, b.coordinate]
    }

    /// Concatenate leg paths for legs `range`, dropping duplicated joints.
    static func concatLegs(
        pins: [StationPin],
        legPaths: [String: [CLLocationCoordinate2D]],
        legs range: Range<Int>
    ) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for i in range {
            var path = legPath(pins: pins, legPaths: legPaths, leg: i)
            if let last = out.last, let first = path.first,
               last.latitude == first.latitude, last.longitude == first.longitude {
                path.removeFirst()
            }
            out.append(contentsOf: path)
        }
        return out
    }

    /// Splits the full route at the train's current position. When the
    /// tracker isn't tracking this service, `marker` is nil and the whole
    /// route comes back in `remaining`.
    ///
    /// Motion between the tracker's polls comes from the live departure /
    /// arrival dates; when real times are unknown (a delayed leg) the last
    /// computed fraction holds so the marker never guesses.
    static func split(
        pins: [StationPin],
        legPaths: [String: [CLLocationCoordinate2D]],
        tracker: TrainTracker,
        serviceId: String,
        date: Date
    ) -> RouteSplit {
        let legCount = max(pins.count - 1, 0)
        let fullRoute = concatLegs(pins: pins, legPaths: legPaths, legs: 0..<legCount)

        guard tracker.isTrackingService(serviceId), pins.count >= 2 else {
            return RouteSplit(marker: nil, covered: [], remaining: fullRoute)
        }
        let stops = tracker.trackedStops
        guard !stops.isEmpty else {
            return RouteSplit(marker: nil, covered: [], remaining: fullRoute)
        }

        let currentIdx = min(max(tracker.currentStopIndex, 0), stops.count - 1)
        let currentCRS = stops[currentIdx].crs
        guard !currentCRS.isEmpty,
              let fromPin = pins.firstIndex(where: { $0.crs == currentCRS }) else {
            return RouteSplit(marker: nil, covered: [], remaining: fullRoute)
        }

        func atRest(onPin pinIndex: Int) -> RouteSplit {
            let point = pins[pinIndex].coordinate
            var covered = concatLegs(pins: pins, legPaths: legPaths, legs: 0..<pinIndex)
            covered.append(point)
            let remaining = [point] + concatLegs(
                pins: pins, legPaths: legPaths, legs: pinIndex..<legCount
            )
            return RouteSplit(
                marker: TrainMapPosition(
                    latitude: point.latitude, longitude: point.longitude,
                    lastPinIndex: pinIndex, nextPinIndex: pinIndex
                ),
                covered: covered,
                remaining: remaining
            )
        }

        let nextIdx = tracker.nextStopIndex
        guard nextIdx > currentIdx, nextIdx < stops.count else { return atRest(onPin: fromPin) }
        let nextCRS = stops[nextIdx].crs
        guard !nextCRS.isEmpty,
              let ahead = pins[(fromPin + 1)...].firstIndex(where: { $0.crs == nextCRS })
        else { return atRest(onPin: fromPin) }

        let fraction: Double
        if let prev = tracker.previousStopDepartureDate,
           let next = tracker.nextStopArrivalDate,
           next > prev {
            fraction = min(max(date.timeIntervalSince(prev) / next.timeIntervalSince(prev), 0), 1)
        } else {
            fraction = min(max(tracker.progressBetweenStops, 0), 1)
        }

        // Walk the (possibly multi-leg) path between the two stops to the
        // distance-proportional point.
        let segment = concatLegs(pins: pins, legPaths: legPaths, legs: fromPin..<ahead)
        let (point, lastVertex) = interpolate(along: segment, fraction: fraction)

        var covered = concatLegs(pins: pins, legPaths: legPaths, legs: 0..<fromPin)
        covered.append(contentsOf: segment[...lastVertex])
        covered.append(point)

        var remaining: [CLLocationCoordinate2D] = [point]
        if lastVertex + 1 < segment.count {
            remaining.append(contentsOf: segment[(lastVertex + 1)...])
        }
        let tail = concatLegs(pins: pins, legPaths: legPaths, legs: ahead..<legCount)
        remaining.append(contentsOf: tail)

        return RouteSplit(
            marker: TrainMapPosition(
                latitude: point.latitude, longitude: point.longitude,
                lastPinIndex: fromPin, nextPinIndex: ahead
            ),
            covered: covered,
            remaining: remaining
        )
    }

    /// Point at `fraction` of the path's total length, plus the index of the
    /// last path vertex at or before that point.
    static func interpolate(
        along path: [CLLocationCoordinate2D],
        fraction: Double
    ) -> (point: CLLocationCoordinate2D, lastVertex: Int) {
        guard path.count >= 2 else {
            return (path.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0), 0)
        }
        let f = min(max(fraction, 0), 1)
        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(path.count - 1)
        var total: Double = 0
        for i in 0..<(path.count - 1) {
            let d = meters(path[i], path[i + 1])
            segmentLengths.append(d)
            total += d
        }
        guard total > 0 else { return (path[0], 0) }

        var target = f * total
        for i in 0..<segmentLengths.count {
            if target <= segmentLengths[i] {
                let t = segmentLengths[i] > 0 ? target / segmentLengths[i] : 0
                let a = path[i], b = path[i + 1]
                let point = CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
                return (point, i)
            }
            target -= segmentLengths[i]
        }
        return (path[path.count - 1], path.count - 2)
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - Shared Map Content

/// Route line, station pins, and the live train marker — shared between the
/// inline card and the full-screen map so both always look identical.
struct RouteMapContent: MapContent {
    let stationPins: [StationPin]
    let split: RouteSplit
    let accent: Color
    let labelAll: Bool
    /// When the tracked train is running late the route ahead turns amber,
    /// so a glance at the map carries the delay.
    let isDelayed: Bool

    var body: some MapContent {
        // Route ahead: solid like the covered line, told apart by colour —
        // muted grey ahead (amber when running late), accent behind the train.
        if split.remaining.count >= 2 {
            MapPolyline(coordinates: split.remaining)
                .stroke(
                    isDelayed ? Theme.delayedText : Theme.inkMute.opacity(0.7),
                    style: StrokeStyle(
                        lineWidth: isDelayed ? 2.5 : 2, lineCap: .round, lineJoin: .round
                    )
                )
        }
        if split.covered.count >= 2 {
            MapPolyline(coordinates: split.covered)
                .stroke(accent, style: StrokeStyle(
                    lineWidth: 3, lineCap: .round, lineJoin: .round
                ))
        }

        ForEach(Array(stationPins.enumerated()), id: \.element.id) { index, pin in
            Annotation(pin.name, coordinate: pin.coordinate, anchor: .bottom) {
                StationMarker(
                    type: pin.type,
                    accent: accent,
                    showLabel: labelAll || pin.type == .origin || pin.type == .destination,
                    isPassed: split.marker.map { index <= $0.lastPinIndex } ?? false
                )
            }
        }

        if let marker = split.marker {
            Annotation("", coordinate: marker.coordinate, anchor: .center) {
                TrainMarker(accent: accent)
            }
            .annotationTitles(.hidden)
        }
    }
}

/// Colour key for the route lines, overlaid on both map presentations.
struct MapKeyChip: View {
    let accent: Color
    let isDelayed: Bool
    let showsCovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsCovered {
                entry(colour: accent, label: "TRAVELLED")
            }
            if isDelayed {
                entry(colour: Theme.delayedText, label: "RUNNING LATE")
            } else {
                entry(colour: Theme.inkMute.opacity(0.7), label: "AHEAD")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func entry(colour: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(colour)
                .frame(width: 14, height: 3)
            Text(label)
                .font(.mono(8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Full Screen

struct RouteMapFullScreen: View {
    let stationPins: [StationPin]
    let legPaths: [String: [CLLocationCoordinate2D]]
    let accent: Color
    let tracker: TrainTracker
    let serviceId: String
    let initialRegion: MKCoordinateRegion

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var followTrain = false
    @State private var lastPosition: TrainMapPosition?
    @State private var split: RouteSplit?

    private var isTrackingThis: Bool { tracker.isTrackingService(serviceId) }
    private var isDelayed: Bool { isTrackingThis && tracker.trainStatus == .delayed }

    /// Camera altitude while following — close enough to see the train move,
    /// wide enough to keep the next station in frame on most legs.
    private static let followDistance: CLLocationDistance = 12_000

    private func currentMarker(at date: Date) -> TrainMapPosition? {
        TrainMapMath.split(
            pins: stationPins, legPaths: legPaths,
            tracker: tracker, serviceId: serviceId, date: date
        ).marker
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                if let split {
                    RouteMapContent(
                        stationPins: stationPins,
                        split: split,
                        accent: accent,
                        labelAll: true,
                        isDelayed: isDelayed
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                MapKeyChip(
                    accent: accent,
                    isDelayed: isDelayed,
                    showsCovered: (split?.covered.count ?? 0) >= 2
                )
                .padding(.trailing, 12)
                .padding(.bottom, 24)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
            // Marker and follow-camera share one 1-second linear animation
            // cadence, so the train and the viewport glide together.
            .task(id: "\(isTrackingThis)-\(stationPins.count)-\(legPaths.count)") {
                while !Task.isCancelled {
                    let next = TrainMapMath.split(
                        pins: stationPins, legPaths: legPaths,
                        tracker: tracker, serviceId: serviceId, date: .now
                    )
                    withAnimation(.linear(duration: 1)) { split = next }
                    lastPosition = next.marker
                    if followTrain, let marker = next.marker {
                        withAnimation(.linear(duration: 1)) {
                            camera = .camera(MapCamera(
                                centerCoordinate: marker.coordinate,
                                distance: Self.followDistance
                            ))
                        }
                    }
                    guard isTrackingThis else { break }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                // A pan that ends far from the train was the user taking
                // over — programmatic follow moves always end on the train.
                guard followTrain, let p = lastPosition else { return }
                if TrainMapMath.meters(ctx.camera.centerCoordinate, p.coordinate) > 1500 {
                    followTrain = false
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
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
                    Text(isTrackingThis ? "LIVE MAP" : "ROUTE MAP")
                        .font(.mono(11, weight: .semibold))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button {
                            followTrain = false
                            withAnimation(.easeInOut(duration: 0.8)) {
                                camera = .region(initialRegion)
                            }
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        if isTrackingThis {
                            Button {
                                followTrain.toggle()
                                if followTrain, let p = lastPosition ?? currentMarker(at: .now) {
                                    withAnimation(.easeInOut(duration: 0.8)) {
                                        camera = .camera(MapCamera(
                                            centerCoordinate: p.coordinate,
                                            distance: Self.followDistance
                                        ))
                                    }
                                }
                            } label: {
                                Image(systemName: followTrain ? "location.fill" : "location")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(followTrain ? Theme.cream : Theme.ink)
                                    .frame(width: 34, height: 34)
                                    .background(followTrain ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.ultraThinMaterial))
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                let pos = currentMarker(at: .now)
                lastPosition = pos
                if let pos {
                    followTrain = true
                    camera = .camera(MapCamera(
                        centerCoordinate: pos.coordinate,
                        distance: Self.followDistance
                    ))
                } else {
                    camera = .region(initialRegion)
                }
            }
        }
    }
}

// MARK: - Markers

private struct TrainMarker: View {
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Theme.ink, lineWidth: 1.5))
            Image(systemName: "train.side.front.car")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

private struct StationMarker: View {
    let type: StopType
    let accent: Color
    let showLabel: Bool
    var isPassed: Bool = false

    private var isEndpoint: Bool {
        type == .origin || type == .destination
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(isEndpoint ? accent : (isPassed ? accent : Theme.cream))
                    .frame(width: isEndpoint ? 14 : 10, height: isEndpoint ? 14 : 10)
                    .overlay(
                        Circle()
                            .stroke(
                                isEndpoint || isPassed ? Theme.ink : Theme.inkMute,
                                lineWidth: isEndpoint ? 2 : 1.5
                            )
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
