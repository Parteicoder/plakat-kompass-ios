import CryptoKit
import Foundation

/// Die beiden Zeichenketten, an denen der **Funk-Abgleich** zwischen Android und iPhone hängt.
///
/// Beide sind Vertrag, keine Einstellung:
///
/// - [kennung] muss Zeichen für Zeichen mit `NearbySyncManager.SERVICE_ID` auf Android
///   übereinstimmen. Nearby verbindet nur Geräte mit identischer Dienstkennung; ein Tippfehler
///   ergibt zwei Apps, die sich schlicht nicht sehen, ohne jede Fehlermeldung.
/// - [bonjourTyp] muss in `App/Info.plist` unter `NSBonjourServices` stehen. Seit iOS 14 blockt
///   das System jede mDNS-Suche nach einem Typ, der dort nicht aufgeführt ist — ebenfalls
///   lautlos. Auf dem iPhone sähe das genau so aus wie „kein anderes Gerät in der Nähe".
///
/// Der Typ ist nicht frei wählbar: Nearby leitet ihn aus der Dienstkennung ab
/// (`WifiLan::GenerateServiceType` in `connections/implementation/mediums/wifi_lan.cc`).
/// Deshalb steht die Ableitung hier — und wird geprüft, statt abgeschrieben zu werden.
public enum NearbyDienst {

    /// Gegenstück zu `NearbySyncManager.SERVICE_ID`.
    public static let kennung = "de.bsw.plakatradar.LOCAL_SYNC"

    /// Endpunktname im Handschlag. Android verlangt genau dieses Präfix und lehnt sonst ab.
    public static let namensPraefix = "PlakatRadar|"

    /// Bonjour-Typ zu einer Dienstkennung: `_` + erste sechs Byte von SHA-256, Großhex, `._tcp`.
    ///
    /// Die sechs Byte sind `kTypeFromServiceIdHashLength` in `internal/platform/nsd_service_info.h`.
    public static func bonjourTyp(fuer kennung: String) -> String {
        let anfang = SHA256.hash(data: Data(kennung.utf8)).prefix(6)
        return "_" + anfang.map { String(format: "%02X", $0) }.joined() + "._tcp"
    }

    /// Der Typ dieser App. Muss wörtlich in `App/Info.plist` stehen.
    public static let bonjourTyp = bonjourTyp(fuer: kennung)

    // MARK: - Handywechsel

    /// Gegenstück zu `DeviceBackupNearbyManager.SERVICE_ID`.
    ///
    /// **Ein eigener Dienst, nicht [kennung] mit anderer Nachricht.** Der Grund ist kein
    /// Ordnungssinn: Beim Abgleich verbinden sich *alle* Teamgeräte miteinander, beim
    /// Handywechsel genau zwei — ein altes und ein neues, und das neue hat noch gar kein Team.
    /// Liefen beide über dieselbe Kennung, meldeten sich beim Umzug sämtliche Teamgeräte in
    /// Funkreichweite mit.
    ///
    /// Und weil es ein eigener Dienst ist, hat er einen **eigenen Bonjour-Typ**, der ebenfalls
    /// in die Info.plist muss. Fehlt er, sucht das iPhone lautlos ins Leere — dieselbe Falle
    /// wie beim Abgleich, nur ein zweites Mal.
    public static let backupKennung = "de.bsw.plakatradar.DEVICE_BACKUP"

    /// Der Typ des Handywechsels. Muss ebenfalls wörtlich in `App/Info.plist` stehen.
    public static let backupBonjourTyp = bonjourTyp(fuer: backupKennung)

    /// Endpunktname beim Handywechsel: `PlakatRadarBackup|SEND|<millis>` bzw. `|RECEIVE|`.
    public static let backupPraefix = "PlakatRadarBackup|"

    /// Vor dem Backup schickt das alte Gerät den Transfer-Schlüssel als Byte-Nachricht mit
    /// diesem Präfix. Der Zeilenumbruch gehört dazu — Android trennt daran.
    public static let transferSchluesselPraefix = "PRBACKUP2-KEY\n"

    /// Sende- oder Empfangsseite. Verbunden wird **nur über Kreuz**.
    public enum BackupRolle: String {
        case senden = "SEND"
        case empfangen = "RECEIVE"

        /// Der Name, unter dem sich diese Seite ankündigt.
        public func endpunktName(zeit: Int64) -> String {
            "\(NearbyDienst.backupPraefix)\(rawValue)|\(zeit)"
        }

        /// Passt die Gegenseite? Zwei Sender finden sich sonst gegenseitig und warten ewig.
        public func passtZu(endpunktName: String) -> Bool {
            guard endpunktName.hasPrefix(NearbyDienst.backupPraefix) else { return false }
            let felder = endpunktName.split(separator: "|", omittingEmptySubsequences: false)
            guard felder.count >= 2 else { return false }
            return String(felder[1]) == gegenseite.rawValue
        }

        public var gegenseite: BackupRolle { self == .senden ? .empfangen : .senden }

        /// Der Text, den Android im Verbindungswunsch erwartet — dort `mode.name`, also die
        /// **lange** Form. Nicht dasselbe wie [rawValue]; die Asymmetrie stammt aus dem
        /// Android-Original und wird hier bewusst nachgebildet statt begradigt.
        public var verbindungsName: String {
            "\(NearbyDienst.backupPraefix)\(self == .senden ? "SENDING" : "RECEIVING")|local"
        }
    }
}
