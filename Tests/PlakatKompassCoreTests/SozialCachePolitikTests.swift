import Foundation
import XCTest
@testable import PlakatKompassCore

/// Zwei Regeln, beide lautlos im Fehlerfall — deshalb geprüft.
final class SozialCachePolitikTests: XCTestCase {

    private let tag: TimeInterval = 24 * 60 * 60

    /// **Null heisst „gar nicht behalten", nicht „unbegrenzt".** Wer das verwechselt, baut aus
    /// der Einstellung „nicht zwischenspeichern" das genaue Gegenteil.
    func testNullTageSchaltetDenSpeicherAb() {
        XCTAssertNil(SozialCachePolitik.haltbarkeit(tage: 0))
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: 0, tage: 0))
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: 1, tage: 0))
    }

    func testNegativeTageGeltenWieNull() {
        XCTAssertNil(SozialCachePolitik.haltbarkeit(tage: -3))
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: 10, tage: -3))
    }

    func testVorgabeSindSiebenTage() {
        XCTAssertEqual(SozialCachePolitik.vorgabeTage, 7)
        XCTAssertEqual(SozialCachePolitik.haltbarkeit(tage: 7), 7 * tag)
    }

    /// Ein zu grosser Eintrag soll begrenzen, nicht abschalten.
    func testUeberdasMaximumWirdGekapptNichtAbgelehnt() {
        XCTAssertEqual(SozialCachePolitik.haltbarkeit(tage: 5000), 90 * tag)
        XCTAssertTrue(SozialCachePolitik.istFrisch(alterSekunden: 89 * tag, tage: 5000))
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: 91 * tag, tage: 5000))
    }

    /// Der Vergleich, den man am leichtesten verdreht. Genau auf der Grenze gilt der Eintrag
    /// noch — sonst fiele ein Eintrag mit exakt sieben Tagen durch, obwohl sieben eingestellt ist.
    func testDieGrenzeGehoertNochDazu() {
        XCTAssertTrue(SozialCachePolitik.istFrisch(alterSekunden: 0, tage: 7))
        XCTAssertTrue(SozialCachePolitik.istFrisch(alterSekunden: 7 * tag, tage: 7))
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: 7 * tag + 1, tage: 7))
    }

    /// Wer die Uhr zurückstellt, soll keinen Eintrag bekommen, der nie abläuft.
    func testEintragAusDerZukunftGiltNichtAlsFrisch() {
        XCTAssertFalse(SozialCachePolitik.istFrisch(alterSekunden: -60, tage: 7))
    }
}
