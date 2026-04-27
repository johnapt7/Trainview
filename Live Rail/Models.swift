import Foundation

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
    let time: String
    let platform: String
    let type: StopType

    init(station: String, time: String, platform: String, type: StopType) {
        self.station = station
        self.time = time
        self.platform = platform
        self.type = type
    }

    init(from cp: CallingPointResponse) {
        self.station = cp.station
        self.time = cp.scheduledTime
        self.platform = cp.platform ?? "—"
        self.type = cp.status == "delayed" ? .major : .stop
    }
}

struct Train: Identifiable {
    let id: String
    let serviceId: String
    let time: String
    let destination: String
    let origin: String
    let via: String
    let platform: String
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

    init(id: String, time: String, destination: String, origin: String,
         via: String, platform: String, operator: String, operatorCode: String,
         status: TrainStatus, statusNote: String, type: String = "", carriages: Int = 0,
         duration: String = "", stops: [Stop] = []) {
        self.id = id
        self.serviceId = id
        self.time = time
        self.destination = destination
        self.origin = origin
        self.via = via
        self.platform = platform
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
    }

    init(from service: BoardService) {
        self.id = service.serviceId
        self.serviceId = service.serviceId
        self.time = service.scheduledTime
        self.destination = service.destination
        self.origin = service.origin
        self.via = service.destinationVia ?? ""
        self.platform = service.platform ?? "—"
        self.operator = service.operator
        self.operatorCode = service.operatorCode
        self.type = ""
        self.carriages = service.length
        self.cancelReason = service.cancelReason
        self.delayReason = service.delayReason
        self.duration = ""
        self.stops = []

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
