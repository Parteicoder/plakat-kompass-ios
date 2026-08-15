import Foundation

/// Ein amtliches Gebiet: Schlüssel und Name. Je nach Ebene fünfstellig (Kreis) oder achtstellig
/// (Gemeinde). Gegenstück zu `Kreis` in `feature/wahldaten/GebietsschluesselClient.kt`.
public struct Kreis: Sendable, Equatable {
    public let schluessel: String
    public let name: String

    public init(schluessel: String, name: String) {
        self.schluessel = schluessel
        self.name = name
    }
}

/// Baut die Overpass-Abfrage für den amtlichen Gebietsschlüssel unter einem Punkt und wertet die
/// Antwort aus. Gegenstück zu `GebietsschluesselClient.kt` — nur der reine, ohne Netz prüfbare
/// Teil; der eigentliche Abruf liegt in der App, wie bei `CommuneBoundaryQuery`/`Gemeindegrenze`.
///
/// Zwei Wahlarten brauchen den Schlüssel: Europawahl (Kreis) und Landtags-/Kommunalwahlen
/// (Gemeinde) — für die Bundestagswahl liegt stattdessen eine Geometrie-Beilage in der App
/// (`WahlkreisGrenzen.swift`), weil deren Wahlkreis-Nummerierung 2025 neu geschnitten wurde und
/// eine veraltete Nummer in OSM still das falsche Ergebnis zeigen könnte.
///
/// Ebene 6 ist der Kreis, Ebene 8 die Gemeinde, Ebene 4 das Bundesland — und für die drei
/// Stadtstaaten (Berlin, Hamburg, Bremen) die einzige, die es gibt. `out tags` statt `out geom`:
/// nur der Schlüssel wird gebraucht, kein Umriss.
public enum GebietsschluesselQuery {
    public static let endpunkt = "https://overpass-api.de/api/interpreter"

    public static func url(latitude: Double, longitude: Double) -> String {
        let abfrage = "[out:json][timeout:25];is_in(\(latitude),\(longitude))->.a;"
            + "relation(pivot.a)[\"boundary\"=\"administrative\"][\"admin_level\"~\"^(4|6|8)$\"];out tags;"
        let erlaubt = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return "\(endpunkt)?data=" + (abfrage.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? abfrage)
    }

    /// Der Kreis (fünfstellig) aus der Antwort. Ebene 6 hat Vorrang — dort steht der Kreisname,
    /// den man erwartet ("Landkreis Nordsachsen"). Nur wenn es keine Ebene 6 gibt, wird der
    /// Schlüssel aus der Gemeinde abgeleitet, dann steht aber deren Name da — ehrlicher als ein
    /// erfundener Kreisname.
    public static func kreis(_ rawJson: String) -> Kreis? {
        suche(rawJson, ebenen: [6, 8, 4], schluessel: kreisschluessel)
    }

    /// Die Gemeinde (achtstellig) aus der Antwort. Umgekehrte Reihenfolge: Ebene 8 hat Vorrang,
    /// mit Ebene 6 als Rückfall, falls eine kreisfreie Stadt ihren Schlüssel nur dort trägt.
    public static func gemeinde(_ rawJson: String) -> Kreis? {
        suche(rawJson, ebenen: [8, 6, 4], schluessel: gemeindeschluessel)
    }

    private static let schluesselMerkmale = ["de:regionalschluessel", "de:amtlicher_gemeindeschluessel"]

    /// Sucht die Ebenen **in der angegebenen Reihenfolge** ab, nicht in der Reihenfolge der
    /// Antwort — Overpass liefert die Elemente in beliebiger Reihenfolge. Ohne eine feste
    /// Rangfolge könnte das Bundesland gewinnen, nur weil es zuerst in der Antwort steht.
    private static func suche(_ rawJson: String, ebenen: [Int], schluessel: (String?) -> String?) -> Kreis? {
        guard let daten = rawJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let elemente = root["elements"] as? [[String: Any]]
        else { return nil }

        for ebene in ebenen {
            for element in elemente {
                guard let tags = element["tags"] as? [String: Any],
                      let stufeText = tags["admin_level"] as? String,
                      let stufe = Int(stufeText), stufe == ebene
                else { continue }

                for merkmal in schluesselMerkmale {
                    guard let gefunden = schluessel(tags[merkmal] as? String) else { continue }
                    let name = (tags["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Gebiet \(gefunden)"
                    return Kreis(schluessel: gefunden, name: name)
                }
            }
        }
        return nil
    }

    /// Die ersten fünf Ziffern eines amtlichen Schlüssels, oder `nil`, wenn es keine fünf gibt.
    /// Der Kreis steht bei allen Schlüsselarten vorn, deshalb reicht hier Abschneiden.
    static func kreisschluessel(_ roh: String?) -> String? {
        guard let ziffern = roh?.filter(\.isNumber), ziffern.count >= 5 else { return nil }
        return String(ziffern.prefix(5))
    }

    /// Der achtstellige Gemeindeschlüssel (AGS). **Abschneiden wäre hier falsch:** Der
    /// zwölfstellige Regionalschlüssel ist Land 2 + Regierungsbezirk 1 + Kreis 2 +
    /// Gemeindeverband 4 + Gemeinde 3; der AGS lässt den Gemeindeverband weg. Die ersten acht
    /// Stellen des Regionalschlüssels ergeben also nicht den AGS, sondern eine Zahl, die es nicht
    /// gibt. Richtig sind die ersten fünf Stellen plus die letzten drei.
    static func gemeindeschluessel(_ roh: String?) -> String? {
        guard let ziffern = roh?.filter(\.isNumber) else { return nil }
        if ziffern.count == 12 {
            return String(ziffern.prefix(5)) + String(ziffern.suffix(3))
        }
        if ziffern.count >= 8 {
            return String(ziffern.prefix(8))
        }
        return nil
    }
}
