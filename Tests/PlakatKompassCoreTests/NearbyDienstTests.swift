import XCTest
@testable import PlakatKompassCore

/// Prüft die einzige Zeichenkette im Funk-Abgleich, deren Fehler **lautlos** ist.
///
/// Steht in `NSBonjourServices` ein falscher Typ, blockt iOS die Suche ohne Meldung: kein Absturz,
/// kein Log, kein roter Lauf. Auf dem iPhone sieht das aus wie „niemand in der Nähe", und man sucht
/// den Fehler tagelang beim WLAN, beim Team-Schlüssel oder beim Android-Gerät.
///
/// Deshalb wird die Ableitung nicht abgeschrieben, sondern gerechnet und gegen Googles **eigenes**
/// Beispiel geprüft. Der Wert stammt aus deren Beispiel-App, nicht aus dieser Fassung — sonst
/// bestätigte der Test nur, dass diese Fassung mit sich selbst übereinstimmt.
final class NearbyDienstTests: XCTestCase {

    /// `connections/swift/NearbyConnections/Example/iOS-Example-Info.plist` in `google/nearby`
    /// führt für die Dienstkennung `com.google.location.nearby.apps.helloconnections` genau
    /// `_307BEAB11028._tcp`. Trifft unsere Ableitung das, trifft sie auch jede andere Kennung.
    func testGooglesEigenesBeispielWirdGetroffen() {
        XCTAssertEqual(
            NearbyDienst.bonjourTyp(fuer: "com.google.location.nearby.apps.helloconnections"),
            "_307BEAB11028._tcp"
        )
    }

    /// Dieser Wert muss wörtlich in `App/Info.plist` unter `NSBonjourServices` stehen.
    /// Wer [NearbyDienst.kennung] ändert, ändert ihn mit — und dieser Test sagt es.
    func testTypDieserApp() {
        XCTAssertEqual(NearbyDienst.bonjourTyp, "_EA0A851F84A0._tcp")
    }

    /// Ein Tippfehler in der Dienstkennung ergäbe zwei Apps, die sich nicht sehen.
    func testKennungPasstZuAndroid() {
        XCTAssertEqual(NearbyDienst.kennung, "de.bsw.plakatradar.LOCAL_SYNC")
        XCTAssertEqual(NearbyDienst.namensPraefix, "PlakatRadar|")
    }

    // MARK: - Handywechsel

    /// Zweiter Dienst, zweiter Typ, dieselbe lautlose Falle. Muss wörtlich in `App/Info.plist`
    /// stehen — sonst sucht das iPhone beim Umzug ins Leere.
    func testTypDesHandywechsels() {
        XCTAssertEqual(NearbyDienst.backupKennung, "de.bsw.plakatradar.DEVICE_BACKUP")
        XCTAssertEqual(NearbyDienst.backupBonjourTyp, "_27F69BB0892F._tcp")
        XCTAssertEqual(NearbyDienst.transferSchluesselPraefix, "PRBACKUP2-KEY\n")
    }

    /// Die beiden Dienste dürfen sich niemals treffen.
    func testAbgleichUndHandywechselSindGetrennt() {
        XCTAssertNotEqual(NearbyDienst.bonjourTyp, NearbyDienst.backupBonjourTyp)
        XCTAssertNotEqual(NearbyDienst.kennung, NearbyDienst.backupKennung)
    }

    /// **Über Kreuz, sonst gar nicht.** Zwei Sender fänden sich sonst gegenseitig und warteten,
    /// bis einer aufgibt — auf beiden Bildschirmen stünde „Verbindung wird aufgebaut".
    func testNurGegensaetzlicheRollenVerbindenSich() {
        let alt = NearbyDienst.BackupRolle.senden
        let neu = NearbyDienst.BackupRolle.empfangen

        XCTAssertTrue(alt.passtZu(endpunktName: neu.endpunktName(zeit: 1)))
        XCTAssertTrue(neu.passtZu(endpunktName: alt.endpunktName(zeit: 1)))
        XCTAssertFalse(alt.passtZu(endpunktName: alt.endpunktName(zeit: 1)))
        XCTAssertFalse(neu.passtZu(endpunktName: neu.endpunktName(zeit: 1)))
    }

    /// Ein fremder Endpunkt darf nicht durchrutschen — auch keiner des Abgleichs.
    func testFremdeEndpunktnamenWerdenAbgelehnt() {
        let alt = NearbyDienst.BackupRolle.senden
        XCTAssertFalse(alt.passtZu(endpunktName: "PlakatRadar|Davids iPhone|abc12345"))
        XCTAssertFalse(alt.passtZu(endpunktName: "PlakatRadarBackup|"))
        XCTAssertFalse(alt.passtZu(endpunktName: ""))
        XCTAssertFalse(alt.passtZu(endpunktName: "Irgendwas|RECEIVE|1"))
    }

    /// Der Name im Verbindungswunsch ist auf Android die **lange** Form (`mode.name`), der beim
    /// Ankündigen die kurze. Diese Asymmetrie ist nachgebildet, nicht begradigt — wer sie
    /// „aufräumt", macht den Umzug zwischen Android und iPhone unmöglich.
    func testVerbindungsnameFolgtDerAndroidSchreibweise() {
        XCTAssertEqual(NearbyDienst.BackupRolle.senden.verbindungsName, "PlakatRadarBackup|SENDING|local")
        XCTAssertEqual(NearbyDienst.BackupRolle.empfangen.verbindungsName, "PlakatRadarBackup|RECEIVING|local")
        XCTAssertEqual(NearbyDienst.BackupRolle.senden.endpunktName(zeit: 42), "PlakatRadarBackup|SEND|42")
    }

    /// Der Nonce im Handschlag: 32 Byte als Kleinhex, und zweimal nacheinander nicht derselbe.
    func testNonceHatLaengeUndWiederholtSichNicht() {
        let a = Crypto.randomNonceHex()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertNotEqual(a, Crypto.randomNonceHex())
    }
}
