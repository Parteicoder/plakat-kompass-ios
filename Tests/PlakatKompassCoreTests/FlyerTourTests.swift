import Foundation
import XCTest
@testable import PlakatKompassCore

/// Flyer-Touren: starten, Wegpunkte sammeln, pausieren, beenden, löschen.
final class FlyerTourTests: XCTestCase {

    private var ordner: URL!
    private var repo: LocalRepository!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        repo = try LocalRepository(ordner: ordner, geraeteName: "Test")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func stand() -> LocalTeamState {
        LocalTeamState(
            deviceId: "me", deviceName: "Ich", role: .MEMBER,
            teamId: "team-1", teamName: "Team", teamSecret: "secret"
        )
    }

    func testTourStartenLegtSieAnUndHinterlaesstEinEreignis() throws {
        let nachher = try repo.startFlyerTour(stand(), name: "  Eilenburg Nord  ")
        let tour = try XCTUnwrap(nachher.flyerTours.first)

        XCTAssertEqual(tour.name, "Eilenburg Nord", "Leerzeichen aussen weg.")
        XCTAssertEqual(tour.status, .ACTIVE)
        XCTAssertTrue(tour.points.isEmpty)
        XCTAssertEqual(nachher.events.first?.action, "Flyer-Tour gestartet: Eilenburg Nord")
    }

    func testOhneNamenGibtEsEinenErsatznamen() throws {
        let nachher = try repo.startFlyerTour(stand(), name: "   ")
        XCTAssertEqual(nachher.flyerTours.first?.name, "Flyer-Tour")
    }

    func testNurEineOffeneTourJeGeraet() throws {
        // Zwei gleichzeitig ergeben keinen Sinn - man laeuft nur einen Weg - und beim
        // Zusammenfuehren wuesste niemand, welche die Wegpunkte bekommen soll.
        let einmal = try repo.startFlyerTour(stand(), name: "Erste")
        XCTAssertThrowsError(try repo.startFlyerTour(einmal, name: "Zweite")) { fehler in
            guard case .nichtErlaubt = fehler as? SyncError else {
                return XCTFail("Erwartet wurde nichtErlaubt, kam: \(fehler)")
            }
        }
    }

    func testNachDemBeendenGehtEineNeueTour() throws {
        var s = try repo.startFlyerTour(stand(), name: "Erste")
        s = try repo.setFlyerTourStatus(s, tour: try XCTUnwrap(s.flyerTours.first), status: .FINISHED)

        XCTAssertNoThrow(try repo.startFlyerTour(s, name: "Zweite"))
    }

    func testWegpunkteHaengenSichAn() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let id = try XCTUnwrap(s.flyerTours.first?.id)

        s = try repo.addFlyerTrackPoint(s, tourId: id, latitude: 51.46, longitude: 12.63)
        s = try repo.addFlyerTrackPoint(s, tourId: id, latitude: 51.47, longitude: 12.64)

        let tour = try XCTUnwrap(s.flyerTours.first)
        XCTAssertEqual(tour.points.count, 2)
        XCTAssertEqual(tour.points.last?.latitude, 51.47)
    }

    func testUngueltigeKoordinateKommtNichtInDenStand() throws {
        // Ein NaN vom Ortungsdienst wuerde sonst das ganze JSON unschreibbar machen - und
        // damit den kompletten Datenstand beim naechsten Speichern verlieren.
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let id = try XCTUnwrap(s.flyerTours.first?.id)

        XCTAssertThrowsError(try repo.addFlyerTrackPoint(s, tourId: id, latitude: .nan, longitude: 12.63))
        XCTAssertThrowsError(try repo.addFlyerTrackPoint(s, tourId: id, latitude: 91, longitude: 12.63))

        s = repo.load()
        XCTAssertTrue(s.flyerTours.first?.points.isEmpty ?? false)
    }

    func testPausierteTourNimmtKeineWegpunkte() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let tour = try XCTUnwrap(s.flyerTours.first)
        s = try repo.setFlyerTourStatus(s, tour: tour, status: .PAUSED)

        XCTAssertThrowsError(try repo.addFlyerTrackPoint(s, tourId: tour.id, latitude: 51.46, longitude: 12.63))
    }

    func testBeendenSetztDenZeitpunkt() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let tour = try XCTUnwrap(s.flyerTours.first)
        s = try repo.setFlyerTourStatus(s, tour: tour, status: .FINISHED)

        let beendet = try XCTUnwrap(s.flyerTours.first)
        XCTAssertEqual(beendet.status, .FINISHED)
        XCTAssertNotNil(beendet.finishedAt)
        XCTAssertEqual(s.events.first?.action, "Flyer-Tour beendet: Tour")
    }

    func testPausierenUndFortsetzen() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        var tour = try XCTUnwrap(s.flyerTours.first)

        s = try repo.setFlyerTourStatus(s, tour: tour, status: .PAUSED)
        XCTAssertEqual(s.flyerTours.first?.status, .PAUSED)
        XCTAssertNil(s.flyerTours.first?.finishedAt, "Pausieren ist kein Beenden.")

        tour = try XCTUnwrap(s.flyerTours.first)
        s = try repo.setFlyerTourStatus(s, tour: tour, status: .ACTIVE)
        XCTAssertEqual(s.flyerTours.first?.status, .ACTIVE)
    }

    func testLoeschenEntferntSieUndHinterlaesstEinEreignis() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let tour = try XCTUnwrap(s.flyerTours.first)

        s = try repo.deleteFlyerTour(s, tour: tour)

        XCTAssertTrue(s.flyerTours.isEmpty)
        XCTAssertEqual(s.events.first?.action, "Flyer-Tour gelöscht: Tour")
    }

    func testAllesLandetAufDerPlatte() throws {
        var s = try repo.startFlyerTour(stand(), name: "Tour")
        let id = try XCTUnwrap(s.flyerTours.first?.id)
        s = try repo.addFlyerTrackPoint(s, tourId: id, latitude: 51.46, longitude: 12.63)

        XCTAssertEqual(repo.load().flyerTours.first?.points.count, 1)
    }
}
