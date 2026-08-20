/// Längengrenzen für Freitext, 1:1 aus der Android-Erfassung.
///
/// Android begrenzt schon beim Tippen (`AddPosterFormFields.kt`, `ManualAddressFallbackSection`,
/// Tourname auf der Karte). Ohne denselben Deckel hier wandert beliebig langer Text in Stand,
/// Sync-Paket und Verwaltungs-CSV — und ein Team mit beiden Plattformen hätte zwei verschiedene
/// Regeln für dasselbe Feld.
public enum EingabeGrenzen {
    /// Handeingabe-Adresse und Standort-Hinweis.
    public static let adresse = 160
    /// Einzeiler, zum Beispiel der Name einer Flyer-Tour.
    public static let einzeiler = 80
    /// Verwaltungs- und interne Bemerkung.
    public static let bemerkung = 500

    /// Hartes Kappen, auch beim Einfügen aus der Zwischenablage.
    public static func kappe(_ text: String, auf maximum: Int) -> String {
        String(text.prefix(maximum))
    }

    /// Android startet eine Tour nur bei `isNotBlank`. Whitespace zählt nicht als Name.
    public static func istLeererName(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
