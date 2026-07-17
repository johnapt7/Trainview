import Foundation

// MARK: - Board / Departures & Arrivals

struct BoardResponse: Codable {
    let generatedAt: String
    let stationName: String
    let stationCrs: String
    let boardType: String
    let platformsAvailable: Bool
    let services: [BoardService]
    let nrccMessages: [String]?
    let filterStation: String?
    let filterCrs: String?
}

struct BoardService: Codable, Identifiable {
    var id: String { serviceId }

    let scheduledTime: String
    let expectedTime: String
    let platform: String?
    let predictedPlatform: PredictedPlatform?
    let `operator`: String
    let operatorCode: String
    let destination: String
    let destinationCrs: String
    let destinationVia: String?
    let origin: String
    let originCrs: String
    let isCancelled: Bool
    let cancelReason: String?
    let delayReason: String?
    let serviceId: String
    let length: Int?
    let status: String
    let rid: String?
    let uid: String?
    let headcode: String?
    /// Present when the backend serves the board via the LDBWS "WithDetails"
    /// operations — spares a per-service details request for the preview.
    let subsequentCallingPoints: [CallingPointResponse]?
    let previousCallingPoints: [CallingPointResponse]?
    let rollingStock: RollingStockInfo?
}

/// Rolling-stock identity resolved from the CIF timetable: the unit class
/// plus its marketing name where one exists (Pendolino, Evero, Azuma...).
struct RollingStockInfo: Codable {
    let unitClass: String?
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case unitClass = "class"
        case name
    }

    /// "Pendolino" when named, otherwise "Class 385"; nil when unknown.
    var label: String? {
        if let name, !name.isEmpty { return name }
        if let unitClass, !unitClass.isEmpty { return "Class \(unitClass)" }
        return nil
    }
}

// MARK: - Platform Prediction

struct PredictedPlatform: Codable {
    let platform: String
    let confidence: Double
    let source: String
    let observationCount: Int?
    let lastObserved: String?
}

// MARK: - Fastest Departures

struct FastestDeparturesResponse: Codable {
    let generatedAt: String
    let stationName: String
    let stationCrs: String
    let platformsAvailable: Bool
    let nrccMessages: [String]?
    let results: [FastestDeparturesResult]
}

struct FastestDeparturesResult: Codable, Identifiable {
    var id: String { destinationCrs }

    let destinationCrs: String
    let destinationName: String
    let service: BoardService?
    let callingPoints: [CallingPointResponse]
    let unavailable: Bool?
    let unavailableReason: String?
}

// MARK: - Service Details

struct ServiceDetailsResponse: Codable {
    let serviceId: String
    let rsid: String?
    let generatedAt: String
    let `operator`: String
    let operatorCode: String
    let serviceType: String
    let isCancelled: Bool
    let cancelReason: String?
    let delayReason: String?
    let platform: String?
    let predictedPlatform: PredictedPlatform?
    let scheduledDeparture: String?
    let expectedDeparture: String?
    let scheduledArrival: String?
    let expectedArrival: String?
    let length: Int?
    let origin: StationLocation?
    let destination: StationLocation?
    let previousCallingPoints: [CallingPointResponse]
    let subsequentCallingPoints: [CallingPointResponse]
}

struct StationLocation: Codable {
    let name: String
    let crs: String
}

struct CallingPointResponse: Codable, Identifiable {
    var id: String { "\(crs)-\(scheduledTime)" }

    let station: String
    let crs: String
    let scheduledTime: String
    let expectedTime: String?
    let actualTime: String?
    let platform: String?
    let isCancelled: Bool
    let status: String
}

// MARK: - Stations

struct StationResponse: Codable, Identifiable {
    var id: String { crs }

    let crs: String
    let tiploc: String
    let name: String
    let `operator`: String?
    let latitude: Double?
    let longitude: Double?
    let isInterchange: Bool
}

struct StationSearchWrapper: Codable {
    let query: String
    let count: Int
    let results: [StationResponse]?
}

struct NearbyStationResponse: Codable, Identifiable {
    var id: String { crs }

    let crs: String
    let tiploc: String
    let name: String
    let `operator`: String?
    let lat: Double
    let lng: Double
    let isInterchange: Bool
    let distanceKm: Double

    enum CodingKeys: String, CodingKey {
        case crs, tiploc, name, `operator`, lat, lng, isInterchange
        case distanceKm = "distance_km"
    }
}

struct NearbyStationsWrapper: Codable {
    let lat: Double
    let lng: Double
    let count: Int
    let stations: [NearbyStationResponse]?
}

// MARK: - Historical Service Performance

struct HSPMetricsResponse: Codable {
    let origin: String
    let destination: String
    let fromDate: String
    let toDate: String
    let fromTime: String
    let toTime: String
    let days: String
    let summary: HSPSummary
    let services: [HSPServiceMetrics]
}

struct HSPSummary: Codable {
    let totalScheduled: Int
    let overallOnTimePercent: Double
    let bestService: HSPBestWorst?
    let worstService: HSPBestWorst?
}

struct HSPBestWorst: Codable {
    let departs: String
    let arrives: String
    let onTimePercent: Double
}

struct HSPServiceMetrics: Codable {
    let departs: String
    let arrives: String
    let `operator`: String
    let matchedServices: Int
    let onTimeCount: Int
    let lateCount: Int
    let onTimePercent: Double
    let rids: [String]
}

// MARK: - Intelligence / Reliability

