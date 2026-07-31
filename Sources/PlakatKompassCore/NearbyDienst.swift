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
}
