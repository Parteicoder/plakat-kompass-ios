import Foundation

/// Der Grenzverlauf einer Gemeinde. Gegenstück zu `feature/boundary/` auf Android.
///
/// Wozu: Wer plakatiert, plakatiert für eine Gemeinde — und die Grenze sieht man der Straße nicht
/// an. Ein Plakat hundert Meter zu weit hängt im Zuständigkeitsbereich der Nachbargemeinde, mit
/// eigener Genehmigung und eigener Frist.
///
/// Die Daten kommen von der Overpass-Schnittstelle von OpenStreetMap, ohne Schlüssel und ohne
/// Anmeldung. Geladen wird ausschließlich Geometrie.
public struct CommuneBoundary: Equatable, Sendable {
    public let name: String
    public let adminLevel: Int
    /// Mehrere Linienzüge, weil eine Gemeindegrenze aus mehreren Wegstücken besteht — und
    /// manche Gemeinden aus mehreren getrennten Flächen.
    public let lines: [[Koordinate]]

    public struct Koordinate: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}

public enum CommuneBoundaryQuery {

    public static let endpunkt = "https://overpass-api.de/api/interpreter"

    /// Die Abfrage.
    ///
    /// **Deutschland-Eigenheit:** `admin_level=8` ist die Gemeinde oder Stadt, aber kreisfreie
    /// Städte liegen teils nur auf `admin_level=6`. Beide werden abgefragt, und ausgewertet wird
    /// die feinste vorhandene Ebene — sonst bekäme man in Leipzig den ganzen Landkreis.
    public static func url(latitude: Double, longitude: Double) -> String {
        let abfrage = "[out:json][timeout:25];is_in(\(latitude),\(longitude))->.a;"
            + "relation(pivot.a)[\"boundary\"=\"administrative\"][\"admin_level\"~\"^(6|8)$\"];out geom;"
        let erlaubt = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return "\(endpunkt)?data=" + (abfrage.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? abfrage)
    }

    /// Wertet die Overpass-Antwort aus und nimmt die feinste vorhandene Verwaltungsebene.
    public static func parse(_ rohJson: String) -> CommuneBoundary? {
        guard let daten = rohJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let elemente = root["elements"] as? [[String: Any]]
        else { return nil }

        var bestes: CommuneBoundary?

        for element in elemente {
            guard element["type"] as? String == "relation",
                  let tags = element["tags"] as? [String: Any],
                  let ebene = ganzzahl(tags["admin_level"]),
                  ebene == 6 || ebene == 8,
                  let mitglieder = element["members"] as? [[String: Any]]
            else { continue }

            let name = (tags["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Gebiet"

            var linien: [[CommuneBoundary.Koordinate]] = []
            for mitglied in mitglieder {
                guard mitglied["type"] as? String == "way",
                      mitglied["role"] as? String != "inner",
                      let geometrie = mitglied["geometry"] as? [[String: Any]]
                else { continue }

                // Punkte ohne lat/lon überspringen. Eine abgeschnittene Antwort hat sie, und ein
                // Punkt mit NaN würde die Karte beim Zeichnen ins Nichts schicken.
                let punkte = geometrie.compactMap { knoten -> CommuneBoundary.Koordinate? in
                    guard let breite = kommazahl(knoten["lat"]), let laenge = kommazahl(knoten["lon"])
                    else { return nil }
                    return CommuneBoundary.Koordinate(latitude: breite, longitude: laenge)
                }
                // Ein einzelner Punkt ist keine Linie.
                if punkte.count >= 2 { linien.append(punkte) }
            }
            guard !linien.isEmpty else { continue }

            if bestes == nil || ebene > bestes!.adminLevel {
                bestes = CommuneBoundary(name: name, adminLevel: ebene, lines: linien)
            }
        }
        return bestes
    }

    private static func ganzzahl(_ roh: Any?) -> Int? {
        if let zahl = roh as? Int { return zahl }
        if let text = roh as? String { return Int(text) }
        if let zahl = roh as? Double, zahl.isFinite { return Int(zahl) }
        return nil
    }

    private static func kommazahl(_ roh: Any?) -> Double? {
        if let zahl = roh as? Double { return zahl.isFinite ? zahl : nil }
        if let zahl = roh as? Int { return Double(zahl) }
        if let zahl = roh as? NSNumber { return zahl.doubleValue.isFinite ? zahl.doubleValue : nil }
        if let text = roh as? String, let zahl = Double(text), zahl.isFinite { return zahl }
        return nil
    }
}
