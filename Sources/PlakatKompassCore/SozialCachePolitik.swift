import Foundation

/// Die zwei Regeln des Sozialdaten-Zwischenspeichers, die still brechen können.
///
/// **Warum das hier steht und nicht beim Cache selbst:** Der Cache lebt im App-Ziel, und das
/// hat kein Test-Ziel — er hängt an `UserDefaults`, am Dateisystem und am Hauptakteur. Diese
/// beiden Regeln hängen an gar nichts und sind trotzdem die Stellen, an denen ein Fehler
/// **lautlos** wäre:
///
/// - Wer den Vergleich verdreht, bekommt einen Zwischenspeicher, der entweder nie trifft
///   (dann ist er nutzlos) oder nie abläuft (dann zeigt die App auf Dauer alte Zahlen).
/// - Wer die Null vergisst, behält Daten, obwohl jemand ausdrücklich „nicht zwischenspeichern"
///   eingestellt hat.
///
/// Beides sieht man der App nicht an. Deshalb liegen die Regeln dort, wo Tests hinkommen.
public enum SozialCachePolitik {

    /// Voreinstellung und Grenzen wortgleich mit `SocialDataSettingsStore.kt`.
    public static let vorgabeTage = 7
    public static let minTage = 0
    public static let maxTage = 90

    /// Wie lange ein Eintrag gilt. **`nil` heisst ausdrücklich „gar nicht behalten"** — nicht
    /// „unbegrenzt". Das ist die Bedeutung von null eingestellten Tagen.
    ///
    /// Werte über [maxTage] werden gekappt statt abgelehnt: Ein zu grosser Eintrag in den
    /// Voreinstellungen soll den Zwischenspeicher nicht abschalten, sondern begrenzen.
    public static func haltbarkeit(tage: Int) -> TimeInterval? {
        guard tage > 0 else { return nil }
        return TimeInterval(min(tage, maxTage)) * 24 * 60 * 60
    }

    /// Ist ein Eintrag dieses Alters noch gültig?
    ///
    /// Negatives Alter — ein Eintrag, der in der Zukunft liegt — gilt als **nicht** frisch.
    /// Das passiert, wenn jemand die Uhr des Telefons zurückstellt, und ein Eintrag, der
    /// dadurch scheinbar nie abläuft, wäre schlimmer als einer zu viel geholter.
    public static func istFrisch(alterSekunden: TimeInterval, tage: Int) -> Bool {
        guard let frist = haltbarkeit(tage: tage) else { return false }
        return alterSekunden >= 0 && alterSekunden <= frist
    }
}
