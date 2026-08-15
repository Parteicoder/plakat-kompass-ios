import Foundation
import XCTest
@testable import PlakatKompassCore

/// Die mitgelieferte Datei `wahlkreise_btw25.geojson` selbst, nicht nur der Algorithmus.
/// Gegenstück zu `WahlkreisBeilageTest.kt`.
///
/// `WahldatenGeometrieTests` prüft den Algorithmus an erfundenen Rechtecken. Dieser Test prüft
/// die echte Beilage — denn genau die kann fehlen (falscher Ressourcenpfad, leere Datei) und ein
/// Test auf dem Algorithmus allein bliebe trotzdem grün.
final class WahlkreisBeilageTests: XCTestCase {

    private let kreise = WahlkreisGrenzen.alle

    func testBeilageIstVorhandenUndLesbar() {
        XCTAssertFalse(kreise.isEmpty, "Beilage ist leer oder unlesbar")
    }

    func testEsSind299WahlkreiseMitLueckenloserNummer() {
        XCTAssertEqual(kreise.count, 299)
        let nummern = kreise.compactMap { Int($0.kennung) }.sorted()
        XCTAssertEqual(nummern, Array(1...299), "Nummern nicht lückenlos 1..299")
    }

    func testJederWahlkreisHatEinenNamen() {
        // Ohne Namen stünde im Panel die nackte Nummer - richtig, aber für niemanden lesbar.
        XCTAssertTrue(kreise.allSatisfy { !$0.name.isEmpty && $0.name != $0.kennung })
    }

    /// Bekannte Orte im richtigen Wahlkreis, quer über die Republik und über beide Geometrietypen.
    /// Dieselben sechs Proben wie im Android-Test, mit denselben Koordinaten — bewusst nicht neu
    /// gewählt, damit ein Abweichen zwischen den Plattformen hier auffiele.
    func testBekannteOrteLiegenImRichtigenWahlkreis() {
        let proben: [(ort: String, longitude: Double, latitude: Double, soll: String)] = [
            ("Eilenburg", 12.6330, 51.4620, "150"),
            ("Leipzig Mitte", 12.3731, 51.3397, "152"),
            ("Berlin Mitte", 13.4050, 52.5200, "074"),
            ("München Marienplatz", 11.5755, 48.1372, "217"),
            ("Hamburg Rathaus", 9.9925, 53.5503, "018"),
            ("Saarbrücken", 6.9969, 49.2354, "296")
        ]
        for probe in proben {
            let treffer = flaecheAn(kreise, longitude: probe.longitude, latitude: probe.latitude)
            XCTAssertEqual(treffer?.kennung, probe.soll, probe.ort)
        }
    }

    func testPunktAusserhalbDeutschlandsTrifftNichts() {
        // Nordsee. Der Nutzer soll "außerhalb der Wahlkreise" sehen, nicht den nächstbesten.
        XCTAssertNil(flaecheAn(kreise, longitude: 6.0, latitude: 55.0))
    }
}
