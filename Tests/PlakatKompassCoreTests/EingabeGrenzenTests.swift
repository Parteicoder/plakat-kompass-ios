import XCTest

@testable import PlakatKompassCore

final class EingabeGrenzenTests: XCTestCase {

    func testZahlenStimmenMitAndroidUeberein() {
        XCTAssertEqual(EingabeGrenzen.adresse, 160)
        XCTAssertEqual(EingabeGrenzen.einzeiler, 80)
        XCTAssertEqual(EingabeGrenzen.bemerkung, 500)
    }

    func testKappeSchneidetUeberlangesAb() {
        let lang = String(repeating: "a", count: 200)
        XCTAssertEqual(EingabeGrenzen.kappe(lang, auf: 160).count, 160)
        XCTAssertEqual(EingabeGrenzen.kappe("kurz", auf: 160), "kurz")
    }

    func testLeererTournameIstKeinStart() {
        XCTAssertTrue(EingabeGrenzen.istLeererName("   "))
        XCTAssertTrue(EingabeGrenzen.istLeererName(""))
        XCTAssertFalse(EingabeGrenzen.istLeererName("Nord"))
    }
}
