import XCTest
@testable import PlakatKompassCore

final class ZensusRasterTests: XCTestCase {

    func testRadiusUndZellenzahlPassenZusammen() {
        // 300 m Umkreis bei 100-m-Zellen: drei Zellen in jede Richtung, also sieben mal sieben.
        // Auf diese 49 ist die Laufzeit abgestimmt - die Abfrage braucht damit rund fuenfzehn
        // Sekunden. Waere der Radius groesser, waechst die Zellenzahl quadratisch und die Abfrage
        // laeuft in die Zeitueberschreitung.
        XCTAssertEqual(ZensusRaster.radiusMeter, 300)
        XCTAssertEqual(ZensusRaster.zellenAnzahl(), 49)
        XCTAssertEqual(
            Epsg3035.zellenUm(longitude: 13.4, latitude: 52.5, radiusMeter: ZensusRaster.radiusMeter).count,
            ZensusRaster.zellenAnzahl()
        )
    }

    func testAbfrageEnthaeltZellenUndFelder() {
        let url = ZensusRaster.baueUrl(longitude: 13.4, latitude: 52.5)
        XCTAssertTrue(url.hasPrefix(ZensusRaster.endpunkt))
        XCTAssertTrue(url.contains("f=json"))
        XCTAssertTrue(url.contains("returnGeometry=false"))
        // Die Zellkennung muss kodiert in der Adresse stehen - sonst fragt die App nichts ab.
        XCTAssertTrue(url.contains("100mN"), "Zellkennungen fehlen in der Abfrage")
    }

    // Zwei Zellen: eine kleine mit 10 Einwohnern, eine grosse mit 90.
    private let antwort = """
    {"features":[
      {"attributes":{"id":"100mN32710E45518","Einwohner":10,"Durchschnittsalter":30,
                     "Unter18":5,"a65undaelter":1,"Leerstandsquote":2.0}},
      {"attributes":{"id":"100mN32710E45519","Einwohner":90,"Durchschnittsalter":50,
                     "Unter18":5,"a65undaelter":9,"Leerstandsquote":4.0}}
    ]}
    """

    func testGewichteterMittelwertZaehltGrosseZellenStaerker() {
        let werte = ZensusRaster.auswerten(antwort)
        let alter = werte.first { $0.indicator.id == "DURCHSCHNITTSALTER_RASTER" }
        // Ungewichtet waeren es 40 Jahre. Richtig ist (30*10 + 50*90) / 100 = 48.
        // Ohne Gewichtung zaehlte eine Zelle mit zehn Bewohnern so viel wie eine mit neunzig.
        XCTAssertEqual(alter?.value ?? 0, 48.0, accuracy: 0.001)
    }

    func testVerhaeltnisRechnetAusStueckzahlen() {
        let werte = ZensusRaster.auswerten(antwort)
        let unter18 = werte.first { $0.indicator.id == "ANTEIL_UNTER_18" }
        // (5 + 5) / (10 + 90) * 100 = 10 %.
        XCTAssertEqual(unter18?.value ?? 0, 10.0, accuracy: 0.001)
    }

    func testSummeZaehltEinwohnerZusammen() {
        let werte = ZensusRaster.auswerten(antwort)
        let einwohner = werte.first { $0.indicator.id == "EINWOHNER" }
        XCTAssertEqual(einwohner?.value ?? 0, 100.0, accuracy: 0.001)
    }

    func testUnplausiblesFaelltRaus() {
        // Ein Durchschnittsalter von drei Jahren gibt es nicht. Solche Werte entstehen, wenn der
        // Dienst ein Feld anders belegt als erwartet - dann ist "keine Daten" die richtige
        // Anzeige, nicht eine Zahl, die aussieht wie eine Angabe.
        let unsinn = """
        {"features":[{"attributes":{"id":"x","Einwohner":50,"Durchschnittsalter":3}}]}
        """
        let werte = ZensusRaster.auswerten(unsinn)
        XCTAssertNil(werte.first { $0.indicator.id == "DURCHSCHNITTSALTER_RASTER" })
    }

    func testFehlerUndLeereAntwortLiefernNichts() {
        XCTAssertTrue(ZensusRaster.auswerten("{\"error\":{\"code\":400}}").isEmpty)
        XCTAssertTrue(ZensusRaster.auswerten("{\"features\":[]}").isEmpty)
        XCTAssertTrue(ZensusRaster.auswerten("kein json").isEmpty)
    }

    func testTextzahlenMitKommaWerdenGelesen() {
        // Der Dienst hat schon Zahlen als Text geliefert, deutsch formatiert.
        XCTAssertEqual(ZensusRaster.alsZahl("48,5") ?? 0, 48.5, accuracy: 0.001)
        XCTAssertEqual(ZensusRaster.alsZahl("1.234,5") ?? 0, 1234.5, accuracy: 0.001)
        XCTAssertNil(ZensusRaster.alsZahl("-"))
        XCTAssertNil(ZensusRaster.alsZahl("null"))
        // NaN muss durchfallen: Es rutscht sonst an jedem Vergleich vorbei und macht ein ganzes
        // Aggregat zu NaN.
        XCTAssertNil(ZensusRaster.alsZahl(Double.nan))
        XCTAssertNil(ZensusRaster.alsZahl(Double.infinity))
    }
}
