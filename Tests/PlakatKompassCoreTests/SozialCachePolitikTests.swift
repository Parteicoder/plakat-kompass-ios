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

    func testVorgabeSindDreissigTage() {
        // Wortgleich mit Android SocialDataSettingsStore.SOCIAL_CACHE_TTL_DEFAULT_DAYS.
        XCTAssertEqual(SozialCachePolitik.vorgabeTage, 30)
        XCTAssertEqual(SozialCachePolitik.haltbarkeit(tage: 30), 30 * tag)
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

    // MARK: - istCachebareAntwort

    /// Der Fall, der auf Android "Zensus mal da, mal nicht" verursacht hat: HTTP 200, aber ein
    /// Fehlerfeld im Rumpf. Genau das darf nicht in den Cache.
    func testFehlerantwortMitStatus200IstNichtCachebar() {
        XCTAssertFalse(SozialCachePolitik.istCachebareAntwort(
            #"{"error":{"code":400,"message":"Ungueltige Anfrage"}}"#
        ))
    }

    /// Eine gültige Antwort ohne Treffer ist eine echte Auskunft, keine Störung — cachebar.
    func testLeereTrefferlisteIstCachebar() {
        XCTAssertTrue(SozialCachePolitik.istCachebareAntwort(#"{"features":[]}"#))
    }

    func testAntwortMitDatenIstCachebar() {
        XCTAssertTrue(SozialCachePolitik.istCachebareAntwort(
            #"{"features":[{"attributes":{"AI0801":7.2}}]}"#
        ))
    }

    func testLeererUndUngueltigerTextIstNichtCachebar() {
        XCTAssertFalse(SozialCachePolitik.istCachebareAntwort(""))
        XCTAssertFalse(SozialCachePolitik.istCachebareAntwort("   "))
        XCTAssertFalse(SozialCachePolitik.istCachebareAntwort("kein json"))
    }
}
