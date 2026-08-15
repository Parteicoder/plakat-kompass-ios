import Foundation

/// Eine Wahlkreis-Fläche aus einer gebündelten GeoJSON-Datei. Gegenstück zu `Wahlflaeche` in
/// `feature/wahldaten/WahldatenGeometrie.kt`.
///
/// Nur die Bundestagswahlkreise haben eine mitgelieferte Geometrie (299 Polygone, siehe
/// `WahlkreisGrenzen.swift`) — alle anderen Wahlarten (Kreis, Gemeinde) fragen ihren amtlichen
/// Schlüssel per Overpass ab, ohne Umriss. Das spart Bytes: eine Karte mit allen
/// Gemeindegrenzen wäre um Größenordnungen größer als 299 Wahlkreis-Polygone.
public struct Wahlflaeche: Sendable, Equatable {
    public let kennung: String
    public let name: String
    /// Nur die äußeren Ringe — deutsche Wahlkreise haben keine Enklaven, ein Loch wäre unnötiger
    /// Aufwand. Je Ring abwechselnd Länge, Breite: `[lon, lat, lon, lat, ...]`.
    public let ringe: [[Double]]

    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    public init(kennung: String, name: String, ringe: [[Double]]) {
        self.kennung = kennung
        self.name = name
        self.ringe = ringe

        var minLon = Double.infinity, minLat = Double.infinity
        var maxLon = -Double.infinity, maxLat = -Double.infinity
        for ring in ringe {
            var i = 0
            while i + 1 < ring.count {
                minLon = min(minLon, ring[i]); maxLon = max(maxLon, ring[i])
                minLat = min(minLat, ring[i + 1]); maxLat = max(maxLat, ring[i + 1])
                i += 2
            }
        }
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }
}

/// Liest Wahlkreis-Flächen aus einer GeoJSON-`FeatureCollection`.
///
/// `kennungSchluessel`/`namensSchluessel` probieren mehrere Property-Namen der Reihe nach — die
/// gebündelte Datei nutzt kleingeschriebene Namen (`wkr_nr`/`name`), die amtliche
/// Bundeswahlleiterin-Datei großgeschriebene (`WKR_NR`/`WKR_NAME`).
public func parseGeoJsonFlaechen(
    _ rawJson: String,
    kennungSchluessel: [String] = ["WKR_NR", "wkr_nr", "nr", "nummer", "Gebietsnummer"],
    namensSchluessel: [String] = ["WKR_NAME", "wkr_name", "name", "Gebietsname"]
) -> [Wahlflaeche] {
    guard let daten = rawJson.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
          let features = root["features"] as? [[String: Any]]
    else { return [] }

    var ergebnis: [Wahlflaeche] = []
    for feature in features {
        guard let eigenschaften = feature["properties"] as? [String: Any],
              let roh = ersterWert(eigenschaften, kennungSchluessel),
              let geometrie = feature["geometry"] as? [String: Any]
        else { continue }

        // Reine Bundeswahlleiterin-Zahlenschlüssel (74) auf drei Stellen auffüllen (074): Die
        // Ergebnisdatei bundestagswahl-2025.json schlüsselt dreistellig-nullgepolstert, das
        // gebündelte GeoJSON liefert bare Zahlen. Ohne diese Regel würden alle 99 Wahlkreise
        // unter 100 nie einen Treffer finden — sah auf dem Gerät wie "kein Ergebnis" aus, war
        // aber ein reiner Schlüssel-Mismatch.
        let numerisch = !roh.isEmpty && roh.allSatisfy(\.isNumber)
        let kennung = numerisch ? String(repeating: "0", count: max(0, 3 - roh.count)) + roh : roh
        let name = ersterWert(eigenschaften, namensSchluessel) ?? kennung

        let ringe = leseGeometrie(geometrie)
        guard !ringe.isEmpty else { continue }
        ergebnis.append(Wahlflaeche(kennung: kennung, name: name, ringe: ringe))
    }
    return ergebnis
}

/// Erste Fläche, die den Punkt enthält — kein Spatialindex, bei 299 Polygonen und einem Punkt je
/// Kartenbewegung lohnt sich das nicht. Bounding-Box zuerst, dann Ray-Casting nur für Kandidaten.
public func flaecheAn(_ gebiete: [Wahlflaeche], longitude: Double, latitude: Double) -> Wahlflaeche? {
    for gebiet in gebiete {
        guard longitude >= gebiet.minLon, longitude <= gebiet.maxLon,
              latitude >= gebiet.minLat, latitude <= gebiet.maxLat
        else { continue }
        if gebiet.ringe.contains(where: { ringEnthaelt($0, longitude: longitude, latitude: latitude) }) {
            return gebiet
        }
    }
    return nil
}

