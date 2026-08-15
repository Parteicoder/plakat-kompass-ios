import Foundation
import XCTest
@testable import PlakatKompassCore

/// Auswertung der Overpass-Antwort für den amtlichen Gebietsschlüssel. Gegenstück zu
/// `GebietsschluesselClientTest.kt`.
///
/// Geprüft wird das Auslesen der Antwort, nicht die Abfrage selbst — die braucht Netz und gehört
/// damit nicht in einen Unit-Test.
final class GebietsschluesselQueryTests: XCTestCase {

    private func antwort(_ elemente: String...) -> String {
        "{\"elements\":[\(elemente.joined(separator: ","))]}"
    }

    private func relation(level: String, name: String, merkmal: String, wert: String) -> String {
        "{\"type\":\"relation\",\"tags\":{\"admin_level\":\"\(level)\",\"name\":\"\(name)\",\"\(merkmal)\":\"\(wert)\"}}"
    }

    // MARK: - Kreisebene (Europawahl)

    func testKreisEbeneHatVorrangVorDerGemeinde() {
        // Der Nutzer erwartet den Kreisnamen. Die Gemeinde trägt denselben Schlüssel, aber den
        // falschen Namen dafür.
        let json = antwort(
            relation(level: "8", name: "Eilenburg", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730080"),
            relation(level: "6", name: "Landkreis Nordsachsen", merkmal: "de:regionalschluessel", wert: "147300000000")
        )
        XCTAssertEqual(GebietsschluesselQuery.kreis(json), Kreis(schluessel: "14730", name: "Landkreis Nordsachsen"))
    }

    func testOhneKreisEbeneReichtDieGemeinde() {
        // Kreisfreie Städte liegen je nach Gegend nur auf einer der beiden Ebenen.
        let json = antwort(relation(level: "8", name: "Leipzig", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14713000"))
        XCTAssertEqual(GebietsschluesselQuery.kreis(json), Kreis(schluessel: "14713", name: "Leipzig"))
    }

    func testDerSchluesselWirdAufFuenfStellenGekuerzt() {
        XCTAssertEqual(GebietsschluesselQuery.kreisschluessel("147300000000"), "14730")
        XCTAssertEqual(GebietsschluesselQuery.kreisschluessel("14713000"), "14713")
        XCTAssertEqual(GebietsschluesselQuery.kreisschluessel("01001"), "01001")
        // Trennzeichen kommen vor; gezählt werden nur Ziffern.
        XCTAssertEqual(GebietsschluesselQuery.kreisschluessel("14 730 000"), "14730")
    }

    func testZuKurzOderFehlendGiltNicht() {
        XCTAssertNil(GebietsschluesselQuery.kreisschluessel("147"))
        XCTAssertNil(GebietsschluesselQuery.kreisschluessel(""))
        XCTAssertNil(GebietsschluesselQuery.kreisschluessel(nil))
    }

    func testOhneSchluesselKeinKreis() {
        // Eine Grenze ohne amtliches Merkmal nützt nichts - daraus ließe sich keine Zeile finden.
        let json = #"{"elements":[{"type":"relation","tags":{"admin_level":"6","name":"Irgendwas"}}]}"#
        XCTAssertNil(GebietsschluesselQuery.kreis(json))
    }

    func testUnbrauchbareAntwortStuerztNichtAb() {
        XCTAssertNil(GebietsschluesselQuery.kreis("kein json"))
        XCTAssertNil(GebietsschluesselQuery.kreis("{}"))
    }

    // MARK: - Gemeindeebene (Landtagswahlen)

    func testGemeindeEbeneHatVorrangVorDemKreis() {
        let json = antwort(
            relation(level: "6", name: "Landkreis Nordsachsen", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730"),
            relation(level: "8", name: "Eilenburg", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730080")
        )
        XCTAssertEqual(GebietsschluesselQuery.gemeinde(json), Kreis(schluessel: "14730080", name: "Eilenburg"))
    }

    /// Der springende Punkt: Der zwölfstellige Regionalschlüssel ist Land 2 + Regierungsbezirk 1 +
    /// Kreis 2 + **Gemeindeverband 4** + Gemeinde 3. Wer davon die ersten acht Stellen nimmt,
    /// erhält nicht den Gemeindeschlüssel, sondern eine Zahl, die es nicht gibt.
    func testRegionalschluesselWirdRichtigUmgerechnet() {
        XCTAssertEqual(GebietsschluesselQuery.gemeindeschluessel("147305206080"), "14730080")
        // Zum Vergleich: falsch wäre das bloße Abschneiden.
        XCTAssertEqual(String("147305206080".prefix(8)), "14730520")
    }

    func testGemeindeschluesselBrauchtAchtStellen() {
        XCTAssertEqual(GebietsschluesselQuery.gemeindeschluessel("14713000"), "14713000")
        XCTAssertEqual(GebietsschluesselQuery.gemeindeschluessel("14 730 080"), "14730080")
        // Ein reiner Kreisschlüssel reicht nicht - daraus ließe sich keine Gemeinde ableiten.
        XCTAssertNil(GebietsschluesselQuery.gemeindeschluessel("14730"))
        XCTAssertNil(GebietsschluesselQuery.gemeindeschluessel(""))
        XCTAssertNil(GebietsschluesselQuery.gemeindeschluessel(nil))
    }

    func testOhneAchtstelligenSchluesselKeineGemeinde() {
        let json = antwort(relation(level: "8", name: "Eilenburg", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730"))
        XCTAssertNil(GebietsschluesselQuery.gemeinde(json))
    }

    // MARK: - Stadtstaaten

    /// Berlin ist selbst ein Bundesland: Es gibt dort weder eine Kreis- noch eine Gemeindegrenze,
    /// nur die Ebene 4. Ohne sie stünde "Zu diesem Punkt ließ sich das Gebiet nicht bestimmen" -
    /// was nach einem Netzproblem aussähe und keines wäre.
    func testStadtstaatWirdUeberEbeneVierGefunden() {
        let json = antwort(relation(level: "4", name: "Berlin", merkmal: "de:amtlicher_gemeindeschluessel", wert: "11000000"))
        XCTAssertEqual(GebietsschluesselQuery.kreis(json), Kreis(schluessel: "11000", name: "Berlin"))
        XCTAssertEqual(GebietsschluesselQuery.gemeinde(json), Kreis(schluessel: "11000000", name: "Berlin"))
    }

    /// Die Gegenprobe, und die eigentlich wichtige: Wo es Kreis und Gemeinde gibt, darf das
    /// Bundesland **nicht** gewinnen — auch dann nicht, wenn Overpass es zuerst zurückgibt.
    func testBundeslandGewinntNieGegenKreisOderGemeinde() {
        let json = antwort(
            relation(level: "4", name: "Sachsen", merkmal: "de:regionalschluessel", wert: "140000000000"),
            relation(level: "6", name: "Landkreis Nordsachsen", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730"),
            relation(level: "8", name: "Eilenburg", merkmal: "de:amtlicher_gemeindeschluessel", wert: "14730110")
        )
        XCTAssertEqual(GebietsschluesselQuery.kreis(json), Kreis(schluessel: "14730", name: "Landkreis Nordsachsen"))
        XCTAssertEqual(GebietsschluesselQuery.gemeinde(json), Kreis(schluessel: "14730110", name: "Eilenburg"))
    }

    /// Auch der Regionalschlüssel eines Stadtstaats muss sich richtig umrechnen lassen.
    func testRegionalschluesselEinesStadtstaats() {
        let json = antwort(relation(level: "4", name: "Hamburg", merkmal: "de:regionalschluessel", wert: "020000000000"))
        XCTAssertEqual(GebietsschluesselQuery.gemeinde(json), Kreis(schluessel: "02000000", name: "Hamburg"))
    }
}
