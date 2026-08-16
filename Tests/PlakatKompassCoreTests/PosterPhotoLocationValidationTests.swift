import Foundation
import XCTest
@testable import PlakatKompassCore

/// Standortpruefung beim Fotografieren. Deckt dieselben Faelle wie
/// `PosterPhotoLocationValidationTest.kt` auf Android ab: fehlender Fix, fehlende Genauigkeit,
/// zu alter Fix, sowie die drei Genauigkeitsstufen.
final class PosterPhotoLocationValidationTests: XCTestCase {

    private let jetzt: Int64 = 1_700_000_000_000

    // MARK: - Blockieren

    func testFehlenderFixWirdBlockiert() {
        let ergebnis = PosterPhotoLocationValidation.validate(
            accuracyMeters: 5, timestampMs: nil, nowMs: jetzt
        )
        XCTAssertFalse(ergebnis.isValid)
        XCTAssertEqual(ergebnis.errorMessage, "Foto aufgenommen, aber kein Standort gefunden. Bitte GPS kurz warten lassen und Foto neu aufnehmen.")
    }

    func testFehlendeGenauigkeitWirdBlockiert() {
        let ergebnis = PosterPhotoLocationValidation.validate(
            accuracyMeters: -1, timestampMs: jetzt, nowMs: jetzt
        )
        XCTAssertFalse(ergebnis.isValid)
        XCTAssertEqual(ergebnis.errorMessage, "Foto aufgenommen, aber GPS meldet keine Genauigkeit. Bitte Foto neu aufnehmen.")
    }

    func testZuAlterFixWirdBlockiert() {
        let ergebnis = PosterPhotoLocationValidation.validate(
            accuracyMeters: 5, timestampMs: jetzt - 30_001, nowMs: jetzt
        )
        XCTAssertFalse(ergebnis.isValid)
        XCTAssertEqual(ergebnis.errorMessage, "GPS beim Foto war zu alt. Bitte Foto neu aufnehmen.")
    }

    func testFixGenauAn30SekundenGrenzeIstNochGueltig() {
        let ergebnis = PosterPhotoLocationValidation.validate(
            accuracyMeters: 5, timestampMs: jetzt - 30_000, nowMs: jetzt
        )
        XCTAssertTrue(ergebnis.isValid)
    }

    func testUngenauerAberFrischerFixIstGueltig() {
        // Android blockiert schlechte Genauigkeit nicht - es fragt nur nach (siehe
        // shouldConfirmInaccurateLocation).
        let ergebnis = PosterPhotoLocationValidation.validate(
            accuracyMeters: 50, timestampMs: jetzt, nowMs: jetzt
        )
        XCTAssertTrue(ergebnis.isValid)
    }

    // MARK: - Bestaetigungsdialog

    func testBestaetigungAbUeber10MeternNoetig() {
        XCTAssertTrue(PosterPhotoLocationValidation.shouldConfirmInaccurateLocation(
            accuracyMeters: 10.1, timestampMs: jetzt, nowMs: jetzt
        ))
        XCTAssertFalse(PosterPhotoLocationValidation.shouldConfirmInaccurateLocation(
            accuracyMeters: 10, timestampMs: jetzt, nowMs: jetzt
        ))
    }

    func testKeineBestaetigungBeiUngueltigemFix() {
        XCTAssertFalse(PosterPhotoLocationValidation.shouldConfirmInaccurateLocation(
            accuracyMeters: 50, timestampMs: jetzt - 30_001, nowMs: jetzt
        ))
    }

    // MARK: - Dreistufige Rueckmeldung

    func testExzellenteGenauigkeitOhneHinweis() {
        XCTAssertNil(PosterPhotoLocationValidation.accuracyWarning(accuracyMeters: 3))
    }

    func testGuteGenauigkeitGibtHinweis() {
        XCTAssertEqual(
            PosterPhotoLocationValidation.accuracyWarning(accuracyMeters: 4),
            "Standort gut (ca. 4 m). Zielbereich ist 3 bis 10 m."
        )
    }

    func testAkzeptierteGenauigkeitGibtHinweis() {
        XCTAssertEqual(
            PosterPhotoLocationValidation.accuracyWarning(accuracyMeters: 8),
            "Standort akzeptiert (ca. 8 m) – liegt im Zielbereich von 3 bis 10 m."
        )
    }

    func testSchlechteGenauigkeitGibtBestaetigungsHinweis() {
        XCTAssertEqual(
            PosterPhotoLocationValidation.accuracyWarning(accuracyMeters: 42),
            "Standort manuell bestätigt trotz ungenauer GPS-Messung (ca. 42 m). Marker bitte auf der Karte prüfen."
        )
    }

    func testUnbekannteGenauigkeitGibtEigenenHinweis() {
        XCTAssertEqual(
            PosterPhotoLocationValidation.accuracyWarning(accuracyMeters: nil),
            "GPS-Genauigkeit unbekannt. Marker bitte später prüfen."
        )
    }
}
