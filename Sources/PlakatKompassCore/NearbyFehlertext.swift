import Foundation

/// Aus einem Nearby-Fehler einen Satz machen, mit dem jemand auf der Strasse etwas anfangen kann.
///
/// Gegenstück zu `core/NearbyFehlertext.kt`. Was die Bibliothek liefert, sieht aus wie
/// „Local network access denied" oder „The Internet connection appears to be offline". Für die
/// Fehlersuche im Protokoll ist das richtig und bleibt dort auch stehen — vor jemandem, der bei
/// Regen an einer Laterne steht, ist es wertlos.
///
/// **Anders als das Android-Vorbild, weil der Funkweg ein anderer ist.** Dort meldet sich
/// Bluetooth oder der fehlende Standortzugriff über GMS-Fehlercodes wie `MISSING_PERMISSION_*`
/// oder `BLUETOOTH`. Auf iOS trägt laut `NearbyAbgleich` nur das **WLAN** — der Funkweg läuft über
/// Bonjour/mDNS (siehe `NSLocalNetworkUsageDescription` und `NSBonjourServices` in
/// `App/Info.plist`), nicht über CoreBluetooth oder MultipeerConnectivity. Die mit Abstand
/// häufigste Ursache ist deshalb die verweigerte „Lokales Netzwerk"-Erlaubnis, für die iOS — genau
/// wie beim Standortzugriff auf Android — keine Abfrage anbietet, ob sie erteilt wurde: Nur der
/// Fehlertext beim ersten Suchlauf verrät es.
///
/// **Zeichenkettenvergleich wie beim Vorbild, aus demselben Grund:** Weder das System noch das
/// Nearby-Paket liefern hierfür einen stabilen Fehlercode über die Rückrufe in `NearbyAbgleich`
/// und `HandywechselNearby` — nur `Error.localizedDescription`. Ein Tippfehler im Suchbegriff
/// fiele niemandem auf, weil der letzte Zweig immer einen brauchbaren Satz liefert. Der Test
/// daneben hält die Zweige fest.
public enum NearbyFehlertext {

    /// Der Rückfallsatz. Er nennt die zwei Stellen, an denen es auf iOS am häufigsten liegt.
    public static let allgemein =
        "Bitte WLAN einschalten und in den Einstellungen unter PlakatKompass „Lokales Netzwerk“ erlauben, dann erneut versuchen."

    public static func fuer(_ fehler: Error?) -> String {
        fuer(fehler?.localizedDescription)
    }

    public static func fuer(_ meldung: String?) -> String {
        let text = meldung ?? ""

        let erlaubnisFehlt = ["local network", "not permitted", "denied"]
        if erlaubnisFehlt.contains(where: { enthaelt(text, $0) }) {
            return "Es fehlt die Erlaubnis für das lokale Netzwerk. Bitte in den iOS-Einstellungen "
                + "unter PlakatKompass „Lokales Netzwerk“ erlauben."
        }

        let keinNetz = ["offline", "network is down", "host is down", "no route to host", "host unreachable"]
        if keinNetz.contains(where: { enthaelt(text, $0) }) {
            return "Kein WLAN verfügbar. Bitte prüfen, ob dieses iPhone im selben WLAN oder Hotspot "
                + "wie das andere Gerät ist."
        }

        if enthaelt(text, "timed out") || enthaelt(text, "timeout") {
            return "Zeitüberschreitung beim Verbindungsaufbau. Bitte prüfen, ob beide Geräte im "
                + "selben WLAN sind, und es noch einmal versuchen."
        }

        return allgemein
    }

    private static func enthaelt(_ text: String, _ suchbegriff: String) -> Bool {
        text.range(of: suchbegriff, options: .caseInsensitive) != nil
    }
}