/// Ray-Casting nach der Even-Odd-Regel. Die asymmetrische Kantenprüfung (`>` auf der einen,
/// `<` auf der anderen Seite) sorgt dafür, dass ein Punkt auf der gemeinsamen Grenze zweier
/// Flächen genau einer davon zugeordnet wird — nicht keiner oder beiden. Ohne das würde die
/// hervorgehobene Fläche beim Schwenken über eine Grenze flackern.
///
/// Keine geodätische Korrektur: flache Ebene, der Fehler ist kleiner als die Ungenauigkeit der
/// Umrissdaten selbst.
func ringEnthaelt(_ ring: [Double], longitude: Double, latitude: Double) -> Bool {
    let punkte = ring.count / 2
    guard punkte >= 3 else { return false }

    var innen = false
    var j = punkte - 1
    for i in 0..<punkte {
        let lonI = ring[i * 2], latI = ring[i * 2 + 1]
        let lonJ = ring[j * 2], latJ = ring[j * 2 + 1]
        if (latI > latitude) != (latJ > latitude),
           longitude < (lonJ - lonI) * (latitude - latI) / (latJ - latI) + lonI {
            innen.toggle()
        }
        j = i
    }
    return innen
}

// Absichtlich elementweise statt mit einem einzigen "as? [[[Double]]]"-Pauschal-Cast: Auf
// welchen konkreten Zahlentyp (Int/Double/NSNumber) JSONSerialization eine JSON-Zahl abbildet,
// unterscheidet sich zwischen Apples Foundation und swift-corelibs-foundation unter Linux (der
// Kern baut laut Package.swift ausdrücklich auch dort). CommuneBoundary.swift geht aus demselben
// Grund schon elementweise vor.

private func leseGeometrie(_ geometrie: [String: Any]) -> [[Double]] {
    guard let typ = geometrie["type"] as? String,
          let coordinates = geometrie["coordinates"] as? [Any]
    else { return [] }
    switch typ {
    case "Polygon":
        guard let aussen = coordinates.first as? [Any], let flach = leseRing(aussen) else { return [] }
        return [flach]
    case "MultiPolygon":
        // Bewusst kein compactMap: eine kaputte Teilfläche soll die ganze Wahlfläche verwerfen,
        // nicht lautlos verkleinert zurückgeben — sonst würde ein Punkt in genau dieser
        // Teilfläche fälschlich als "außerhalb aller Wahlkreise" gemeldet.
        var ringe: [[Double]] = []
        for polygon in coordinates {
            guard let ringGruppe = polygon as? [Any], let aussen = ringGruppe.first as? [Any],
                  let flach = leseRing(aussen)
            else { return [] }
            ringe.append(flach)
        }
        return ringe
    default:
        return []
    }
}

/// Wandelt eine Liste von `[lon,lat]`-Punkten in einen flachen Ring `[lon,lat,lon,lat,...]` um.
/// Mindestens drei Punkte, sonst ist es kein Ring; jede Koordinate muss sich als endliche Zahl
/// lesen lassen.
private func leseRing(_ punkte: [Any]) -> [Double]? {
    guard punkte.count >= 3 else { return nil }
    var flach: [Double] = []
    flach.reserveCapacity(punkte.count * 2)
    for punkt in punkte {
        guard let koordinate = punkt as? [Any], koordinate.count >= 2,
              let lon = zahlAusJson(koordinate[0]), let lat = zahlAusJson(koordinate[1])
        else { return nil }
        flach.append(lon)
        flach.append(lat)
    }
    return flach
}

private func ersterWert(_ eigenschaften: [String: Any], _ schluessel: [String]) -> String? {
    for name in schluessel {
        guard let wert = eigenschaften[name] else { continue }
        if let text = wert as? String {
            if !text.isEmpty { return text }
            continue
        }
        // Ganzzahlige Werte ohne ".0" darstellen, sonst wird aus 152 "152.0" statt "152". Fällt
        // `intAusJson` mangels Ganzzahl-Bereich zurück auf nil (z. B. bei 1e20), bleibt die
        // Dezimaldarstellung als Rückfall — besser eine unerwartete Zeichenkette als ein Absturz.
        if let zahl = zahlAusJson(wert) {
            if zahl.truncatingRemainder(dividingBy: 1) == 0, let ganzzahl = intAusJson(zahl) {
                return String(ganzzahl)
            }
            return String(zahl)
        }
    }
    return nil
}
