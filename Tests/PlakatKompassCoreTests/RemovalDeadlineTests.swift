import Foundation
import XCTest
@testable import PlakatKompassCore

/// Abnahmefristen. Enthält die vier Fälle aus `RemovalDeadlinePolicyTest.kt` und die Textausgabe,
/// die es drüben nicht als Test gibt.
///
/// Warum das mehr als Kosmetik ist: Wahlplakate müssen innerhalb einer Frist abgenommen werden.
/// Rechnet diese Datei falsch, sieht ein Team seine überfälligen Plakate nicht — und merkt es
/// erst, wenn die Gemeinde sich meldet.
final class RemovalDeadlineTests: XCTestCase {

    private let jetzt: Int64 = 1_700_000_000_000   // 14.11.2023, 22:13:20 UTC
    private let tag: Int64 = 24 * 60 * 60 * 1000

    private func plakat(status: PosterStatus = .HANGING, frist: Int64?) -> Poster {
        Poster(
            id: "p1", teamId: "team-1", latitude: 51.46, longitude: 12.63,
            status: status,
            createdByDeviceId: "device-1", createdByName: "David",
            createdAt: jetzt - 10 * tag, updatedAt: jetzt - 10 * tag,
            plannedRemovalAt: frist
        )
    }

    // MARK: - Statusautomatik

    func testFaelligesPlakatWirdZumProblem() {
        let ergebnis = RemovalDeadlinePolicy.applyToPoster(plakat(frist: jetzt - tag), now: jetzt)

        XCTAssertEqual(ergebnis.status, .DAMAGED)
        XCTAssertEqual(ergebnis.updatedAt, jetzt, "Der Zeitstempel muss mitwandern, sonst gewinnt beim Abgleich die alte Fassung.")
    }

    func testEntferntesPlakatBleibtEntfernt() {
        let ergebnis = RemovalDeadlinePolicy.applyToPoster(
            plakat(status: .REMOVED, frist: jetzt - tag), now: jetzt
        )
        XCTAssertEqual(ergebnis.status, .REMOVED)
    }

    func testPlakatMitFristInDerZukunftBleibtUnberuehrt() {
        let ergebnis = RemovalDeadlinePolicy.applyToPoster(
            plakat(status: .CHECKED, frist: jetzt + 5 * tag), now: jetzt
        )
        XCTAssertEqual(ergebnis.status, .CHECKED)
        XCTAssertEqual(ergebnis.updatedAt, jetzt - 10 * tag, "Ohne Aenderung darf der Zeitstempel nicht wandern.")
    }

    func testPlakatOhneFristBleibtUnberuehrt() {
        let ergebnis = RemovalDeadlinePolicy.applyToPoster(plakat(frist: nil), now: jetzt)
        XCTAssertEqual(ergebnis.status, .HANGING)
    }

    func testZweitesAnwendenAendertNichtsMehr() {
        // Sonst wanderte updatedAt bei jedem App-Start neu und das Plakat gaebe sich beim
        // Abgleich staendig als die neuere Fassung aus.
        let einmal = RemovalDeadlinePolicy.applyToPoster(plakat(frist: jetzt - tag), now: jetzt)
        let zweimal = RemovalDeadlinePolicy.applyToPoster(einmal, now: jetzt + tag)
        XCTAssertEqual(zweimal, einmal)
    }

    func testDerGanzeStandBleibtDerselbeWennNichtsFaelligIst() {
        let stand = LocalTeamState(
            deviceId: "d", deviceName: "n", posters: [plakat(frist: jetzt + 5 * tag)]
        )
        XCTAssertEqual(RemovalDeadlinePolicy.applyToState(stand, now: jetzt), stand)
    }

    // MARK: - Zählung

    func testZaehlungUebergehtEntfernte() {
        let posters = [
            plakat(frist: jetzt - tag),                      // faellig
            plakat(status: .REMOVED, frist: jetzt - tag),    // faellig, aber entfernt
            plakat(frist: jetzt + tag),                      // noch nicht faellig
            plakat(frist: nil)                               // ohne Frist
        ]
        XCTAssertEqual(RemovalDeadlinePolicy.countDueOrOverdue(posters, now: jetzt), 1)
    }

    // MARK: - Text

    func testCountdownInKalendertagen() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = try! XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        func text(_ frist: Int64) -> String? {
            RemovalDeadlinePolicy.removalCountdownText(frist, now: jetzt, kalender: kalender)
        }