struct ReliabilityStats: Codable {
    let originCrs: String
    let destinationCrs: String
    let totalServices: Int
    let onTimeServices: Int
    let delayedServices: Int
    let cancelledServices: Int
    let onTimePercent: Double
    let avgDelayMinutes: Double
    let period: String
    let generatedAt: String
}

// MARK: - Disruptions (TOC-level)

struct TOCIndicatorsResponse: Codable {
    let generatedAt: String
    let indicators: [TOCIndicator]
}

struct TOCIndicator: Codable, Identifiable {
    var id: String { tocCode }

    let tocCode: String
    let tocName: String
    let status: String
    let statusDescription: String
    let additionalInfo: String?
    /// Link to the operator's live travel news page. Optional so the app
    /// keeps working against backends that don't send it yet.
    let detailURL: String?
}

// MARK: - Disruptions (Station-level)

struct StationDisruptionsResponse: Codable {
    let crs: String
    let stationName: String
    let disruptions: [StationDisruption]
}

struct StationDisruption: Codable, Identifiable {
    let id: String
    let type: String
    let severity: String
    let title: String
    let description: String
    let category: String
    let affectedOperators: [String]
    let validFrom: String
    let customerAdvice: String?
    /// See TOCIndicator.detailURL.
    let detailURL: String?
}

// MARK: - Movements (TRUST)

struct MovementsResponse: Codable {
    let rid: String?
    let count: Int?
    let movements: [MovementEvent]?
    let error: Bool?
    let code: String?
    let message: String?
}

struct MovementEvent: Codable, Identifiable {
    var id: String { "\(rid)-\(eventType)-\(tiploc)-\(actualTimestamp)" }

    let rid: String
    let headcode: String
    let uid: String
    let eventType: String
    let actualTimestamp: String
    let plannedTimestamp: String
    let variationSeconds: Int
    let variationStatus: String
    let stanox: String
    let tiploc: String
    let crs: String?
    let platform: String?
    let toc: String
    let recordedAt: String
}

// MARK: - Formation & Coach Loading

struct FormationResponse: Decodable {
    let rid: String?
    let formation: [FormationRecord]?
}

struct FormationRecord: Decodable {
    let fid: String?
    let coaches: CoachesContainer?
}

struct CoachesContainer: Decodable {
    let coach: [CoachInfo]?
}

/// Darwin's XML→JSON conversion makes `toilet` either a plain string
/// ("Standard", "Accessible") or an object whose type sits under the
/// empty-string key — decode both into `toiletType`.
struct CoachInfo: Decodable {
    let coachNumber: String?
    let coachClass: String?
    let toiletType: String?

    private enum CodingKeys: String, CodingKey {
        case coachNumber, coachClass, toilet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coachNumber = try container.decodeIfPresent(String.self, forKey: .coachNumber)
        coachClass = try container.decodeIfPresent(String.self, forKey: .coachClass)
        if let plain = try? container.decode(String.self, forKey: .toilet) {
            toiletType = plain
        } else if let object = try? container.decode([String: String].self, forKey: .toilet) {
            toiletType = object[""]
        } else {
            toiletType = nil
        }
    }
}

struct TrainLoadingResponse: Decodable {
    let rid: String?
    let loadings: [LoadingRecord]?
}

struct LoadingRecord: Decodable {
    let rid: String?
    let tpl: String?
    let crs: String?
    let loading: [CoachLoadingEntry]?
}

struct CoachLoadingEntry: Decodable {
    let coachNumber: String?
    /// Percentage as a string, e.g. "45".
    let loading: String?

    var percent: Int? {
        guard let loading else { return nil }
        return Int(loading)
    }
}

// MARK: - Associations (divides / joins)

struct AssociationsResponse: Decodable {
    let rid: String?
    let associations: [TrainAssociation]?
}

struct TrainAssociation: Decodable {
    let category: String
    let tiploc: String?
    let crs: String?
    let station: String?
    let partnerRid: String?
    let isMain: Bool
    let cancelled: Bool
}

// MARK: - Route Geometry

struct RouteGeometryResponse: Decodable {
    let legs: [RouteGeometryLeg]
}

struct RouteGeometryLeg: Decodable {
    let from: String
    let to: String
    /// "osm" when routed along real track, "straight" for a 2-point fallback.
    let source: String
    /// [lat, lng] pairs ordered from → to.
    let coords: [[Double]]
}

// MARK: - Live Activity Registration

struct LiveActivityRegistration: Encodable {
    let token: String
    let rid: String
    let serviceId: String
    let uid: String?
    let boardingCrs: String
    let alightingCrs: String?
}

// MARK: - Active Trains Snapshot

struct ActiveTrainsResponse: Codable {
    let count: Int
    let trains: [ActiveTrain]
}

/// One entry per active train from GET /api/movements. Location is the
/// newest station-resolvable TRUST event; lateness and age reflect the
/// newest event of any kind.
struct ActiveTrain: Codable {
    let rid: String
    let uid: String?
    let headcode: String
    let toc: String
    let eventType: String
    let tiploc: String
    let crs: String
    let lat: Double
    let lon: Double
    let actualTimestamp: String
    let ageSeconds: Int
    let variationSeconds: Int
    let variationStatus: String

    /// Stable identity for dot tracking — RID when known, else CIF UID.
    var key: String { rid.isEmpty ? (uid ?? "") : rid }
}

// MARK: - API Error

struct APIErrorResponse: Codable {
    let error: Bool
    let code: String
    let message: String
}
