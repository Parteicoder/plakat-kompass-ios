import XCTest
@testable import PlakatKompassCore

final class Epsg3035Tests: XCTestCase {

    func testUrsprungTrifftDieFalschenWerteGenau() {
        // Der einzige Punkt, dessen Bild man ohne Tabelle kennt: Im Projektionsursprung
        // (10° Ost, 52° Nord) muessen genau die Verschiebungswerte herauskommen, die in der
        // Definition von EPSG:3035 stehen - 4 321 000 / 3 210 000.
        //
        // Das ist der schaerfste verfuegbare Test der ganzen Formel: Faellt er, stimmt an der
        // Projektion etwas grundsaetzlich nicht, und die App fragt Zellen ab, die woanders liegen.
        let punkt = Epsg3035.vonWgs84(longitude: 10.0, latitude: 52.0)
        XCTAssertEqual(punkt.easting, 4_321_000.0, accuracy: 0.001)
        XCTAssertEqual(punkt.northing, 3_210_000.0, accuracy: 0.001)
    }

    func testHundertMeterOstenSindEineZelleWeiter() {
        // Die Zellen sind 100 Meter breit. Wer sich um gut 100 Meter nach Osten bewegt, muss in
        // der Nachbarzelle landen - sonst passt das Gitter nicht zu seinem Namen.
        let mitte = Epsg3035.vonWgs84(longitude: 10.0, latitude: 52.0)
        let links = Epsg3035.zellKennung(easting: mitte.easting, northing: mitte.northing)
        let rechts = Epsg3035.zellKennung(easting: mitte.easting + 100.0, northing: mitte.northing)
        XCTAssertNotEqual(links, rechts)

        // Und die Kennung traegt die Zellnummer, nicht die Metermenge: 4 321 000 / 100 = 43 210.
        XCTAssertEqual(links, "100mN32100E43210")
    }

    func testUmkreisLiefertDasErwarteteQuadrat() {
        // 300 Meter Umkreis heisst drei Zellen in jede Richtung, also sieben mal sieben.
        // Auf diese 49 Zellen ist die Laufzeit der Abfrage abgestimmt; kaeme hier eine andere
        // Zahl heraus, waere entweder die Abfrage zu langsam oder der Umkreis zu klein.
        let zellen = Epsg3035.zellenUm(longitude: 13.4, latitude: 52.5, radiusMeter: 300)
        XCTAssertEqual(zellen.count, 49)
        XCTAssertEqual(Set(zellen).count, 49, "Zellen duerfen sich nicht wiederholen")

        // Die Zelle des Punktes selbst muss dabei sein - sonst fehlt ausgerechnet die, auf der
        // man steht.
        let mitte = Epsg3035.vonWgs84(longitude: 13.4, latitude: 52.5)
        let eigene = Epsg3035.zellKennung(easting: mitte.easting, northing: mitte.northing)
        XCTAssertTrue(zellen.contains(eigene))
    }

    func testKleinerRadiusLiefertMindestensDieEigeneUndDieNachbarn() {
        // Auch bei null Metern soll nicht nichts herauskommen: Eine Abfrage ohne Zellen waere
        // eine Abfrage ohne Antwort.
        let zellen = Epsg3035.zellenUm(longitude: 13.4, latitude: 52.5, radiusMeter: 0)
        XCTAssertEqual(zellen.count, 9)
    }
}
