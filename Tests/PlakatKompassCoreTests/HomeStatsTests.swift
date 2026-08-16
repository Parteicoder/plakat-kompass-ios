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

    // MARK: - Richtung

    func testKompassZeigtInDieVierHimmelsrichtungen() {
        let myLat = 51.4614, myLng = 12.6353
        // Die Kompassnadel haengt an diesen Werten: 0 = Norden, 90 = Osten.
        XCTAssertEqual(
            NearestPoster.bearingDegrees(fromLat: myLat, fromLon: myLng, toLat: myLat + 0.01, toLon: myLng),
            0, accuracy: 1.0
        )
        XCTAssertEqual(
            NearestPoster.bearingDegrees(fromLat: myLat, fromLon: myLng, toLat: myLat, toLon: myLng + 0.01),
            90, accuracy: 1.0
        )
        XCTAssertEqual(
            NearestPoster.bearingDegrees(fromLat: myLat, fromLon: myLng, toLat: myLat - 0.01, toLon: myLng),
            180, accuracy: 1.0
        )
        XCTAssertEqual(
            NearestPoster.bearingDegrees(fromLat: myLat, fromLon: myLng, toLat: myLat, toLon: myLng - 0.01),
            270, accuracy: 1.0
        )
    }

    func testKompassBleibtInnerhalbDesVollenKreises() {
        let suedwesten = NearestPoster.bearingDegrees(
            fromLat: 51.4614, fromLon: 12.6353, toLat: 51.4514, toLon: 12.6253
        )
        XCTAssertTrue((180.0...270.0).contains(suedwesten))
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

    // MARK: - Bewertung

    func testBewertungsfensterWartetUndErscheintHoechstensDreimal() {
        let jetzt = Date(timeIntervalSince1970: 2_000_000_000)
        let elfTage = RatingPromptPolicy.wartezeit + 24 * 60 * 60
        let ersterStart = jetzt.addingTimeInterval(-elfTage)

        XCTAssertFalse(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: nil, letzteAnfrage: nil, anzahl: 0, jetzt: jetzt
            )
        )
        XCTAssertFalse(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: jetzt.addingTimeInterval(-RatingPromptPolicy.wartezeit + 1),
                letzteAnfrage: nil,
                anzahl: 0,
                jetzt: jetzt
            )
        )
        XCTAssertTrue(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: ersterStart, letzteAnfrage: nil, anzahl: 0, jetzt: jetzt
            )
        )
        XCTAssertFalse(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: ersterStart,
                letzteAnfrage: jetzt.addingTimeInterval(-RatingPromptPolicy.wartezeit + 1),
                anzahl: 1,
                jetzt: jetzt
            )
        )
        XCTAssertTrue(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: ersterStart,
                letzteAnfrage: jetzt.addingTimeInterval(-elfTage),
                anzahl: 1,
                jetzt: jetzt
            )
        )
        XCTAssertFalse(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: ersterStart,
                letzteAnfrage: nil,
                anzahl: RatingPromptPolicy.maximaleAnfragen,
                jetzt: jetzt
            )
        )
    }

    // Gegenstueck zu RatingPromptPolicyTest.kt: einmal bewertet, nie wieder gefragt - selbst
    // wenn Wartezeit und Zaehler laengst ein "Ja" ergeben wuerden.
    func testKeinFensterMehrNachBereitsBewertet() {
        let jetzt = Date(timeIntervalSince1970: 2_000_000_000)
        let ersterStart = jetzt.addingTimeInterval(-RatingPromptPolicy.wartezeit - 1)

        XCTAssertFalse(
            RatingPromptPolicy.sollAnzeigen(
                ersterStart: ersterStart,
                letzteAnfrage: nil,
                anzahl: 0,
                bereitsBewertet: true,
                jetzt: jetzt
            )
        )
    }
}
