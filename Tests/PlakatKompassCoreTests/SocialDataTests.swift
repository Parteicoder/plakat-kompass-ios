import Foundation
import XCTest
@testable import PlakatKompassCore

/// Auswertung der Regionalatlas-Antwort.
///
/// Der Abruf braucht Netz und lässt sich hier nicht prüfen — die Auswertung schon, und die ist
/// der Teil, in dem etwas schiefgehen kann. Die Antwort ist ein Join über zwei Tabellen; wie die
/// Spalten heißen, hängt vom Indikator ab. Ein Parser, der daneben greift, liefert eine Zahl, die
/// aussieht wie ein Ergebnis.
final class SocialDataTests: XCTestCase {

    private func antwort(_ features: String) -> String {
        "{\"features\":[\(features)]}"
    }

    // MARK: - Der gute Fall

    func testWertUndGebietsnameWerdenGelesen() {
        let json = antwort("""
        {"attributes":{"gen":"Eilenburg","jahr":2023,"ai0801":6.4,"ags":"14730080"}}
        """)
        let wert = RegionalAtlas.parseResponse(json, indicator: .arbeitslosenquote, level: .KREIS)

        XCTAssertEqual(wert?.value, 6.4)
        XCTAssertEqual(wert?.regionName, "Eilenburg")
        XCTAssertEqual(wert?.year, 2023)
        XCTAssertEqual(wert?.level, .KREIS)
    }

    func testDerJuengsteJahrgangGewinnt() {
        // Der Join liefert oft mehrere Jahrgaenge. Der erste ist gern zehn Jahre alt.
        let json = antwort("""
        {"attributes":{"gen":"Krostitz","jahr":2009,"ai0801":11.2}},
        {"attributes":{"gen":"Krostitz","jahr":2023,"ai0801":5.8}},
        {"attributes":{"gen":"Krostitz","jahr":2016,"ai0801":8.1}}
        """)
        let wert = RegionalAtlas.parseResponse(json, indicator: .arbeitslosenquote, level: .KREIS)

        XCTAssertEqual(wert?.year, 2023)
        XCTAssertEqual(wert?.value, 5.8)
    }

    // MARK: - Lieber nichts als das Falsche

    func testUnplausiblerWertWirdVerworfen() {
        // Ein Durchschnittsalter von 5 Jahren ist ein Griff in die falsche Spalte, kein Ergebnis.
        let json = antwort("""
        {"attributes":{"gen":"Musterstadt","jahr":2023,"ai0218":5.0}}
        """)
        XCTAssertNil(RegionalAtlas.parseResponse(json, indicator: .durchschnittsalter, level: .GEMEINDE))
    }

    func testMehrereMoeglicheSpaltenErgebenKeinenWert() {
        // Zwei aiXXXX-Spalten und kein passender Code: Raten waere schlimmer als aufgeben.
        let json = antwort("""
        {"attributes":{"gen":"Musterstadt","ai9991":12.0,"ai9992":34.0}}
        """)
        XCTAssertNil(RegionalAtlas.parseResponse(json, indicator: .arbeitslosenquote, level: .KREIS))
    }

    func testGenauEineAiSpalteWirdGenommen() {
        // Der Attributcode passt nicht, aber es gibt nur eine Kandidatenspalte.
        let json = antwort("""
        {"attributes":{"gen":"Musterstadt","ai9999":7.3,"ags":"14730080","jahr":2022}}
        """)
        XCTAssertEqual(RegionalAtlas.parseResponse(json, indicator: .arbeitslosenquote, level: .KREIS)?.value, 7.3)
    }

    func testFehlerantwortErgibtNichts() {
        XCTAssertNil(RegionalAtlas.parseResponse(
            "{\"error\":{\"code\":400,\"message\":\"Invalid\"}}",
            indicator: .arbeitslosenquote, level: .KREIS
        ))
    }

    func testLeereUndKaputteAntwortenErgebenNichts() {
        for json in ["{\"features\":[]}", "{}", "kein JSON", ""] {
            XCTAssertNil(
                RegionalAtlas.parseResponse(json, indicator: .arbeitslosenquote, level: .KREIS),
                "„\(json)“ darf keinen Wert liefern."
            )
        }
    }

    // MARK: - Zahlen

