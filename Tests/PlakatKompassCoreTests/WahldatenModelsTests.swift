import Foundation
import XCTest

@testable import PlakatKompassCore

/// `WahlKennung.istArchiv` und die geteilte JSON-Zahl-Konvertierung `zahlAusJson`/`intAusJson`.
final class WahldatenModelsTests: XCTestCase {

  // MARK: - istArchiv

  func testIstArchivErkenntVergangeneWahl() {
    let kennung = WahlKennung(
      art: .bundestag, jahr: 2021, ebene: .wahlkreis, titel: "t",
      quelle: .plakatKompassJson(url: "x", cacheDatei: "x")
    )
    XCTAssertTrue(kennung.istArchiv(aktuellesJahr: 2026))
  }

  /// `jahr == 0` ist bei `.landDatei`-Quellen der Platzhalter vor dem ersten Parsen — das
  /// bedeutet "noch unbekannt", nicht "sehr alt". Ohne den Fix wäre `0 < aktuellesJahr` immer
  /// wahr und eine laufende Wahl fälschlich als archiviert markiert.
  func testIstArchivBehandeltUngeparstenPlatzhalterAlsNichtArchiviert() {
    let kennung = WahlKennung(
      art: .landtag, jahr: 0, ebene: .gemeinde, titel: "t",
      quelle: .landDatei(dateiname: Wahlquelle.LandDateiName.landtag, landkennzahl: "08")
    )
    XCTAssertFalse(kennung.istArchiv(aktuellesJahr: 2026))
  }

  func testFasseKleineParteienZusammenUndSetztSonstigeAnsEnde() {
    let ergebnis = fasseKleineZusammen([
      Parteiergebnis(partei: "SPD", prozent: 24),
      Parteiergebnis(partei: "Klein A", prozent: 1.2),
      Parteiergebnis(partei: "Sonstige", prozent: 0.3),
      Parteiergebnis(partei: "Klein B", prozent: 0.4),
    ])

    XCTAssertEqual(ergebnis.map(\.partei), ["SPD", "Sonstige"])
    XCTAssertEqual(ergebnis[0].prozent, 24)
    XCTAssertEqual(ergebnis[1].prozent, 1.9, accuracy: 0.0001)
  }

  func testFasseKleineParteienLaesstVollstaendigeListeUnveraendert() {
    let parteien = [
      Parteiergebnis(partei: "B", prozent: 4),
      Parteiergebnis(partei: "A", prozent: 3),
    ]
    XCTAssertEqual(fasseKleineZusammen(parteien), parteien)
  }

  // MARK: - zahlAusJson

  func testZahlAusJsonLehntBoolAb() {
    // JSONSerialization bildet ein JSON `true`/`false` unter Apples Foundation als
    // `__NSCFBoolean` ab, eine private NSNumber-Unterklasse — ohne den expliziten
    // Bool-Ausschluss würde das als 1.0/0.0 durchgehen.
    let json = #"{"beteiligung": true, "parteien": {}}"#.data(using: .utf8)!
    let root = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
    XCTAssertNil(zahlAusJson(root["beteiligung"]!))
  }

  func testZahlAusJsonAkzeptiertNormaleZahlen() {
    XCTAssertEqual(zahlAusJson(70.8), 70.8)
    XCTAssertEqual(zahlAusJson(70), 70.0)

    let json = #"[0, 1, 152]"#.data(using: .utf8)!
    let zahlen = try! JSONSerialization.jsonObject(with: json) as! [Any]
    XCTAssertEqual(zahlen.compactMap(zahlAusJson), [0, 1, 152])
  }

  // MARK: - intAusJson

  /// `Int(Double)` trapt bei einem endlichen, aber bereichsüberschreitenden Wert. `intAusJson`
  /// muss stattdessen `nil` liefern.
  func testIntAusJsonLiefertNilStattAbsturzBeiBereichsUeberschreitung() {
    XCTAssertNil(intAusJson(1e20))
    XCTAssertNil(intAusJson(-1e20))
  }

  func testIntAusJsonFunktioniertFuerNormaleJahreszahlen() {
    XCTAssertEqual(intAusJson(2026), 2026)
  }
}
