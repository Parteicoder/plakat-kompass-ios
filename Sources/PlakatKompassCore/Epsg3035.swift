import Foundation

/// WGS84 (Länge/Breite) → EPSG:3035 (ETRS89-LAEA Europa) und die Zell-Kennungen des
/// INSPIRE-100-Meter-Gitters.
///
/// Dient **allein** dazu, die Zell-Kennungen für die Online-Abfrage auszurechnen
/// (`where=id IN ('100mN…E…', …)`). Es werden **keine** Statistikwerte gespeichert oder
/// mitgeliefert — die Kennzahlen kommen live vom öffentlichen ArcGIS-Dienst.
///
/// Warum überhaupt selbst rechnen: Der Dienst beantwortet räumliche Punkt- und Rechteckabfragen
/// auf diesem Layer mit 400 oder mit Zeitüberschreitungen. Die attributbasierte Abfrage über
/// Zell-Kennungen ist der Weg, der trägt — und dafür müssen die Kennungen hier entstehen.
///
/// Gegenstück zu `feature/socialdata/zensus/Epsg3035.kt` auf Android. Die Zahlen müssen auf beiden
/// Seiten dieselben sein, sonst fragen die Apps unterschiedliche Zellen ab und zeigen für
/// denselben Ort verschiedene Werte.
public enum Epsg3035 {
    private static let a = 6_378_137.0
    private static let f = 1.0 / 298.257_222_101
    private static let e2 = f * (2.0 - f)
    private static let e = e2.squareRoot()
    private static let lat0 = 52.0 * .pi / 180.0
    private static let lon0 = 10.0 * .pi / 180.0
    private static let falseEasting = 4_321_000.0
    private static let falseNorthing = 3_210_000.0
    private static let zelleM = 100.0

    public struct OstNord: Equatable, Sendable {
        public let easting: Double
        public let northing: Double

        public init(easting: Double, northing: Double) {
            self.easting = easting
            self.northing = northing
        }
    }

    /// Projiziert WGS84-Grad nach EPSG:3035-Metern.
    public static func vonWgs84(longitude: Double, latitude: Double) -> OstNord {
        let lat = latitude * .pi / 180.0
        let lon = longitude * .pi / 180.0
        let qp = q(.pi / 2.0)
        let q0 = q(lat0)
        let qq = q(lat)
        let beta0 = asin(q0 / qp)
        let beta = asin(qq / qp)
        let rq = a * (qp / 2.0).squareRoot()
        let d = a * (cos(lat0) / (1.0 - e2 * sin(lat0) * sin(lat0)).squareRoot()) / (rq * cos(beta0))
        let b = rq * (
            2.0 / (1.0 + sin(beta0) * sin(beta) + cos(beta0) * cos(beta) * cos(lon - lon0))
        ).squareRoot()
        let easting = falseEasting + b * d * cos(beta) * sin(lon - lon0)
        let northing = falseNorthing + (b / d) * (
            cos(beta0) * sin(beta) - sin(beta0) * cos(beta) * cos(lon - lon0)
        )
        return OstNord(easting: easting, northing: northing)
    }

    /// Zell-Kennung im Format des Dienstes, etwa `100mN32732E45520`.
    public static func zellKennung(easting: Double, northing: Double) -> String {
        let e100 = Int64((easting / zelleM).rounded(.down))
        let n100 = Int64((northing / zelleM).rounded(.down))
        return "100mN\(n100)E\(e100)"
    }

    /// Alle Zell-Kennungen im Umkreis-Quadrat um einen Kartenpunkt — nur Adressen für die
    /// anschließende Abfrage, keine Daten.
    public static func zellenUm(
        longitude: Double,
        latitude: Double,
        radiusMeter: Int
    ) -> [String] {
        let mitte = vonWgs84(longitude: longitude, latitude: latitude)
        let schritte = max(1, (radiusMeter + Int(zelleM) - 1) / Int(zelleM))
        let e0 = (mitte.easting / zelleM).rounded(.down) * zelleM
        let n0 = (mitte.northing / zelleM).rounded(.down) * zelleM
        var kennungen: [String] = []
        kennungen.reserveCapacity((2 * schritte + 1) * (2 * schritte + 1))
        for dn in -schritte...schritte {
            for de in -schritte...schritte {
                kennungen.append(zellKennung(
                    easting: e0 + Double(de) * zelleM,
                    northing: n0 + Double(dn) * zelleM
                ))
            }
        }
        return kennungen
    }

    private static func q(_ phi: Double) -> Double {
        let s = sin(phi)
        return (1.0 - e2) * (
            s / (1.0 - e2 * s * s)
                - (1.0 / (2.0 * e)) * log((1.0 - e * s) / (1.0 + e * s))
        )
    }
}
