import Foundation
import XCTest
@testable import PlakatKompassCore

/// Hält die Zuordnung der Nearby-Fehlertexte fest, damit ein Tippfehler im Suchbegriff auffällt
/// — sonst würde ihn niemand bemerken, weil der Rückfallsatz immer einen brauchbaren Text liefert.
final class NearbyFehlertextTests: XCTestCase {

    func testLokalesNetzwerkVerweigert() {
        let text = NearbyFehlertext.fuer("Local Network access was denied by the user")
        XCTAssertTrue(text.contains("Lokales Netzwerk"))
    }

    func testKeinWlan() {
        let text = NearbyFehlertext.fuer("The Internet connection appears to be offline.")
        XCTAssertTrue(text.contains("WLAN"))
    }

    func testZeitueberschreitung() {
        let text = NearbyFehlertext.fuer("Operation timed out")
        XCTAssertTrue(text.contains("Zeitüberschreitung"))
    }

    func testUnbekannterFehlerFaelltAufAllgemeinZurueck() {
        XCTAssertEqual(NearbyFehlertext.fuer("irgendein rätselhafter Fehlercode 42"), NearbyFehlertext.allgemein)
    }

    func testLeereMeldungFaelltAufAllgemeinZurueck() {
        XCTAssertEqual(NearbyFehlertext.fuer(nil as String?), NearbyFehlertext.allgemein)
    }
}
