import Foundation
import PlakatKompassCore

/// Einstellungen für Wahldaten, unabhängig von der Sozialdaten-Cache-Dauer — Gegenstück zu den
/// `wahldaten*`-Einträgen in `util/SocialDataSettingsStore.kt`. Eine mehrere-hundert-KB-große
/// Ergebnisdatei verdient eine eigene Haltbarkeit, nicht dieselbe wie ein paar Sozialdaten-Werte,
/// auch wenn beide später in derselben Einstellungskarte stehen.
enum WahldatenEinstellungen {
    static let vorgabeTage = 30
    static let minTage = 0
    static let maxTage = 90
    private static let tageSchluessel = "wahldatenCacheTage"
    private static let alleParteienSchluessel = "wahldatenAlleParteien"

    static var cacheTage: Int {
        get { (UserDefaults.standard.object(forKey: tageSchluessel) as? Int) ?? vorgabeTage }
        set { UserDefaults.standard.set(min(max(newValue, minTage), maxTage), forKey: tageSchluessel) }
    }

    /// Aus, solange niemand es eingeschaltet hat: Kleinparteien bleiben standardmäßig als
    /// "Sonstige" gebündelt.
    static var alleParteienAnzeigen: Bool {
        get { UserDefaults.standard.bool(forKey: alleParteienSchluessel) }
        set { UserDefaults.standard.set(newValue, forKey: alleParteienSchluessel) }
    }
}

/// Eine Ergebnisdatei je Wahlquelle auf der Platte, im `Caches`-Verzeichnis. Gegenstück zum
/// dateibasierten Teil von `ErgebnisdateiClient.kt`.
///
/// Anders als `SozialdatenCache.swift` (eine gemeinsame JSON-Datei mit vielen kurzen Einträgen)
/// bekommt jede Wahlquelle ihre eigene Datei: Eine mehrere-hundert-KB-große Ergebnisdatei in
/// einem gemeinsamen Blob neu zu schreiben, nur weil eine andere Quelle sich geändert hat, wäre
/// Verschwendung. Die Haltbarkeit wird über das Änderungsdatum der Datei selbst geprüft, kein
/// zusätzlicher Zeitstempel-Wrapper nötig.
@MainActor
enum ErgebnisdateiCache {
    private static var verzeichnis: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func hole(_ dateiname: String) -> Data? {
        guard WahldatenEinstellungen.cacheTage > 0 else { return nil }
        let ziel = verzeichnis.appendingPathComponent(dateiname)
        guard let attribute = try? FileManager.default.attributesOfItem(atPath: ziel.path),
              let geaendert = attribute[.modificationDate] as? Date
        else { return nil }

        let alterSekunden = Date().timeIntervalSince(geaendert)
        let haltbarkeitSekunden = TimeInterval(WahldatenEinstellungen.cacheTage) * 24 * 60 * 60
        guard alterSekunden >= 0, alterSekunden < haltbarkeitSekunden else { return nil }
        return try? Data(contentsOf: ziel)
    }

    /// Nicht geschrieben, wenn der Cache per Einstellung aus ist — sonst würde ein späteres
    /// Wiedereinschalten sofort eine veraltete Datei servieren, ohne dass je neu geladen wurde.
    static func speichere(_ dateiname: String, _ daten: Data) {
        guard WahldatenEinstellungen.cacheTage > 0 else { return }
        try? daten.write(to: verzeichnis.appendingPathComponent(dateiname), options: .atomic)
    }

    static func groesseBytes(_ dateinamen: [String]) -> Int64 {
        dateinamen.reduce(0) { summe, name in
            let pfad = verzeichnis.appendingPathComponent(name).path
            let attribute = try? FileManager.default.attributesOfItem(atPath: pfad)
            return summe + ((attribute?[.size] as? Int64) ?? 0)
        }
    }

    static func leeren(_ dateinamen: [String]) {
        for name in dateinamen {
            try? FileManager.default.removeItem(at: verzeichnis.appendingPathComponent(name))
        }
    }
}

/// Holt die Ergebnisdatei einer Wahlquelle — aus dem Zwischenspeicher, wenn frisch genug, sonst
/// vom Netz. Gegenstück zu `ErgebnisdateiClient.lade`.
enum ErgebnisdateiAbruf {
    @MainActor
    static func lade(_ quelle: Wahlquelle) async -> Data? {
        if let zwischengespeichert = ErgebnisdateiCache.hole(quelle.cacheDatei) {
            return zwischengespeichert
        }
        guard let daten = await hole(quelle.url) else { return nil }
        // Eine ungültige Antwort (z. B. eine HTML-Fehlerseite) wird nicht zwischengespeichert -
        // sonst läge sie dank der langen Cache-Frist einen Monat als "kein Ergebnis" fest.
        guard sindLandtagJsonBytes(daten) else { return nil }
        ErgebnisdateiCache.speichere(quelle.cacheDatei, daten)
        return daten
    }

