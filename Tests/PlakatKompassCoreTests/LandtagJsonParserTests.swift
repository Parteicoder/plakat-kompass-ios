import Foundation
import XCTest
@testable import PlakatKompassCore

/// Liest `daten.plakat-kompass.de/<land>/landtag.json` und die gleich aufgebauten Kreistags-,
/// Kommunal-, Bundestags- und Europawahl-Dateien. Gegenstück zu `LandtagJsonParserTest.kt`.
///
/// Anders als beim früheren Excel-Auswerter auf Android gibt es hier nichts zu erraten — die
/// Datei ist strukturiert und stammt aus der eigenen Aufbereitung in `Plakat-Kompass-Asset`.
/// Geprüft wird deshalb nicht die Erkennung, sondern der Umgang mit dem, was die Datei
/// tatsächlich enthalten kann: fehlende Gemeinden, unplausible Beteiligung, unvollständige
/// Quellenangabe.
final class LandtagJsonParserTests: XCTestCase {

    private let platzhalter = WahlKennung(
        art: .landtag, jahr: 0, ebene: .gemeinde, titel: "Landtagswahl Sachsen",
        quelle: .landDatei(dateiname: Wahlquelle.LandDateiName.landtag, landkennzahl: "14")
    )

    private let json: Data = """
    {
      "land": "14",
      "titel": "Landtagswahl Sachsen 2024",
      "jahr": 2024,
      "quelle": "Der Landeswahlleiter des Freistaates Sachsen",
      "lizenz": "Datenlizenz Deutschland – Namensnennung – Version 2.0",
      "gebiete": {
        "14612000": {
          "name": "Dresden, Stadt",
          "beteiligung": 77.4,
          "parteien": {"CDU": 30.9, "AfD": 22.0, "ÖDP": 0.0}
        },
        "14524030": {
          "name": "Crimmitschau, Stadt",
          "beteiligung": 131.5,
          "parteien": {"CDU": 35.0, "AfD": 34.6}
        }
      }
    }
    """.data(using: .utf8)!

