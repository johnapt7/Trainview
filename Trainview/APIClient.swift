import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, apiError: APIErrorResponse?)
    case decodingError(Error)
    case noData
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let apiError):
            if let msg = apiError?.message { return msg }
            return "Server error (\(code))"
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        case .unauthorized:
            return "Signed out"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL = "https://network-rail-adapter-production.up.railway.app/api"

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Supplies the account session token, set by AccountStore at startup.
    /// When non-nil, every request carries it as a bearer header — harmless
    /// on public endpoints, required on /account and /auth/session.
    var sessionTokenProvider: (() -> String?)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = sessionTokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: authorizedRequest(url: url))
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let apiError = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.httpError(statusCode: httpResponse.statusCode, apiError: apiError)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Request with a method and JSON body, returning a decoded response.
    /// Used by the account endpoints (POST/PUT/DELETE).
    private func send<T: Decodable, Body: Encodable>(_ method: String, _ path: String, body: Body) async throws -> T {
        var request = try methodRequest(method, path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    /// Body-less variant of `send` (DELETE endpoints).
    private func send<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await perform(try methodRequest(method, path))
    }

    private func methodRequest(_ method: String, _ path: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = authorizedRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let apiError = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.httpError(statusCode: httpResponse.statusCode, apiError: apiError)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Board (Departures / Arrivals)

    func getBoard(crs: String, type: String = "departures", rows: Int = 40, filterCrs: String? = nil, timeOffset: Int? = nil) async throws -> BoardResponse {
        var items = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "rows", value: "\(rows)"),
        ]
        // The backend reads "to"/"from", not "filterCrs" — it silently
        // ignores unknown params, so a wrong name returns an UNfiltered board.
        if let filterCrs {
            items.append(URLQueryItem(name: type == "arrivals" ? "from" : "to", value: filterCrs))
        }
        if let timeOffset, timeOffset != 0 { items.append(URLQueryItem(name: "timeOffset", value: "\(timeOffset)")) }
        return try await request("/board/\(crs)", queryItems: items)
    }

    // MARK: - Fastest Departures

    func getFastestDepartures(
        from crs: String,
        to destinations: [String],
        timeOffset: Int? = nil
    ) async throws -> FastestDeparturesResponse {
        var items = [URLQueryItem(name: "to", value: destinations.joined(separator: ","))]
        if let timeOffset, timeOffset != 0 {
            items.append(URLQueryItem(name: "timeOffset", value: "\(timeOffset)"))
        }
        return try await request("/board/\(crs)/fastest", queryItems: items)
    }

    // MARK: - Service Details

    func getServiceDetails(serviceId: String, crs: String? = nil) async throws -> ServiceDetailsResponse {
        let encoded = serviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serviceId
        var queryItems: [URLQueryItem]? = nil
        if let crs {
            queryItems = [URLQueryItem(name: "crs", value: crs)]
        }
        return try await request("/service/\(encoded)", queryItems: queryItems)
    }

    // MARK: - Formation, Loading & Associations

    func getFormation(rid: String) async throws -> FormationResponse {
        try await request("/formation/\(rid)")
    }

    func getTrainLoading(rid: String) async throws -> TrainLoadingResponse {
        try await request("/loading/train/\(rid)")
    }

    func getAssociations(rid: String) async throws -> AssociationsResponse {
        try await request("/associations/\(rid)")
    }

    // MARK: - Station Search

    func searchStations(query: String, limit: Int = 10) async throws -> [StationResponse] {
        let wrapper: StationSearchWrapper = try await request("/stations/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
        return wrapper.results ?? []
    }

    // MARK: - Nearby Stations

    func getNearbyStations(lat: Double, lng: Double, limit: Int = 5) async throws -> NearbyStationsWrapper {
        try await request("/stations/nearby", queryItems: [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lng", value: "\(lng)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
    }

    // MARK: - Station by CRS

    func getStation(crs: String) async throws -> StationResponse {
        try await request("/stations/crs/\(crs)")
    }

    // MARK: - Station Coordinates (batch)

    func getStationCoordinates(crsCodes: [String]) async -> [String: (lat: Double, lng: Double)] {
        await withTaskGroup(of: (String, Double, Double)?.self) { group in
            for crs in Set(crsCodes) {
                group.addTask {
                    guard let station = try? await self.getStation(crs: crs),
                          let lat = station.latitude,
                          let lng = station.longitude else { return nil }
                    return (crs, lat, lng)
                }
            }
            var result: [String: (lat: Double, lng: Double)] = [:]
            for await entry in group {
                if let (crs, lat, lng) = entry {
                    result[crs] = (lat, lng)
                }
            }
            return result
        }
    }

    // MARK: - HSP Metrics

    func getHSPMetrics(origin: String, destination: String, days: Int = 5) async throws -> HSPMetricsResponse {
        let calendar = Calendar.current
        let today = Date()
        let fromDate = calendar.date(byAdding: .day, value: -days, to: today)!

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        return try await request("/hsp/metrics/\(origin)/\(destination)", queryItems: [
            URLQueryItem(name: "from_date", value: fmt.string(from: fromDate)),
            URLQueryItem(name: "to_date", value: fmt.string(from: today)),
            URLQueryItem(name: "from_time", value: "0000"),
            URLQueryItem(name: "to_time", value: "2359"),
            URLQueryItem(name: "days", value: "WEEKDAY"),
        ])
    }

    // MARK: - Intelligence / Reliability

    func getReliability(origin: String, destination: String, days: Int = 5) async throws -> ReliabilityStats {
        try await request("/intelligence/reliability/\(origin)/\(destination)", queryItems: [
            URLQueryItem(name: "days", value: "\(days)"),
        ])
    }

    // MARK: - Disruptions

    func getTOCIndicators() async throws -> TOCIndicatorsResponse {
        try await request("/disruptions/tocs")
    }

    func getStationDisruptions(crs: String) async throws -> StationDisruptionsResponse {
        try await request("/disruptions/stations/\(crs)")
    }

    // MARK: - Movements

    // MARK: - Live Activity push registration

    func registerLiveActivity(_ registration: LiveActivityRegistration) async throws {
        try await postIgnoringResponse("/liveactivity/register", body: registration)
    }

    func unregisterLiveActivity(token: String) async throws {
        try await postIgnoringResponse("/liveactivity/unregister", body: ["token": token])
    }

    /// POST with a JSON body where only the status code matters.
    private func postIgnoringResponse<Body: Encodable>(_ path: String, body: Body) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: status, apiError: nil)
        }
    }

    func getRouteGeometry(crsCodes: [String]) async throws -> RouteGeometryResponse {
        try await request(
            "/route/geometry",
            queryItems: [URLQueryItem(name: "crs", value: crsCodes.joined(separator: ","))]
        )
    }

    func getMovements(rid: String, uid: String? = nil) async throws -> MovementsResponse {
        var queryItems: [URLQueryItem] = []
        if let uid, !uid.isEmpty {
            queryItems.append(URLQueryItem(name: "uid", value: uid))
        }
        return try await request("/movements/\(rid)", queryItems: queryItems)
    }

    // MARK: - Account

    func signInWithApple(identityToken: String, fullName: String?, authorizationCode: String?) async throws -> AuthResponse {
        struct SignInBody: Encodable {
            let identityToken: String
            let fullName: String?
            let authorizationCode: String?
        }
        return try await send("POST", "/auth/apple", body: SignInBody(
            identityToken: identityToken, fullName: fullName, authorizationCode: authorizationCode
        ))
    }

    func signOut() async throws {
        struct SignOutResponse: Decodable { let signedOut: Bool? }
        let _: SignOutResponse = try await send("DELETE", "/auth/session")
    }

    func deleteAccount() async throws {
        struct DeleteResponse: Decodable { let deleted: Bool? }
        let _: DeleteResponse = try await send("DELETE", "/account")
    }

    func getAccountStations() async throws -> StationsPayload {
        try await request("/account/stations")
    }

    func putAccountStations(home: [SyncedStation], favourites: [SyncedStation]) async throws -> StationsPayload {
        struct PutBody: Encodable {
            let home: [SyncedStation]
            let favourites: [SyncedStation]
        }
        return try await send("PUT", "/account/stations", body: PutBody(home: home, favourites: favourites))
    }
}
