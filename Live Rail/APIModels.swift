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
    let scheduledDeparture: String?
    let expectedDeparture: String?
    let scheduledArrival: String?
    let expectedArrival: String?
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

// MARK: - API Error

struct APIErrorResponse: Codable {
    let error: Bool
    let code: String
    let message: String
}
