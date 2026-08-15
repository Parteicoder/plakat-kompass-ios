import XCTest
@testable import PlakatKompassCore

final class PosterFilterTests: XCTestCase {
    private let jetzt: Int64 = 1_700_000_000_000

    private func plakat(
        status: PosterStatus = .HANGING,
        frist: Int64? = nil
    ) -> Poster {
        Poster(
            teamId: "t",
            latitude: 52.5,
            longitude: 13.4,
            status: status,
            createdByDeviceId: "g",
            createdByName: "Gerät",
            plannedRemovalAt: frist
        )
    }

    func testAktivLaesstEntfernteWeg() {
        XCTAssertTrue(PosterFilter.aktiv.passt(plakat(status: .HANGING), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.aktiv.passt(plakat(status: .REMOVED), jetzt: jetzt))
    }

    func testOhneFristNiemalsUeberfaellig() {
        // Der Fallstrick: Waere der Ersatzwert 0 statt Int64.max, gaelte jedes Plakat ohne Frist
        // als ueberfaellig - und die Liste "Ueberfaellig" waere voll mit Plakaten, fuer die nie
        // eine Frist gesetzt wurde.
        XCTAssertFalse(PosterFilter.ueberfaellig.passt(plakat(frist: nil), jetzt: jetzt))
    }

    func testUeberfaelligNurWennFristVorbeiUndNichtEntfernt() {
        XCTAssertTrue(PosterFilter.ueberfaellig.passt(plakat(frist: jetzt - 1), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.ueberfaellig.passt(plakat(frist: jetzt + 1), jetzt: jetzt))
        // Abgenommen und ueberfaellig heisst: erledigt, nicht offen.
        XCTAssertFalse(
            PosterFilter.ueberfaellig.passt(plakat(status: .REMOVED, frist: jetzt - 1), jetzt: jetzt)
        )
    }

    func testProblemeSindBeschaedigtUndVerschwunden() {
        XCTAssertTrue(PosterFilter.probleme.passt(plakat(status: .DAMAGED), jetzt: jetzt))
        XCTAssertTrue(PosterFilter.probleme.passt(plakat(status: .MISSING), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.probleme.passt(plakat(status: .CHECKED), jetzt: jetzt))
    }

    func testKontrolliertNurStatusChecked() {
        XCTAssertTrue(PosterFilter.kontrolliert.passt(plakat(status: .CHECKED), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.kontrolliert.passt(plakat(status: .HANGING), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.kontrolliert.passt(plakat(status: .REMOVED), jetzt: jetzt))
    }

    func testEntferntNurStatusRemoved() {
        XCTAssertTrue(PosterFilter.entfernt.passt(plakat(status: .REMOVED), jetzt: jetzt))
        XCTAssertFalse(PosterFilter.entfernt.passt(plakat(status: .HANGING), jetzt: jetzt))
    }

    func testAlleLaesstAllesDurch() {
        for status in PosterStatus.allCases {
            XCTAssertTrue(PosterFilter.alle.passt(plakat(status: status), jetzt: jetzt))
        }
    }
}
