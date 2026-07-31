import Foundation
// Fuer SozialCachePolitik: Die beiden Haltbarkeitsregeln liegen im Kern, weil das App-Ziel
// kein Test-Ziel hat. Genau dieser Import hat beim ersten Anlauf gefehlt.
import PlakatKompassCore

/// Antworten der amtlichen Server über App-Starts hinweg behalten — Gegenstück zu
/// `feature/socialdata/SocialResponseCache.kt` und `util/SocialDataSettingsStore.kt`.
///
/// **Warum das mehr ist als Bequemlichkeit.** Bisher lag der Zwischenspeicher nur im
/// Arbeitsspeicher und war bei jedem App-Start weg. Wer mit schlechtem Netz durch ein Viertel
/// läuft, die App zwischendurch schliesst und wieder aufmacht, holt dieselben Zahlen immer
/// wieder neu — über eine Rasterabfrage, die rund fünfzehn Sekunden braucht. Und er belastet
/// dabei einen Server, den die Statistischen Ämter kostenlos bereitstellen.
///
/// **Sieben Tage sind grosszügig, und das ist richtig so:** Zensus- und Regionalatlas-Zahlen
/// ändern sich jährlich. Eine Woche alte Werte sind exakt so gültig wie frisch geholte.
///
/// **Der Ablageort ist bewusst `Caches`.** iOS darf dieses Verzeichnis bei Platzmangel leeren,
/// und genau das soll es dürfen: Alles hier lässt sich jederzeit neu holen. Die erfassten
/// Plakate liegen woanders und sind davon nicht betroffen.
@MainActor
final class SozialdatenCache {

    /// Voreinstellung und Grenzen stehen im Kern — dort, wo sie geprüft werden. Hier nur
    /// durchgereicht, damit die Einstellungsseite sie nicht aus zwei Quellen holen muss.
    static let vorgabeTage = SozialCachePolitik.vorgabeTage
    static let minTage = SozialCachePolitik.minTage
    static let maxTage = SozialCachePolitik.maxTage
    /// Der Schlüssel in den Voreinstellungen. Auch die Einstellungsseite benutzt ihn.
    static let tageSchluessel = "sozialCacheTage"

    /// Wie Android: mehr als das wird nicht behalten, ältestes fliegt zuerst.
    private static let maxEintraege = 300
    /// Nicht bei jedem Treffer auf die Platte. Eine Rasterabfrage schreibt sonst mitten im
    /// Laufen mehrere Hundert Kilobyte, und zwar genau dann, wenn es auf Tempo ankommt.
    private static let schreibVerzoegerungSekunden: UInt64 = 2

    private struct Eintrag: Codable {
        let zeit: Date
        let text: String
    }

    private var eintraege: [String: Eintrag] = [:]
    private var schreiber: Task<Void, Never>?

    private let datei: URL

    static let geteilt = SozialdatenCache()

    init(datei: URL? = nil) {
        self.datei = datei ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sozialdaten-cache.json")
        lade()
    }

    // MARK: - Benutzung

    /// Die eingestellte Zahl der Tage. Fehlt der Eintrag, gilt die Vorgabe — nicht null:
    /// Beim allerersten Start hat noch niemand etwas eingestellt, und „gar nicht behalten"
    /// wäre die falsche Auslegung von „noch nichts gesagt".
    private var eingestellteTage: Int {
        (UserDefaults.standard.object(forKey: Self.tageSchluessel) as? Int) ?? Self.vorgabeTage
    }

    func hole(_ schluessel: String) -> String? {
        guard let eintrag = eintraege[schluessel] else { return nil }
        guard SozialCachePolitik.istFrisch(
            alterSekunden: Date().timeIntervalSince(eintrag.zeit), tage: eingestellteTage
        ) else {
            // Abgelaufenes gleich entfernen, statt es bis zum naechsten Aufraeumen mitzuschleppen.
            eintraege.removeValue(forKey: schluessel)
            return nil
        }
        return eintrag.text
    }

    func merke(_ schluessel: String, _ text: String) {
        guard SozialCachePolitik.haltbarkeit(tage: eingestellteTage) != nil else { return }
        eintraege[schluessel] = Eintrag(zeit: Date(), text: text)
        if eintraege.count > Self.maxEintraege {
            // Aeltestes zuerst. Ohne diese Grenze wuechse die Datei ueber eine Kampagne
            // hinweg unbegrenzt - jede Rasterabfrage ist mehrere Hundert Kilobyte gross.
            let ueberzaehlig = eintraege.count - Self.maxEintraege
            eintraege
                .sorted { $0.value.zeit < $1.value.zeit }
                .prefix(ueberzaehlig)
                .forEach { eintraege.removeValue(forKey: $0.key) }
        }
        planeSchreiben()
    }

    func leeren() {
        eintraege.removeAll()
        schreiber?.cancel()
        schreiber = nil
        try? FileManager.default.removeItem(at: datei)
    }

    /// Wie viel liegt gerade da — für die Anzeige auf der Einstellungsseite. Ein Knopf
    /// „Cache leeren" ohne Zahl daneben sagt niemandem, ob sich das Tippen lohnt.
    var anzahl: Int { eintraege.count }

    // MARK: - Platte

    private func lade() {
        guard let daten = try? Data(contentsOf: datei),
              let gelesen = try? JSONDecoder().decode([String: Eintrag].self, from: daten)
        else { return }
        eintraege = gelesen
    }

    /// Sammelt Änderungen und schreibt erst, wenn zwei Sekunden Ruhe war. Ein neuer Aufruf
    /// verwirft den vorigen Auftrag — sonst schriebe eine Rasterabfrage über 49 Zellen die
    /// Datei ein Dutzend Mal hintereinander.
    private func planeSchreiben() {
        schreiber?.cancel()
        schreiber = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.schreibVerzoegerungSekunden * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.schreibe()
        }
    }

    private func schreibe() {
        guard let daten = try? JSONEncoder().encode(eintraege) else { return }
        try? daten.write(to: datei, options: .atomic)
    }
}