    private static func hole(_ urlText: String) async -> Data? {
        guard let ziel = URL(string: urlText) else { return nil }
        let anfrage: URLRequest = {
            var anfrage = URLRequest(url: ziel)
            anfrage.timeoutInterval = 20
            anfrage.setValue("PlakatKompass/1.0 (iOS; Wahldaten)", forHTTPHeaderField: "User-Agent")
            anfrage.setValue("*/*", forHTTPHeaderField: "Accept")
            return anfrage
        }()

        guard let (daten, antwort) = try? await URLSession.shared.data(for: anfrage),
              let http = antwort as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }
        return daten
    }
}

/// Holt den amtlichen Gebietsschlüssel unter einem Punkt von Overpass. Gegenstück zum
/// netzwerkseitigen Teil von `GebietsschluesselClient.kt`.
///
/// Zwischengespeichert wird die **rohe Antwort**, nicht das ausgewertete Gebiet: Eine Abfrage
/// liefert Kreis- und Gemeindeebene auf einmal, und wer im Panel die Wahlart wechselt, wechselt
/// damit die Ebene, nicht den Ort — dafür soll es keinen zweiten Netzaufruf brauchen.
@MainActor
final class GebietsschluesselAbruf {
    static let geteilt = GebietsschluesselAbruf()

    private var zwischenspeicher: [String: String] = [:]

    func kreis(latitude: Double, longitude: Double) async -> Kreis? {
        await antwort(latitude: latitude, longitude: longitude).flatMap(GebietsschluesselQuery.kreis)
    }

    func gemeinde(latitude: Double, longitude: Double) async -> Kreis? {
        await antwort(latitude: latitude, longitude: longitude).flatMap(GebietsschluesselQuery.gemeinde)
    }

    /// Auf zwei Nachkommastellen gerundet (~1 km) — eine Gemeinde ist größer, nahe Punkte liefern
    /// also dieselbe Antwort.
    private func antwort(latitude: Double, longitude: Double) async -> String? {
        let schluessel = String(format: "%.2f,%.2f", latitude, longitude)
        if let vorhanden = zwischenspeicher[schluessel] { return vorhanden }

        let roh = await mitZweitemVersuch(latitude: latitude, longitude: longitude)
        // Nur Treffer merken: ein Netzausfall soll den Punkt nicht für den Rest des App-Laufs
        // festnageln.
        if let roh { zwischenspeicher[schluessel] = roh }
        return roh
    }

    /// Ein zweiter Anlauf, wenn der erste nichts bringt — Overpass weist Anfragen bei
    /// Überlastung zeitweise ab, ein einzelner Nachschlag mit kurzer Pause fängt das ab. Auf
    /// HTTP 429 ("zu viele Anfragen") wird **nicht** nachgefasst — ein zweiter Versuch nach einer
    /// Sekunde wäre dann genau das Falsche.
    private func mitZweitemVersuch(latitude: Double, longitude: Double) async -> String? {
        for versuch in 0..<2 {
            if versuch > 0 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            let (code, body) = await fetch(latitude: latitude, longitude: longitude)
            if let body { return body }
            if code == 429 { return nil }
        }
        return nil
    }

    private func fetch(latitude: Double, longitude: Double) async -> (Int?, String?) {
        guard let ziel = URL(string: GebietsschluesselQuery.url(latitude: latitude, longitude: longitude))
        else { return (nil, nil) }

        let anfrage: URLRequest = {
            var anfrage = URLRequest(url: ziel)
            anfrage.timeoutInterval = 30
            anfrage.setValue("PlakatKompass/1.0 (iOS; Gebietsschluessel)", forHTTPHeaderField: "User-Agent")
            anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
            return anfrage
        }()

        return await OverpassSchlange.geteilt.nacheinander {
            guard let (daten, antwort) = try? await URLSession.shared.data(for: anfrage),
                  let http = antwort as? HTTPURLResponse
            else { return (nil, nil) }
            guard (200...299).contains(http.statusCode) else { return (http.statusCode, nil) }
            return (http.statusCode, String(decoding: daten, as: UTF8.self))
        }
    }
}
