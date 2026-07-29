import Foundation
import XCTest
@testable import PlakatKompassCore

/// Zahlen der Startseite und „nächstes Plakat". Fälle aus `NearestPosterTest.kt`.
final class HomeStatsTests: XCTestCase {

    private func plakat(
        _ id: String, _ status: PosterStatus = .HANGING,
        lat: Double = 51.46, lon: Double = 12.63
    ) -> Poster {
        Poster(
            id: id, teamId: "t", latitude: lat, longitude: lon,
            status: status, createdByDeviceId: "d", createdByName: "n"
        )
    }

    // MARK: - Zahlen

    func testDieVierZahlenUeberschneidenSichAbsichtlich() {
        let stats = HomeStats(posters: [
            plakat("1", .HANGING),
            plakat("2", .CHECKED),
            plakat("3", .DAMAGED),
            plakat("4", .MISSING),
            plakat("5", .REMOVED)
        ])

        XCTAssertEqual(stats.aktiv, 4, "Alles ausser Entfernt.")
        XCTAssertEqual(stats.kontrolliert, 1)
        XCTAssertEqual(stats.probleme, 2, "Beschaedigt und Fehlt.")
        XCTAssertEqual(stats.entfernt, 1)

        // Ein beschaedigtes Plakat zaehlt in zwei Zahlen. Wer sie addiert, bekommt Unsinn -
        // das ist Absicht, sie beantworten vier getrennte Fragen.
        XCTAssertNotEqual(stats.aktiv + stats.entfernt, stats.kontrolliert + stats.probleme + 5)
    }

    func testOhnePlakateAllesNull() {
        let stats = HomeStats(posters: [])
        XCTAssertEqual([stats.aktiv, stats.kontrolliert, stats.probleme, stats.entfernt], [0, 0, 0, 0])
    }

    // MARK: - Entfernung

    func testEntfernungZwischenZweiPunkten() {
        // Leipzig Hbf -> Voelkerschlachtdenkmal, rund 3,5 km Luftlinie.
        let meter = NearestPoster.distanceMeters(51.3459, 12.3833, 51.3122, 12.4131)
        XCTAssertEqual(meter, 4100, accuracy: 400)
    }

    func testDerselbePunktIstNullMeterEntfernt() {
        XCTAssertEqual(NearestPoster.distanceMeters(51.46, 12.63, 51.46, 12.63), 0, accuracy: 0.001)
    }

    func testDasNaechstePlakatGewinnt() {
        let nah = plakat("nah", lat: 51.4601, lon: 12.6301)
        let fern = plakat("fern", lat: 51.50, lon: 12.70)

        let treffer = NearestPoster.find([fern, nah], latitude: 51.46, longitude: 12.63)
        XCTAssertEqual(treffer?.poster.id, "nah")
    }

    func testEntfernteWerdenUebergangen() {
        // Ein abgenommenes Plakat ist kein Ziel mehr.
        let treffer = NearestPoster.find(
            [plakat("weg", .REMOVED, lat: 51.4601, lon: 12.6301), plakat("da", lat: 51.50, lon: 12.70)],
            latitude: 51.46, longitude: 12.63
        )
        XCTAssertEqual(treffer?.poster.id, "da")
    }

    func testOhnePlakateKeinTreffer() {
        XCTAssertNil(NearestPoster.find([], latitude: 51.46, longitude: 12.63))
        XCTAssertNil(NearestPoster.find([plakat("weg", .REMOVED)], latitude: 51.46, longitude: 12.63))
    }

    // MARK: - Text

    func testEntfernungsText() {
        XCTAssertEqual(NearestPoster.distanceText(0), "0 m")
        XCTAssertEqual(NearestPoster.distanceText(250.7), "250 m")
        XCTAssertEqual(NearestPoster.distanceText(999), "999 m")
        XCTAssertEqual(NearestPoster.distanceText(1500), "1,5 km")
        // Ab zehn Kilometern ohne Nachkommastelle: "12,4 km" hilft niemandem weiter als "12 km".
        XCTAssertEqual(NearestPoster.distanceText(12_400), "12 km")
    }
}