    func testGemeindeWirdGefunden() {
        let ergebnis = parseLandtagJson(bytes: json, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertEqual(ergebnis.beteiligung!, 77.4, accuracy: 0.001)
        XCTAssertEqual(ergebnis.parteien.first { $0.partei == "CDU" }?.prozent ?? 0, 30.9, accuracy: 0.001)
    }

    /// 0,0-Prozent-Parteien tragen keine Information und werden nicht angezeigt.
    func testNullProzentParteienWerdenAusgelassen() {
        let ergebnis = parseLandtagJson(bytes: json, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertFalse(ergebnis.parteien.contains { $0.partei == "ÖDP" })
    }

    /// Eine Beteiligung über 100 % ist unplausibel — bei Sachsen kam das tatsächlich vor
    /// (Gemeinden, die die Briefwahl auch für eine Nachbargemeinde durchführten). Lieber keine
    /// Zahl zeigen als eine falsche.
    func testUnplausibleBeteiligungWirdVerworfen() {
        let ergebnis = parseLandtagJson(bytes: json, gebietsschluessel: "14524030", wahl: platzhalter)!
        XCTAssertNil(ergebnis.beteiligung)
        // Die Parteianteile selbst bleiben davon unberührt - nur die Beteiligung ist betroffen.
        XCTAssertEqual(ergebnis.parteien.first { $0.partei == "CDU" }?.prozent ?? 0, 35.0, accuracy: 0.001)
    }

    func testUnbekannteGemeindeLiefertNil() {
        XCTAssertNil(parseLandtagJson(bytes: json, gebietsschluessel: "99999999", wahl: platzhalter))
    }

    func testUngueltigesJsonLiefertNil() {
        XCTAssertNil(parseLandtagJson(bytes: "kein json".data(using: .utf8)!, gebietsschluessel: "14612000", wahl: platzhalter))
        XCTAssertNil(parseLandtagJson(bytes: Data(), gebietsschluessel: "14612000", wahl: platzhalter))
    }

    func testTitelUndJahrKommenAusDerDatei() {
        let ergebnis = parseLandtagJson(bytes: json, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertEqual(ergebnis.wahl.titel, "Landtagswahl Sachsen 2024")
        XCTAssertEqual(ergebnis.wahl.jahr, 2024)
    }

    func testQuellenangabeNenntHerausgeberUndLizenz() {
        let ergebnis = parseLandtagJson(bytes: json, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertEqual(
            ergebnis.quellenangabe,
            "Der Landeswahlleiter des Freistaates Sachsen (Datenlizenz Deutschland – Namensnennung – Version 2.0)"
        )
    }

    /// Fehlt die Lizenz in der Datei, steht wenigstens der Herausgeber da — keine erfundene Lizenz.
    func testQuellenangabeOhneLizenzNenntNurDenHerausgeber() {
        let ohneLizenz = """
        {"titel": "t", "jahr": 2024, "quelle": "GERDA – German Election Database",
         "gebiete": {"14612000": {"name": "Dresden", "beteiligung": 50.0, "parteien": {"CDU": 100.0}}}}
        """.data(using: .utf8)!
        let ergebnis = parseLandtagJson(bytes: ohneLizenz, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertEqual(ergebnis.quellenangabe, "GERDA – German Election Database")
    }

    func testFehlendesGebieteObjektLiefertNil() {
        let ohneGebiete = #"{"titel": "t", "jahr": 2024, "quelle": "x"}"#.data(using: .utf8)!
        XCTAssertNil(parseLandtagJson(bytes: ohneGebiete, gebietsschluessel: "14612000", wahl: platzhalter))
    }

    func testSindLandtagJsonBytesErkenntJsonUndVerwirftAnderes() {
        XCTAssertTrue(sindLandtagJsonBytes(#"{"a":1}"#.data(using: .utf8)!))
        XCTAssertTrue(sindLandtagJsonBytes(#" {"a":1}"#.data(using: .utf8)!))
        XCTAssertFalse(sindLandtagJsonBytes("<html>404</html>".data(using: .utf8)!))
        XCTAssertFalse(sindLandtagJsonBytes(Data()))
    }

    /// Eine Fehlerseite, die zufällig mit einem Zeilenumbruch statt `<` beginnt, darf nicht als
    /// Landtags-JSON durchgehen — sonst läge sie dank der langen Cache-Frist einen Monat als
    /// "kein Ergebnis" fest.
    func testSindLandtagJsonBytesErkenntFehlerseiteMitFuehrendemZeilenumbruch() {
        XCTAssertFalse(sindLandtagJsonBytes("\n\n<html>Wartungsarbeiten</html>".data(using: .utf8)!))
    }

    /// Ein BOM vor der öffnenden Klammer darf eine sonst gültige Datei nicht verwerfen.
    func testSindLandtagJsonBytesToleriertBom() {
        XCTAssertTrue(sindLandtagJsonBytes("\u{FEFF}{\"a\":1}".data(using: .utf8)!))
    }

    private let bundestag = WahlKennung(
        art: .bundestag, jahr: 2025, ebene: .wahlkreis, titel: "Bundestagswahl 2025",
        quelle: .plakatKompassJson(
            url: "https://daten.plakat-kompass.de/bundestagswahl-2025.json",
            cacheDatei: "plakat_kompass_bundestagswahl_2025.json"
        )
    )

    func testPlakatKompassBundestagswahlWirdWieLandtagsdateiGelesen() {
        let bundesJson = """
        {"titel":"Bundestagswahl 2025","jahr":2025,
         "quelle":"Die Bundeswahlleiterin, Wiesbaden",
         "lizenz":"Datenlizenz Deutschland – Namensnennung 2.0",
         "gebiete":{"001":{"name":"Flensburg – Schleswig","beteiligung":83.1,
         "parteien":{"CDU":24.9,"SPD":15.9,"MLPD":0.0}}}}
        """.data(using: .utf8)!

        let ergebnis = parseLandtagJson(bytes: bundesJson, gebietsschluessel: "001", wahl: bundestag)!
        XCTAssertEqual(ergebnis.beteiligung!, 83.1, accuracy: 0.001)
        XCTAssertEqual(ergebnis.parteien.first { $0.partei == "CDU" }?.prozent ?? 0, 24.9, accuracy: 0.001)
        XCTAssertEqual(ergebnis.wahl.titel, "Bundestagswahl 2025")
    }

    func testBomVorDerDateiStoertDasParsenNicht() {
        var mitBom = "\u{FEFF}".data(using: .utf8)!
        mitBom.append(json)
        let ergebnis = parseLandtagJson(bytes: mitBom, gebietsschluessel: "14612000", wahl: platzhalter)!
        XCTAssertEqual(ergebnis.parteien.first { $0.partei == "CDU" }?.prozent ?? 0, 30.9, accuracy: 0.001)
    }
}