        XCTAssertEqual(text(jetzt + 3 * tag), "Noch 3 Tage")
        XCTAssertEqual(text(jetzt + tag), "Morgen abnehmen")
        XCTAssertEqual(text(jetzt), "Heute abnehmen")
        XCTAssertEqual(text(jetzt - tag), "Überfällig seit 1 Tag")
        XCTAssertEqual(text(jetzt - 4 * tag), "Überfällig seit 4 Tagen")
    }

    func testKurzVorMitternachtIstMorgenNichtHeute() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = try! XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        // 22:00 Uhr, Frist am naechsten Morgen um 08:00. Dazwischen liegen zehn Stunden, aber
        // eine Nacht - "Morgen abnehmen" ist richtig, "Heute abnehmen" waere irrefuehrend.
        let abends = Int64(
            kalender.date(from: DateComponents(year: 2024, month: 5, day: 6, hour: 22))!
                .timeIntervalSince1970 * 1000
        )
        let morgenFrueh = Int64(
            kalender.date(from: DateComponents(year: 2024, month: 5, day: 7, hour: 8))!
                .timeIntervalSince1970 * 1000
        )

        XCTAssertEqual(
            RemovalDeadlinePolicy.removalCountdownText(morgenFrueh, now: abends, kalender: kalender),
            "Morgen abnehmen"
        )
    }

    func testOhneFristKeinText() {
        XCTAssertNil(RemovalDeadlinePolicy.removalCountdownText(nil, now: jetzt))
    }

    // MARK: - Deckel auf der Ereignis-Chronik

    private func ereignisse(_ anzahl: Int) -> [PosterEvent] {
        (0..<anzahl).map {
            PosterEvent(
                id: "e\($0)", posterId: "p", teamId: "t",
                actorDeviceId: "d", actorName: "n", action: "Aktion \($0)",
                createdAt: Int64($0)
            )
        }
    }

    func testUnterDemDeckelBleibtAllesStehen() {
        var stand = LocalTeamState(deviceId: "d", deviceName: "n")
        stand.events = ereignisse(RemovalDeadlinePolicy.maxEvents)

        XCTAssertEqual(RemovalDeadlinePolicy.withCappedEvents(stand), stand)
    }

    func testUeberDemDeckelBleibenDieNeuesten() {
        // Ohne Deckel waechst die Chronik ueber eine Kampagne unbegrenzt - und weil der KOMPLETTE
        // Stand bei jeder Aenderung geschrieben wird, wird jedes Speichern langsamer.
        var stand = LocalTeamState(deviceId: "d", deviceName: "n")
        stand.events = ereignisse(RemovalDeadlinePolicy.maxEvents + 50)

        let gedeckelt = RemovalDeadlinePolicy.withCappedEvents(stand)

        XCTAssertEqual(gedeckelt.events.count, RemovalDeadlinePolicy.maxEvents)
        XCTAssertEqual(gedeckelt.events.first?.createdAt, Int64(RemovalDeadlinePolicy.maxEvents + 49))
        XCTAssertEqual(gedeckelt.events.last?.createdAt, 50)
    }

    func testDerDeckelIstDeterministisch() {
        // Alle Teamgeraete muessen nach einem Abgleich auf dieselbe Auswahl kommen, sonst
        // schaukeln sie sich gegenseitig auf und der Abgleich kommt nie zur Ruhe.
        var stand = LocalTeamState(deviceId: "d", deviceName: "n")
        stand.events = ereignisse(RemovalDeadlinePolicy.maxEvents + 10).shuffled()

        var anders = stand
        anders.events = stand.events.shuffled()

        XCTAssertEqual(
            RemovalDeadlinePolicy.withCappedEvents(stand).events.map(\.id),
            RemovalDeadlinePolicy.withCappedEvents(anders).events.map(\.id)
        )
    }

    func testErinnerungstext() {
        XCTAssertNil(RemovalDeadlinePolicy.reminderText(dueCount: 0), "Ohne faellige Plakate keine Meldung.")
        XCTAssertEqual(RemovalDeadlinePolicy.reminderText(dueCount: 1)?.titel, "1 Plakat muss abgenommen werden")
        XCTAssertEqual(RemovalDeadlinePolicy.reminderText(dueCount: 4)?.titel, "4 Plakate müssen abgenommen werden")
    }
}
