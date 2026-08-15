import Foundation
import XCTest
@testable import PlakatKompassCore

/// Anzeige-Aufbereitung der Parteiergebnisse: kleine Parteien bündeln, sortieren. Gegenstück zu
/// `feature/wahldaten/WahldatenParser.kt` — dort nur indirekt über die Oberfläche geprüft, hier
/// direkt, weil die Regeln (Sonstige nie doppelt, nie leer, immer zuletzt sortiert) leicht beim
/// nächsten Umbau brechen, ohne dass es auffällt.
final class WahldatenParserTests: XCTestCase {

    // MARK: - fasseKleineZusammen

    func testKleineParteienWerdenZuSonstigeGebuendelt() {
        let parteien = [
            Parteiergebnis(partei: "A", prozent: 10),
            Parteiergebnis(partei: "Z-Partei", prozent: 50),
            Parteiergebnis(partei: "Klein1", prozent: 1.0),
            Parteiergebnis(partei: "Klein2", prozent: 0.5)
        ]
        let ergebnis = fasseKleineZusammen(parteien, schwelle: 2.0)

        // Alphabetisch unter den echten Parteien, "Sonstige" aber immer zuletzt - auch wenn es
        // alphabetisch zwischen "A" und "Z-Partei" stünde.
        XCTAssertEqual(ergebnis.map(\.partei), ["A", "Z-Partei", "Sonstige"])
        XCTAssertEqual(ergebnis.last?.prozent ?? 0, 1.5, accuracy: 0.001)
    }

    func testVorhandeneSonstigeWirdEingerechnetNichtVerdoppelt() {
        let parteien = [
            Parteiergebnis(partei: "A", prozent: 84),
            Parteiergebnis(partei: "Sonstige", prozent: 15),
            Parteiergebnis(partei: "Klein", prozent: 1)
        ]
        let ergebnis = fasseKleineZusammen(parteien, schwelle: 2.0)

        XCTAssertEqual(ergebnis.count, 2)
        XCTAssertEqual(ergebnis.filter { $0.partei == "Sonstige" }.count, 1)
        XCTAssertEqual(ergebnis.first { $0.partei == "Sonstige" }?.prozent ?? 0, 16, accuracy: 0.001)
    }

    func testOhneKleineParteienBleibtDieListeUnveraendert() {
        // Absichtlich unsortiert (Z vor A): ohne etwas zum Zusammenfassen wird nicht neu
        // sortiert, die Originalreihenfolge bleibt stehen.
        let parteien = [
            Parteiergebnis(partei: "Z", prozent: 60),
            Parteiergebnis(partei: "A", prozent: 40)
        ]
        let ergebnis = fasseKleineZusammen(parteien, schwelle: 2.0)
        XCTAssertEqual(ergebnis.map(\.partei), ["Z", "A"])
    }

    func testSchwelleIstEinstellbar() {
        let parteien = [
            Parteiergebnis(partei: "A", prozent: 90),
            Parteiergebnis(partei: "B", prozent: 3),
            Parteiergebnis(partei: "C", prozent: 7)
        ]
        // Mit der Vorgabe (2 %) bliebe B stehen - mit 5 % wird es gebündelt.
        XCTAssertTrue(fasseKleineZusammen(parteien, schwelle: 2.0).contains { $0.partei == "B" })
        XCTAssertFalse(fasseKleineZusammen(parteien, schwelle: 5.0).contains { $0.partei == "B" })
    }

    // MARK: - sortiereParteien

    func testAlphabetischOhneRuecksichtAufGrossKleinschreibung() {
        let ergebnis = sortiereParteien(["spd": 20, "AfD": 15, "cdu": 30])
        XCTAssertEqual(ergebnis.map(\.partei), ["AfD", "cdu", "spd"])
    }

    func testSonstigeStehtImmerZuletzt() {
        // Auch mit dem höchsten Stimmenanteil - sortiert wird nie nach Prozent.
        let ergebnis = sortiereParteien(["Sonstige": 99, "AfD": 1])
        XCTAssertEqual(ergebnis.map(\.partei), ["AfD", "Sonstige"])
    }
}
