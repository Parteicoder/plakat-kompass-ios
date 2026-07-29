import Foundation

/// Die Zahlen der Startseite. Gegenstück zu `ModernHomeStats.kt`.
///
/// Vier Zahlen, aber sie überschneiden sich absichtlich: Ein beschädigtes Plakat zählt sowohl
/// als aktiv als auch als Problem. Wer sie addiert, bekommt Unsinn — sie beantworten vier
/// getrennte Fragen und keine Aufteilung.
public struct HomeStats: Equatable, Sendable {
    public let aktiv: Int
    public let kontrolliert: Int
    public let probleme: Int
    public let entfernt: Int

    public init(posters: [Poster]) {
        aktiv = posters.filter { $0.status != .REMOVED }.count
        kontrolliert = posters.filter { $0.status == .CHECKED }.count
        probleme = posters.filter { $0.status == .DAMAGED || $0.status == .MISSING }.count
        entfernt = posters.filter { $0.status == .REMOVED }.count
    }
}

/// „Welches Plakat ist gerade das nächste?" Gegenstück zu `core/NearestPoster.kt`.
///
/// Wer eine Runde dreht, um Plakate zu kontrollieren, will wissen, wohin als Nächstes. Die
/// Rechnung steht hier und nicht in der Oberfläche, weil sie sich prüfen lässt — eine falsche
/// Entfernung schickt jemanden durch die halbe Stadt.
public enum NearestPoster {

    private static let erdradiusMeter = 6_371_000.0

    public struct Treffer: Equatable, Sendable {
        public let poster: Poster
        public let entfernungMeter: Double
    }

    /// Haversine. Für Entfernungen innerhalb einer Gemeinde ist die Erde nah genug an einer
    /// Kugel; eine genauere Ellipsoid-Rechnung würde hier Zentimeter gewinnen.
    public static func distanceMeters(
        _ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double
    ) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return erdradiusMeter * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    public static func find(_ posters: [Poster], latitude: Double, longitude: Double) -> Treffer? {
        posters
            .filter { $0.status != .REMOVED }
            .map { Treffer(poster: $0, entfernungMeter: distanceMeters(latitude, longitude, $0.latitude, $0.longitude)) }
            .min { $0.entfernungMeter < $1.entfernungMeter }
    }

    /// Unter einem Kilometer in Metern, darüber in Kilometern — ab zehn ohne Nachkommastelle.
    /// „12,4 km" hilft niemandem weiter als „12 km".
    public static func distanceText(_ meter: Double) -> String {
        if meter < 1000 { return "\(Int(meter)) m" }
        if meter < 10_000 { return String(format: "%.1f km", locale: Locale(identifier: "de_DE"), meter / 1000) }
        return String(format: "%.0f km", locale: Locale(identifier: "de_DE"), meter / 1000)
    }
}
