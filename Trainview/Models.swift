import Foundation
import CoreLocation

enum TrainStatus: String, CaseIterable {
    case onTime = "on-time"
    case delayed = "delayed"
    case cancelled = "cancelled"
}

enum StopType: String {
    case origin
    case destination
    case stop
    case major
}

struct Stop: Identifiable {
    let id = UUID()
    let station: String
    let crs: String
    let time: String
    let expectedTime: String?
    let actualTime: String?
    let platform: String
    let type: StopType
    let hasDeparted: Bool

    init(station: String, crs: String = "", time: String, expectedTime: String? = nil, actualTime: String? = nil, platform: String, type: StopType, hasDeparted: Bool = false) {
        self.station = station
        self.crs = crs
        self.time = time
        self.expectedTime = expectedTime
        self.actualTime = actualTime
        self.platform = platform
        self.type = type
        self.hasDeparted = hasDeparted
    }

    init(from cp: CallingPointResponse, hasDeparted: Bool = false) {
        self.station = cp.station.decodingHTMLEntities()
        self.crs = cp.crs
        self.time = cp.scheduledTime
        self.expectedTime = cp.expectedTime
        self.actualTime = cp.actualTime
        self.platform = cp.platform ?? "—"
        self.type = cp.status == "delayed" ? .major : .stop
        self.hasDeparted = hasDeparted
    }

    var delayMinutes: Int? {
        guard let scheduled = Stop.parseMinutes(time) else { return nil }
        let observed: Int? = {
            if let a = actualTime, let m = Stop.parseMinutes(a) { return m }
            if let e = expectedTime, let m = Stop.parseMinutes(e) { return m }
            return nil
        }()
        guard let observed else { return nil }
        var delta = observed - scheduled
        if delta < -12 * 60 { delta += 24 * 60 }
        if delta > 12 * 60 { delta -= 24 * 60 }
        return delta
    }

    private static func parseMinutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

struct Train: Identifiable {
    let id: String
    let serviceId: String
    let time: String
    let destination: String
    let destinationCrs: String
    let origin: String
    let via: String
    let platform: String
    let isPredictedPlatform: Bool
    let `operator`: String
    let operatorCode: String
    let status: TrainStatus
    let statusNote: String
    let type: String
    let carriages: Int?
    let cancelReason: String?
    let delayReason: String?
    let duration: String
    let stops: [Stop]
    let rid: String?
    let uid: String?
    let headcode: String?
    let rollingStock: RollingStockInfo?

    init(id: String, time: String, destination: String, destinationCrs: String = "", origin: String,
         via: String, platform: String, operator: String, operatorCode: String,
         status: TrainStatus, statusNote: String, type: String = "", carriages: Int = 0,
         duration: String = "", stops: [Stop] = []) {
        self.id = id
        self.serviceId = id
        self.time = time
        self.destination = destination
        self.destinationCrs = destinationCrs
        self.origin = origin
        self.via = via
        self.platform = platform
        self.isPredictedPlatform = false
        self.operator = `operator`
        self.operatorCode = operatorCode
        self.status = status
        self.statusNote = statusNote
        self.type = type
        self.carriages = carriages
        self.cancelReason = nil
        self.delayReason = nil
        self.duration = duration
        self.stops = stops
        self.rid = nil
        self.uid = nil
        self.headcode = nil
        self.rollingStock = nil
    }

    /// Rebuilds a previously tracked train from a persisted snapshot. Live
    /// details (status, stops, times) are refreshed by the tracker's first
    /// poll, so only identity and display basics are restored here.
    init(restoredId: String, time: String, origin: String, destination: String,
         destinationCrs: String, platform: String, operator: String,
         operatorCode: String, rid: String?, uid: String?) {
        self.id = restoredId
        self.serviceId = restoredId
        self.time = time
        self.destination = destination
        self.destinationCrs = destinationCrs
        self.origin = origin
        self.via = ""
        self.platform = platform
        self.isPredictedPlatform = false
        self.operator = `operator`
        self.operatorCode = operatorCode
        self.status = .onTime
        self.statusNote = "On time"
        self.type = ""
        self.carriages = nil
        self.cancelReason = nil
        self.delayReason = nil
        self.duration = ""
        self.stops = []
        self.rid = rid
        self.uid = uid
        self.headcode = nil
        self.rollingStock = nil
    }