    func testNaNUndUnendlichGeltenAlsKeinWert() {
        // Der wichtigste Fall: Double("NaN") gelingt, und JEDER Vergleich mit NaN ist falsch -
        // die Plausibilitaetspruefung wuerde einen NaN also stillschweigend durchwinken.
        XCTAssertNil(RegionalAtlas.alsZahl("NaN"))
        XCTAssertNil(RegionalAtlas.alsZahl("Infinity"))
        XCTAssertNil(RegionalAtlas.alsZahl(Double.nan))
        XCTAssertNil(RegionalAtlas.alsZahl(Double.infinity))
    }

    func testDeutscheZahlenschreibweise() {
        XCTAssertEqual(RegionalAtlas.alsZahl("7,2"), 7.2)
        XCTAssertEqual(RegionalAtlas.alsZahl("1.234,5"), 1234.5)
        XCTAssertEqual(RegionalAtlas.alsZahl("1234.5"), 1234.5)
        XCTAssertEqual(RegionalAtlas.alsZahl(42), 42)
    }

    func testLeerwerteGeltenAlsKeinWert() {
        for roh in ["", "   ", "null", "NULL", "-"] {
            XCTAssertNil(RegionalAtlas.alsZahl(roh), "„\(roh)“ ist kein Wert.")
        }
    }

    func testNegativeWerteSindErlaubtWoSieSinnErgeben() {
        // Eine schrumpfende Gemeinde ist genau das, was man sehen will.
        let json = antwort("""
        {"attributes":{"gen":"Schrumpfhausen","jahr":2023,"ai0202":-84.0}}
        """)
        XCTAssertEqual(
            RegionalAtlas.parseResponse(json, indicator: .bevoelkerungsentwicklung, level: .GEMEINDE)?.value,
            -84.0
        )
    }

    // MARK: - Darstellung

    func testEinheitenWerdenDeutschFormatiert() {
        XCTAssertEqual(SocialUnit.percent.format(6.4), "6,4 %")
        XCTAssertEqual(SocialUnit.years.format(44.15), "44,2 Jahre")
        XCTAssertEqual(SocialUnit.euro.format(23_450), "23.450 €")
        XCTAssertEqual(SocialUnit.density.format(148.6), "149 EW/km²")
    }

    // MARK: - Abfrage

    func testDieUrlTraegtEbeneUndTabelleMit() {
        let url = RegionalAtlas.buildUrl(
            indicator: .arbeitslosenquote, level: .KREIS, longitude: 12.63, latitude: 51.46
        )
        let entschluesselt = url.removingPercentEncoding ?? url

        XCTAssertTrue(url.hasPrefix(RegionalAtlas.endpunkt + "?"))
        XCTAssertTrue(entschluesselt.contains("typ = 3"), "Kreisebene ist typ 3.")
        XCTAssertTrue(entschluesselt.contains("ai008_1_5"))
        XCTAssertTrue(entschluesselt.contains("\"x\":12.63"))
        XCTAssertTrue(entschluesselt.contains("f=json"))
    }

    func testGemeindeebeneNutztEinenAnderenTyp() {
        let url = RegionalAtlas.buildUrl(
            indicator: .durchschnittsalter, level: .GEMEINDE, longitude: 12.63, latitude: 51.46
        )
        XCTAssertTrue((url.removingPercentEncoding ?? url).contains("typ = 5"))
    }

    func testSonderzeichenWerdenKodiert() {
        // Ohne Kodierung von & und = zerfaellt die Abfrage in Parameter, die niemand gemeint hat.
        let url = RegionalAtlas.buildUrl(
            indicator: .arbeitslosenquote, level: .KREIS, longitude: 12.63, latitude: 51.46
        )
        let nachDemEndpunkt = String(url.dropFirst(RegionalAtlas.endpunkt.count + 1))
        let parameterNamen = nachDemEndpunkt.split(separator: "&").map { $0.split(separator: "=")[0] }

        XCTAssertEqual(
            Set(parameterNamen.map(String.init)),
            ["layer", "geometry", "geometryType", "inSR", "spatialRel", "outFields", "returnGeometry", "f"]
        )
    }

    // MARK: - Katalog

    func testJederIndikatorHatEineEindeutigeKennung() {
        let kennungen = SocialIndicator.alle.map(\.id)
        XCTAssertEqual(Set(kennungen).count, kennungen.count)
    }

    func testUnbekannteKennungFaelltAufDenStandardZurueck() {
        XCTAssertEqual(SocialIndicator.mitId("GIBTESNICHT"), SocialIndicator.standard)
        XCTAssertEqual(SocialIndicator.mitId(nil), SocialIndicator.standard)
        XCTAssertEqual(SocialIndicator.mitId("RENTNERALTER"), SocialIndicator.rentneralter)
    }
}
