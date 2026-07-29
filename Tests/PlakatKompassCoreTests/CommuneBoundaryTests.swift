import Foundation
import XCTest
@testable import PlakatKompassCore

/// Auswertung der Overpass-Antwort für Gemeindegrenzen.
final class CommuneBoundaryTests: XCTestCase {

    private func relation(name: String, ebene: String, wege: String) -> String {
        """
        {"type":"relation","tags":{"name":"\(name)","admin_level":"\(ebene)",
        "boundary":"administrative"},"members":[\(wege)]}
        """
    }

    private func weg(_ punkte: String, rolle: String = "outer") -> String {
        "{\"type\":\"way\",\"role\":\"\(rolle)\",\"geometry\":[\(punkte)]}"
    }

    private func antwort(_ elemente: String) -> String {
        "{\"elements\":[\(elemente)]}"
    }

    func testGrenzeWirdGelesen() {
        let json = antwort(relation(
            name: "Eilenburg", ebene: "8",
            wege: weg("{\"lat\":51.46,\"lon\":12.63},{\"lat\":51.47,\"lon\":12.64}")
        ))
        let grenze = CommuneBoundaryQuery.parse(json)

        XCTAssertEqual(grenze?.name, "Eilenburg")
        XCTAssertEqual(grenze?.adminLevel, 8)
        XCTAssertEqual(grenze?.lines.count, 1)
        XCTAssertEqual(grenze?.lines.first?.count, 2)
    }

    func testDieFeinsteEbeneGewinnt() {
        // In einer kreisfreien Stadt liefert Overpass beide. Ebene 6 waere der ganze Kreis -
        // fuer jemanden, der eine Gemeinde beplakatiert, die falsche Flaeche.
        let json = antwort([
            relation(name: "Landkreis Nordsachsen", ebene: "6",
                     wege: weg("{\"lat\":51.0,\"lon\":12.0},{\"lat\":51.1,\"lon\":12.1}")),
            relation(name: "Eilenburg", ebene: "8",
                     wege: weg("{\"lat\":51.46,\"lon\":12.63},{\"lat\":51.47,\"lon\":12.64}"))
        ].joined(separator: ","))

        XCTAssertEqual(CommuneBoundaryQuery.parse(json)?.name, "Eilenburg")
    }

    func testNurEbeneSechsWirdGenommenWennEsNichtsFeineresGibt() {
        let json = antwort(relation(
            name: "Leipzig", ebene: "6",
            wege: weg("{\"lat\":51.34,\"lon\":12.38},{\"lat\":51.35,\"lon\":12.39}")
        ))
        XCTAssertEqual(CommuneBoundaryQuery.parse(json)?.adminLevel, 6)
    }

    func testInnenliegendeWegeWerdenUebergangen() {
        // "inner" ist ein Loch in der Flaeche, etwa eine eingeschlossene Nachbargemeinde -
        // kein Stueck der Aussengrenze.
        let json = antwort(relation(
            name: "Ringgemeinde", ebene: "8",
            wege: [
                weg("{\"lat\":51.4,\"lon\":12.6},{\"lat\":51.5,\"lon\":12.7}"),
                weg("{\"lat\":51.45,\"lon\":12.65},{\"lat\":51.46,\"lon\":12.66}", rolle: "inner")
            ].joined(separator: ",")
        ))
        XCTAssertEqual(CommuneBoundaryQuery.parse(json)?.lines.count, 1)
    }

    func testPunkteOhneKoordinateWerdenUebersprungen() {
        // Eine abgeschnittene Antwort hat solche Knoten. Ein Punkt mit NaN wuerde die Karte
        // beim Zeichnen ins Nichts schicken.
        let json = antwort(relation(
            name: "Kaputt", ebene: "8",
            wege: weg("{\"lat\":51.46,\"lon\":12.63},{\"foo\":1},{\"lat\":51.47,\"lon\":12.64}")
        ))
        XCTAssertEqual(CommuneBoundaryQuery.parse(json)?.lines.first?.count, 2)
    }

    func testEinzelnerPunktIstKeineLinie() {
        let json = antwort(relation(
            name: "Punkt", ebene: "8", wege: weg("{\"lat\":51.46,\"lon\":12.63}")
        ))
        XCTAssertNil(CommuneBoundaryQuery.parse(json), "Ohne verwertbare Linie gibt es keine Grenze.")
    }

    func testFremdeEbenenWerdenIgnoriert() {
        // admin_level 4 ist das Bundesland. Das hilft beim Plakatieren nicht weiter.
        let json = antwort(relation(
            name: "Sachsen", ebene: "4",
            wege: weg("{\"lat\":51.0,\"lon\":13.0},{\"lat\":51.1,\"lon\":13.1}")
        ))
        XCTAssertNil(CommuneBoundaryQuery.parse(json))
    }

    func testLeereUndKaputteAntwortenErgebenNichts() {
        for json in ["{\"elements\":[]}", "{}", "kein JSON", ""] {
            XCTAssertNil(CommuneBoundaryQuery.parse(json), "„\(json)“ darf nichts liefern.")
        }
    }

    func testDieAbfrageTraegtDenPunktUndBeideEbenen() {
        let url = CommuneBoundaryQuery.url(latitude: 51.46, longitude: 12.63)
        let klartext = url.removingPercentEncoding ?? url

        XCTAssertTrue(url.hasPrefix(CommuneBoundaryQuery.endpunkt + "?data="))
        XCTAssertTrue(klartext.contains("is_in(51.46,12.63)"))
        XCTAssertTrue(klartext.contains("^(6|8)$"), "Beide Ebenen abfragen, feinste nehmen.")
        XCTAssertFalse(url.contains(" "), "Leerzeichen muessen kodiert sein.")
    }
}
