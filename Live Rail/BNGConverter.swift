import Foundation

/// Converts WGS84 latitude/longitude to British National Grid (EPSG:27700)
/// easting/northing metres. Mirror of the backend's bng package, run in the
/// forward direction: published seven-parameter Helmert transform, so a few
/// metres of error — ample for placing train dots at station granularity.
enum BNGConverter {
    private static let airyA = 6_377_563.396
    private static let airyB = 6_356_256.909
    private static let wgsA = 6_378_137.0
    private static let wgsB = 6_356_752.314245

    private static let scaleFactor = 0.9996012717
    private static let trueLat = 49 * Double.pi / 180
    private static let trueLon = -2 * Double.pi / 180
    private static let falseE = 400_000.0
    private static let falseN = -100_000.0

    static func toOSGB36(latitude: Double, longitude: Double) -> (easting: Double, northing: Double) {
        var lat = latitude * .pi / 180
        var lon = longitude * .pi / 180

        // WGS84 -> OSGB36 datum shift via cartesian coordinates. Parameters
        // are the OS-published position-vector transform (the backend applies
        // the same values negated for the opposite direction).
        var (x, y, z) = geodeticToCartesian(lat: lat, lon: lon, height: 0, a: wgsA, b: wgsB)
        (x, y, z) = helmert(
            x: x, y: y, z: z,
            tx: -446.448, ty: 125.157, tz: -542.060,
            scalePPM: 20.4894, rxSeconds: -0.1502, rySeconds: -0.2470, rzSeconds: -0.8421
        )
        (lat, lon) = cartesianToGeodetic(x: x, y: y, z: z, a: airyA, b: airyB)

        return transverseMercator(lat: lat, lon: lon)
    }

    private static func transverseMercator(lat: Double, lon: Double) -> (Double, Double) {
        let e2 = 1 - airyB * airyB / (airyA * airyA)
        let n = (airyA - airyB) / (airyA + airyB)
        let sinLat = sin(lat), cosLat = cos(lat), tanLat = tan(lat)

        let nu = airyA * scaleFactor / sqrt(1 - e2 * sinLat * sinLat)
        let rho = airyA * scaleFactor * (1 - e2) / pow(1 - e2 * sinLat * sinLat, 1.5)
        let eta2 = nu / rho - 1
        let m = meridionalArc(lat: lat, n: n)

        let i = m + falseN
        let ii = nu / 2 * sinLat * cosLat
        let iii = nu / 24 * sinLat * pow(cosLat, 3) * (5 - tanLat * tanLat + 9 * eta2)
        let iiia = nu / 720 * sinLat * pow(cosLat, 5) * (61 - 58 * tanLat * tanLat + pow(tanLat, 4))
        let iv = nu * cosLat
        let v = nu / 6 * pow(cosLat, 3) * (nu / rho - tanLat * tanLat)
        let vi = nu / 120 * pow(cosLat, 5)
            * (5 - 18 * tanLat * tanLat + pow(tanLat, 4) + 14 * eta2 - 58 * tanLat * tanLat * eta2)

        let dLon = lon - trueLon
        let northing = i + ii * pow(dLon, 2) + iii * pow(dLon, 4) + iiia * pow(dLon, 6)
        let easting = falseE + iv * dLon + v * pow(dLon, 3) + vi * pow(dLon, 5)
        return (easting, northing)
    }

    private static func meridionalArc(lat: Double, n: Double) -> Double {
        let dLat = lat - trueLat
        let sLat = lat + trueLat
        return airyB * scaleFactor * ((1 + n + 5 * n * n / 4 + 5 * n * n * n / 4) * dLat
            - (3 * n + 3 * n * n + 21 * n * n * n / 8) * sin(dLat) * cos(sLat)
            + (15 * n * n / 8 + 15 * n * n * n / 8) * sin(2 * dLat) * cos(2 * sLat)
            - 35 * n * n * n / 24 * sin(3 * dLat) * cos(3 * sLat))
    }

    private static func geodeticToCartesian(lat: Double, lon: Double, height: Double, a: Double, b: Double)
        -> (Double, Double, Double) {
        let e2 = 1 - b * b / (a * a)
        let sinLat = sin(lat), cosLat = cos(lat)
        let nu = a / sqrt(1 - e2 * sinLat * sinLat)
        return ((nu + height) * cosLat * cos(lon),
                (nu + height) * cosLat * sin(lon),
                ((1 - e2) * nu + height) * sinLat)
    }

    private static func helmert(
        x: Double, y: Double, z: Double,
        tx: Double, ty: Double, tz: Double,
        scalePPM: Double, rxSeconds: Double, rySeconds: Double, rzSeconds: Double
    ) -> (Double, Double, Double) {
        let arcsecToRad = Double.pi / (180 * 60 * 60)
        let scale = 1 + scalePPM * 1e-6
        let rx = rxSeconds * arcsecToRad
        let ry = rySeconds * arcsecToRad
        let rz = rzSeconds * arcsecToRad
        return (tx + scale * x - rz * y + ry * z,
                ty + rz * x + scale * y - rx * z,
                tz - ry * x + rx * y + scale * z)
    }

    private static func cartesianToGeodetic(x: Double, y: Double, z: Double, a: Double, b: Double)
        -> (Double, Double) {
        let e2 = 1 - b * b / (a * a)
        let p = hypot(x, y)
        var lat = atan2(z, p * (1 - e2))
        while true {
            let sinLat = sin(lat)
            let nu = a / sqrt(1 - e2 * sinLat * sinLat)
            let next = atan2(z + e2 * nu * sinLat, p)
            if abs(next - lat) < 1e-12 {
                lat = next
                break
            }
            lat = next
        }
        return (lat, atan2(y, x))
    }
}
