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

    /// Richtung von Punkt A nach Punkt B in Grad (0 = Norden, 90 = Osten, … 360). Für die
    /// Kompass-Nadel: Die Spitze zeigt entweder nach Norden oder zum nächsten Plakat.
    public static func bearingDegrees(
        fromLat: Double, fromLon: Double, toLat: Double, toLon: Double
    ) -> Double {
        let lat1 = fromLat * .pi / 180
        let lat2 = toLat * .pi / 180
        let dLon = (toLon - fromLon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
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

/// Wann iOS nach einer Bewertung fragen darf. Die eigentliche Anzeige übernimmt StoreKit.
public enum RatingPromptPolicy {
    public static let wartezeit: TimeInterval = 10 * 24 * 60 * 60
    public static let maximaleAnfragen = 3

    public static func sollAnzeigen(
        ersterStart: Date?, letzteAnfrage: Date?, anzahl: Int, jetzt: Date
    ) -> Bool {
        guard let ersterStart,
              anzahl < maximaleAnfragen,
              jetzt.timeIntervalSince(ersterStart) >= wartezeit
        else { return false }

        guard let letzteAnfrage else { return true }
        return jetzt.timeIntervalSince(letzteAnfrage) >= wartezeit
    }
}
