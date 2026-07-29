import Foundation
import ZIPFoundation

/// Die Plakatliste für die Stadtverwaltung: eine CSV, auf Wunsch mit den Fotos in einem ZIP.
///
/// Gegenstück zu `core/OfficialExport.kt` auf Android. Diese Datei verlässt die App-Welt und
/// landet in Excel oder LibreOffice bei jemandem im Rathaus — das prägt fast jede Entscheidung
/// hier drin und erklärt die drei Eigenheiten des Formats:
///
/// 1. **BOM am Anfang.** Ohne ihn zeigen ältere Excel-Fassungen aus Umlauten Buchstabensalat.
/// 2. **`sep=;` als erste Zeile.** Sonst zerlegt Excel Überschriften wie „Aktueller Status"
///    an den Leerzeichen.
/// 3. **Formeln entschärfen.** Siehe `defuseFormula`.
///
/// Anders als bei einem Sync-Paket muss die Ausgabe **nicht** Byte für Byte der von Android
/// entsprechen: Eine CSV geht an die Verwaltung, nie an ein anderes Gerät. Gleich aussehen soll
/// sie trotzdem — ein Team, das mit beiden Plattformen arbeitet, reicht sonst zwei verschiedene
/// Listen ein.
public enum OfficialExport {

    public static func toCsv(state: LocalTeamState, municipality: String) -> String {
        buildCsv(state: state, municipality: municipality, photoPathFor: nil)
    }

    /// Schreibt `plakatliste.csv` samt `fotos/` in ein ZIP und gibt dessen Bytes zurück.
    ///
    /// Fotos, die auf der Platte fehlen, stehen in der CSV als „Kein Foto" — ein fehlendes Bild
    /// darf den Export nicht scheitern lassen, sonst steht die Verwaltungsfrist wegen einer
    /// einzigen kaputten Datei.
    public static func zipData(
        state: LocalTeamState,
        municipality: String,
        photoURL: (String) -> URL?
    ) throws -> Data {
        guard let archive = Archive(accessMode: .create) else {
            throw SyncError.exportFehlgeschlagen("ZIP liess sich nicht anlegen.")
        }

        let namen = photoEntryNames(state: state, photoURL: photoURL)
        let csv = Data(
            buildCsv(
                state: state,
                municipality: municipality,
                photoPathFor: { index in namen[index] ?? "Kein Foto" }
            ).utf8
        )
        try archive.addEntry(
            with: "plakatliste.csv",
            type: .file,
            uncompressedSize: Int64(csv.count),
            provider: { position, size in csv.subdata(in: Int(position)..<Int(position) + size) }
        )

        for (index, plakat) in state.posters.enumerated() {
            guard let eintrag = namen[index],
                  let name = plakat.localPhotoFileName,
                  let quelle = photoURL(name),
                  let foto = try? Data(contentsOf: quelle)
            else { continue }
            try archive.addEntry(
                with: eintrag,
                type: .file,
                uncompressedSize: Int64(foto.count),
                provider: { position, size in foto.subdata(in: Int(position)..<Int(position) + size) }
            )
        }

        guard let daten = archive.data else {
            throw SyncError.exportFehlgeschlagen("ZIP liess sich nicht abschliessen.")
        }
        return daten
    }

    // MARK: - Die CSV

    private static func buildCsv(
        state: LocalTeamState,
        municipality: String,
        photoPathFor: ((Int) -> String)?
    ) -> String {
        var kopf = [
            "Nr.",
            "Kommune",
            "Standortbeschreibung",
            "Plakatart",
            "Aktueller Status",
            "Erfasst am",
            "Abnahme geplant am",
            "Bemerkung für Stadtverwaltung",
            "GPS-Breitengrad",
            "GPS-Längengrad",
            "Google-Maps-Link"
        ]
        if photoPathFor != nil { kopf.append("Foto-Datei") }

        let zeilen = state.posters.enumerated().map { index, plakat -> String in
            var spalten = [
                String(index + 1),
                municipality,
                plakat.addressHint.istLeer ? "Keine Standortbeschreibung eingetragen" : plakat.addressHint,
                plakat.type.amtlicherText,
                plakat.status.amtlicherText,
                datum(plakat.createdAt),
                plakat.plannedRemovalAt.map(datum) ?? "Nicht eingetragen",
                plakat.officialNote.istLeer ? "Keine Bemerkung" : plakat.officialNote,
                zahl(plakat.latitude),
                zahl(plakat.longitude),
                "https://www.google.com/maps/search/?api=1&query=\(zahl(plakat.latitude)),\(zahl(plakat.longitude))"
            ]
            if let photoPathFor { spalten.append(photoPathFor(index)) }
            return spalten.map(zelle).joined(separator: ";")
        }

        return "\u{FEFF}" + (["sep=;", kopf.map(zelle).joined(separator: ";")] + zeilen)
            .joined(separator: "\n")
    }