    init(from service: BoardService) {
        self.id = service.serviceId
        self.serviceId = service.serviceId
        self.time = service.scheduledTime
        self.destination = service.destination.decodingHTMLEntities()
        self.destinationCrs = service.destinationCrs
        self.origin = service.origin.decodingHTMLEntities()
        self.via = (service.destinationVia ?? "").decodingHTMLEntities()
        if let confirmed = service.platform {
            self.platform = confirmed
            self.isPredictedPlatform = false
        } else if let predicted = service.predictedPlatform,
                  Train.isAuthoritativePlatformSource(predicted.source) {
            // Real-time and recorded-fact sources are true regardless of
            // whether the train has left — LDBWS drops platforms for
            // departed services, so this is what fills past boards.
            self.platform = predicted.platform
            self.isPredictedPlatform = false
        } else if let predicted = service.predictedPlatform,
                  !Train.hasDeparted(scheduled: service.scheduledTime, expected: service.expectedTime) {
            // Learned guesses stay hedged, and never speculate about the past.
            self.platform = predicted.platform
            self.isPredictedPlatform = true
        } else {
            self.platform = "—"
            self.isPredictedPlatform = false
        }
        self.operator = service.operator.decodingHTMLEntities()
        self.operatorCode = service.operatorCode
        self.type = ""
        self.carriages = service.length
        self.cancelReason = service.cancelReason
        self.delayReason = service.delayReason
        self.duration = ""
        self.stops = []
        self.rid = service.rid
        self.uid = service.uid
        self.headcode = service.headcode
        self.rollingStock = service.rollingStock

        switch service.status {
        case "delayed":
            self.status = .delayed
            self.statusNote = service.expectedTime
        case "cancelled":
            self.status = .cancelled
            self.statusNote = "Cancelled"
        default:
            self.status = .onTime
            self.statusNote = service.expectedTime
        }
    }

    /// Sources that state where the train is or was — as opposed to the
    /// learned tiers (pattern/historical), which are guesses.
    private static func isAuthoritativePlatformSource(_ source: String) -> Bool {
        switch source {
        case "observed", "darwin_confirmed", "darwin", "td", "trust":
            return true
        default:
            return false
        }
    }

    private static func hasDeparted(scheduled: String, expected: String) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current

        func toToday(_ s: String) -> Date? {
            guard let t = fmt.date(from: s) else { return nil }
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: now)
        }

        guard let target = toToday(expected) ?? toToday(scheduled) else { return false }
        if target.timeIntervalSince(now) > 6 * 3600 { return true }
        return target < now
    }
}

struct Station: Identifiable, Codable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let dist: Double?
    let isInterchange: Bool

    init(code: String, name: String, dist: Double? = nil, isInterchange: Bool = false) {
        self.code = code
        self.name = name
        self.dist = dist
        self.isInterchange = isInterchange
    }

    init(from response: StationResponse) {
        self.code = response.crs
        self.name = response.name
        self.dist = nil
        self.isInterchange = response.isInterchange
    }

    init(from response: NearbyStationResponse) {
        self.code = response.crs
        self.name = response.name
        self.dist = response.distanceKm
        self.isInterchange = response.isInterchange
    }
}

enum BoardMode: String, CaseIterable {
    case departures
    case arrivals
}

enum FilterMode: String, CaseIterable {
    case all
    case onTime = "on-time"
    case intercity
}

struct StationPin: Identifiable {
    let id: String
    let crs: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let type: StopType
}
