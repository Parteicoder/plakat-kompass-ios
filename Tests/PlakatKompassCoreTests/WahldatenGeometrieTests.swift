import Foundation
import XCTest
@testable import PlakatKompassCore

/// Punkt-in-Fläche-Suche für Wahlkreise. Zwei synthetische Gebiete: Wahlkreis "1" (ein Polygon,
/// Rechteck 12.0–12.40° Länge) und Wahlkreis "2" (ein MultiPolygon aus zwei getrennten
/// Rechtecken, 12.40–12.80° Länge). Beide teilen sich die Kante bei 12.40° Länge — genau der
/// Fall, an dem sich zeigt, ob ein Grenzpunkt eindeutig genau einer Fläche zufällt.
final class WahldatenGeometrieTests: XCTestCase {

    private let json = """
    {"type":"FeatureCollection","features":[
      {"type":"Feature","properties":{"WKR_NR":1,"WKR_NAME":"Eins"},
       "geometry":{"type":"Polygon","coordinates":[[
         [12.0,50.0],[12.40,50.0],[12.40,51.0],[12.0,51.0]
       ]]}},
      {"type":"Feature","properties":{"WKR_NR":2,"WKR_NAME":"Zwei"},
       "geometry":{"type":"MultiPolygon","coordinates":[
         [[[12.40,50.0],[12.80,50.0],[12.80,50.5],[12.40,50.5]]],
         [[[12.40,50.5],[12.80,50.5],[12.80,51.0],[12.40,51.0]]]
       ]}}
    ]}
    """

    // MARK: - Der gute Fall

    func testInnererPunktGehoertZurFlaeche() {
        let gebiete = parseGeoJsonFlaechen(json)
        let treffer = flaecheAn(gebiete, longitude: 12.20, latitude: 50.5)
        XCTAssertEqual(treffer?.kennung, "001")
    }

    func testBeideTeileEinesMultiPolygonsZaehlen() {
        let gebiete = parseGeoJsonFlaechen(json)
        XCTAssertEqual(flaecheAn(gebiete, longitude: 12.60, latitude: 50.2)?.kennung, "002")
        XCTAssertEqual(flaecheAn(gebiete, longitude: 12.60, latitude: 50.8)?.kennung, "002")
    }

    func testPunktAusserhalbAllerFlaechenGibtNil() {
        let gebiete = parseGeoJsonFlaechen(json)
        XCTAssertNil(flaecheAn(gebiete, longitude: 0, latitude: 0))
    }

    func testGemeinsameKanteGehoertGenauEinerFlaeche() {
        // Punkt genau auf der geteilten Kante bei 12.40° Länge, mittig in der Höhe (50.3° Breite,
        // damit er nicht zusätzlich auf einer waagrechten Kante liegt). Von Hand durchgerechnet:
        // die strikte "<"-Schwelle in ringEnthaelt schließt die rechte Kante von Wahlkreis 1 aus
        // und zählt sie zu Wahlkreis 2 — nicht beide, nicht keiner.
        let gebiete = parseGeoJsonFlaechen(json)
        XCTAssertEqual(flaecheAn(gebiete, longitude: 12.40, latitude: 50.3)?.kennung, "002")
    }

    // MARK: - Kennung

    func testNumerischeKennungWirdAufDreiStellenAufgefuellt() {
        // WKR_NR 1 und 2 in der Fixture stehen für Wahlkreise <100 - der Praxisfall aus dem
        // Zero-Padding-Fix: bundestagswahl-2025.json schlüsselt dreistellig ("001"), das
        // gebündelte GeoJSON liefert bare Zahlen.
        let gebiete = parseGeoJsonFlaechen(json)
        XCTAssertEqual(gebiete.map(\.kennung).sorted(), ["001", "002"])
    }

    func testNumerischeKennungWirdNichtAlsGleitkommaDargestellt() {
        // "152.0" statt "152" wäre ein Schlüssel, den keine Ergebnisdatei kennt.
        let einzeln = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"WKR_NR":152,"WKR_NAME":"X"},
           "geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1]]]}}
        ]}
        """
        XCTAssertEqual(parseGeoJsonFlaechen(einzeln).first?.kennung, "152")
    }

    func testAlternativeEigenschaftsnamenWerdenErkannt() {
        let alternativ = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"nr":"07213","name":"Beispielkreis"},
           "geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1]]]}}
        ]}
        """
        let gebiete = parseGeoJsonFlaechen(alternativ)
        XCTAssertEqual(gebiete.first?.kennung, "07213")
        XCTAssertEqual(gebiete.first?.name, "Beispielkreis")
    }

    // MARK: - Robustheit

    func testLeereFeaturesGebenLeereListe() {
        XCTAssertTrue(parseGeoJsonFlaechen("""
        {"type":"FeatureCollection","features":[]}
        """).isEmpty)
    }

    func testUngueltigesJsonGibtLeereListe() {
        XCTAssertTrue(parseGeoJsonFlaechen("nicht json").isEmpty)
        XCTAssertTrue(parseGeoJsonFlaechen("").isEmpty)
    }

    func testPunktGeometrieWirdUebersprungen() {
        // Ein Point ist kein Polygon - das Feature liefert keine Fläche, statt abzustürzen.
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"WKR_NR":9,"WKR_NAME":"Punkt"},
           "geometry":{"type":"Point","coordinates":[9.0,50.0]}}
        ]}
        """
        XCTAssertTrue(parseGeoJsonFlaechen(json).isEmpty)
    }

    /// Eine kaputte Teilfläche eines MultiPolygons darf nicht lautlos verschwinden, während der
    /// Rest als "vollständige" Wahlfläche zurückkommt — sonst würde ein Punkt in genau dieser
    /// Teilfläche fälschlich als "außerhalb aller Wahlkreise" gemeldet.
    func testMultiPolygonMitKaputterTeilflaecheWirdGanzVerworfen() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"WKR_NR":3,"WKR_NAME":"Drei"},
           "geometry":{"type":"MultiPolygon","coordinates":[
             [[[0,0],[1,0],[1,1],[0,1]]],
             [[[2,2]]]
           ]}}
        ]}
        """
        XCTAssertTrue(parseGeoJsonFlaechen(json).isEmpty)
    }
}
