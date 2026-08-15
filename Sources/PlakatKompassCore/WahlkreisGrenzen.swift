import Foundation

/// Lädt die gebündelten Bundestagswahlkreis-Umrisse. Gegenstück zu
/// `feature/wahldaten/WahlkreisGrenzen.kt`.
///
/// Herkunft und Prüfung der Datei: siehe `docs/wahldaten-quellen.md` im Android-Repo — 299
/// Polygone, lückenlos 1–299 durchnummeriert, Gesamtfläche innerhalb 0,23 % der amtlichen Zahl.
/// Dieselbe Datei wie dort, keine zweite Herleitung.
public enum WahlkreisGrenzen {
    /// Einmal pro Prozess geladen und geparst — Swifts `static let`-Initialisierung ist
    /// threadsicher und lazy, ein eigenes Sperr-/Cache-Konstrukt wie Androids `@Volatile` ist
    /// dafür nicht nötig. Scheitert das Laden, bleibt es eine leere Liste statt eines Absturzes —
    /// Bundestagswahldaten fehlen dann einfach, alle anderen Wahlarten sind davon unberührt.
    public static let alle: [Wahlflaeche] = lade()

    private static func lade() -> [Wahlflaeche] {
        guard let url = Bundle.module.url(
                forResource: "wahlkreise_btw25", withExtension: "geojson", subdirectory: "Resources"
              ),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parseGeoJsonFlaechen(text)
    }
}
