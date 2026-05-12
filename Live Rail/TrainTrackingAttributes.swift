import ActivityKit
import Foundation

struct TrainTrackingAttributes: ActivityAttributes {
    let serviceId: String
    let origin: String
    let destination: String
    let operatorCode: String
    let operatorName: String
    let scheduledDeparture: String
    let scheduledArrival: String
    let totalStops: Int

    struct ContentState: Codable, Hashable {
        let currentStopIndex: Int
        let nextStopName: String
        let nextStopExpectedTime: String
        let nextStopPlatform: String?
        let nextStopDelayMinutes: Int?
        let platform: String
        let status: String
        let progressFraction: Double
        let previousStopDepartureDate: Date?
        let nextStopArrivalDate: Date?
        let destinationArrivalDate: Date?
        let destinationDelayMinutes: Int?
        let lastUpdated: Date
    }
}
