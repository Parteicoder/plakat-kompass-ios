import Foundation
import XCTest
@testable import PlakatKompassCore

/// Portierung von `SyncImportSummaryTest.kt`.
final class SyncImportSummaryTests: XCTestCase {

    // Feste Zeitstempel: Mit `Date.nowMillis` wären zwei getrennt erzeugte Plakate desselben
    // Standes nie gleich, und "unverändert" ließe sich nicht prüfen.
    private func poster(id: String, address: String = "Bahnhofstr. 1") -> Poster {
        Poster(
            id: id,
            teamId: "team-1",
            latitude: 51.4614,
            longitude: 12.6353,
            addressHint: address,
            createdByDeviceId: "device-1",
            createdByName: "David",
            createdAt: 1_700_000_000_000,
            updatedAt: 1_700_000_000_000
        )
    }

    private func state(_ posters: Poster...) -> LocalTeamState {
        LocalTeamState(deviceId: "device-1", deviceName: "Handy", teamId: "team-1", posters: posters)
    }

    func testCountsNewPosters() {
        let text = syncImportSummary(before: state(), after: state(poster(id: "a"), poster(id: "b")), source: "Sync-Paket")
        XCTAssertEqual(text, "Sync-Paket erfolgreich importiert: 2 Plakate neu, 0 aktualisiert, 0 unverändert.")
    }

    func testCountsChangedAndUnchangedApart() {
        let before = state(poster(id: "a"), poster(id: "b"))
        let after = state(poster(id: "a"), poster(id: "b", address: "Neue Adresse 2"))
        let text = syncImportSummary(before: before, after: after, source: "Funk-Abgleich")
        XCTAssertEqual(text, "Funk-Abgleich erfolgreich importiert: 0 Plakate neu, 1 aktualisiert, 1 unverändert.")
    }

    func testMentionsTeamWideDeletionsOnlyWhenTheyHappened() {
        let before = state(poster(id: "a"), poster(id: "b"))
        let mitLoeschung = syncImportSummary(before: before, after: state(poster(id: "a")), source: "Sync-Paket")
        XCTAssertTrue(mitLoeschung.hasSuffix(", 1 teamweit gelöscht."))

        let ohneLoeschung = syncImportSummary(before: before, after: before, source: "Sync-Paket")
        XCTAssertTrue(ohneLoeschung.hasSuffix("unverändert."))
    }
}