    /// Fotoname je Plakat-Position, oder `nil` wenn es kein Foto gibt oder die Datei fehlt.
    ///
    /// Einmal berechnet und geteilt, damit die CSV und das ZIP nicht auseinanderlaufen können:
    /// Ein Name, der in der Liste steht, aber nicht im Archiv liegt, wäre für die Verwaltung ein
    /// toter Verweis.
    private static func photoEntryNames(
        state: LocalTeamState,
        photoURL: (String) -> URL?
    ) -> [Int: String] {
        var namen: [Int: String] = [:]
        for (index, plakat) in state.posters.enumerated() {
            guard let name = plakat.localPhotoFileName,
                  let url = photoURL(name),
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            let roh = url.pathExtension.lowercased()
            let endung = roh.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil ? roh : "jpg"
            namen[index] = "fotos/plakat_\(String(format: "%03d", index + 1)).\(endung)"
        }
        return namen
    }

    // MARK: - Einzelne Zellen

    /// Excel und LibreOffice werten eine Zelle, die nach dem Entquoten mit `=`, `+`, `-`, `@`,
    /// Tabulator oder CR beginnt, als **Formel** aus. Standortbeschreibung, Bemerkung und
    /// Kommune sind Freitext und können per Abgleich von einem fremden Gerät stammen — jemand
    /// könnte dort also `=HYPERLINK(...)` hinterlegen, das dann im Rathaus ausgeführt wird.
    /// Ein vorangestelltes Apostroph macht daraus wieder Text.
    ///
    /// Echte Zahlen bleiben Zahlen: Ein Längengrad `-12.34` soll in der Tabelle rechnen können.
    private static func defuseFormula(_ wert: String) -> String {
        guard let erstes = wert.first, "=+-@\t\r".contains(erstes) else { return wert }
        if wert.range(of: "^-?\\d+(\\.\\d+)?$", options: .regularExpression) != nil { return wert }
        return "'" + wert
    }

    private static func zelle(_ wert: String) -> String {
        "\"" + defuseFormula(wert).replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `DateFormatter` ist teuer im Aufbau und wird pro Export mehrfach gebraucht.
    /// Die Zeitzone bleibt bewusst die des Geräts: „Erfasst am" soll den Tag zeigen, an dem
    /// die Person vor dem Plakat stand.
    private static let datumsFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private static func datum(_ millis: Int64) -> String {
        datumsFormat.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    /// Koordinaten wie auf Android schreiben.
    ///
    /// Swifts `String(describing:)` liefert bei sehr kleinen Werten `1e-05`, Kotlin `1.0E-5`.
    /// Für Koordinaten spielt das keine Rolle — aber die Verwaltung soll keine
    /// Exponentialschreibweise sehen, also wird sie hier ausgeschrieben.
    private static func zahl(_ wert: Double) -> String {
        let kurz = "\(wert)"
        guard kurz.lowercased().contains("e") else { return kurz }
        return String(format: "%.10f", wert)
    }
}

private extension String {
    /// Wie Kotlins `isBlank()`: leer oder nur Weißraum.
    var istLeer: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private extension PosterType {
    /// Eigene Beschriftungen, nicht die der Oberfläche: Für die Verwaltung heißt `LARGE_FORMAT`
    /// „Großformat / Großfläche", in der App nur „Großformat". So steht es auch auf Android.
    var amtlicherText: String {
        switch self {
        case .LAMP_POST: return "Laternenmast"
        case .FENCE: return "Zaun"
        case .BANNER: return "Banner"
        case .TRIANGLE_STAND: return "Dreieckständer"
        case .LARGE_FORMAT: return "Großformat / Großfläche"
        case .OTHER: return "Sonstiges"
        }
    }
}

private extension PosterStatus {
    var amtlicherText: String {
        switch self {
        case .HANGING: return "Hängt"
        case .CHECKED: return "Kontrolliert"
        case .DAMAGED: return "Beschädigt"
        case .MISSING: return "Fehlt"
        case .REPLACED: return "Ersetzt"
        case .REMOVED: return "Entfernt"
        }
    }
}

/// Der Dateiname des Verwaltungs-ZIPs. Gegenstück zu `core/ExportNames.kt`.
public enum ExportNames {

    /// Der Zeitstempel geht bis auf Millisekunden, damit zwei Exporte in derselben Sekunde nicht
    /// dieselbe Datei überschreiben — beim Doppeltippen passiert genau das.
    public static func authorityZipName(
        municipality: String,
        nowMillis: Int64 = Date.nowMillis
    ) -> String {
        var sauber = municipality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Kommune"
            : municipality
        sauber = sauber.replacingOccurrences(
            of: "[^A-Za-z0-9ÄÖÜäöüß_-]", with: "_", options: .regularExpression
        )
        sauber = sauber.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        sauber = sauber.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if sauber.isEmpty { sauber = "Kommune" }

        let stempel = stempelFormat.string(from: Date(timeIntervalSince1970: Double(nowMillis) / 1000))
        return "PlakatRadar_Verwaltung_\(sauber)_\(stempel).zip"
    }

    private static let stempelFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return f
    }()
}
