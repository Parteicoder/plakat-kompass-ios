import Foundation
import XCTest
import ZIPFoundation
@testable import PlakatKompassCore

/// Prüft den Verwaltungs-Export.
///
/// Der Schwerpunkt liegt auf der Formel-Entschärfung. Die CSV wird bei der Stadtverwaltung
/// geöffnet, und die Freitextfelder darin können per Abgleich von einem fremden Gerät stammen —
/// das ist der einzige Weg, auf dem aus dieser App heraus fremder Inhalt auf einem
/// Verwaltungsrechner ausgeführt werden könnte. Dieselben Fälle prüft
/// `OfficialExportCsvInjectionTest` auf Android.
final class OfficialExportTests: XCTestCase {

    private func plakat(
        adresse: String = "Am Markt 1",
        bemerkung: String = "ok",
        latitude: Double = -12.34,
        longitude: Double = 9.87,
        foto: String? = nil
    ) -> Poster {
        Poster(
            id: "p1",
            teamId: "team-1",
            latitude: latitude,
            longitude: longitude,
            addressHint: adresse,
            localPhotoFileName: foto,
            createdByDeviceId: "device-1",
            createdByName: "David",
            officialNote: bemerkung
        )
    }

    private func stand(_ plakate: Poster...) -> LocalTeamState {
        LocalTeamState(deviceId: "device-1", deviceName: "David", posters: plakate)
    }

    /// Die Datenzeile: nach BOM, `sep=;` und Überschrift.
    private func datenzeile(_ csv: String, _ index: Int = 0) -> String {
        String(csv.dropFirst()).components(separatedBy: "\n")[2 + index]
    }

    // MARK: - Formel-Entschärfung

    func testFreitextMitFuehrendemFormelzeichenWirdEntschaerft() {
        let csv = OfficialExport.toCsv(
            state: stand(plakat(adresse: "=HYPERLINK(\"http://boese.example\")", bemerkung: "@SUM(A1)")),
            municipality: "Musterstadt"
        )
        let zeile = datenzeile(csv)

        XCTAssertTrue(zeile.contains("\"'=HYPERLINK"))
        XCTAssertTrue(zeile.contains("\"'@SUM(A1)\""))
        XCTAssertFalse(zeile.contains("\"=HYPERLINK"))
    }

    func testKommuneWirdEbenfallsEntschaerft() {
        let csv = OfficialExport.toCsv(
            state: stand(plakat()),
            municipality: "+CMD|'/C calc'!A0"
        )
        XCTAssertTrue(datenzeile(csv).contains("\"'+CMD"))
    }

    func testNegativeKoordinateBleibtEineZahl() {
        let csv = OfficialExport.toCsv(state: stand(plakat()), municipality: "Musterstadt")
        let zeile = datenzeile(csv)

        // -12.34 faengt mit einem Formelzeichen an, ist aber eine Zahl und muss eine bleiben:
        // sonst kann die Verwaltung damit nicht rechnen.
        XCTAssertTrue(zeile.contains("\"-12.34\""))
        XCTAssertFalse(zeile.contains("'-12.34"))
    }

    func testAnfuehrungszeichenImFreitextWerdenVerdoppelt() {
        let csv = OfficialExport.toCsv(
            state: stand(plakat(adresse: "Ecke \"Alte Post\"")),
            municipality: "Musterstadt"
        )
        XCTAssertTrue(datenzeile(csv).contains("\"Ecke \"\"Alte Post\"\"\""))
    }

    // MARK: - Aufbau der Datei

    func testKopfzeilenFuerExcel() {
        let csv = OfficialExport.toCsv(state: stand(plakat()), municipality: "Musterstadt")

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "Ohne BOM zeigt aelteres Excel Buchstabensalat.")
        let zeilen = String(csv.dropFirst()).components(separatedBy: "\n")
        XCTAssertEqual(zeilen[0], "sep=;", "Ohne den Hinweis zerlegt Excel Ueberschriften an Leerzeichen.")
        XCTAssertTrue(zeilen[1].hasPrefix("\"Nr.\";\"Kommune\""))
        XCTAssertFalse(zeilen[1].contains("Foto-Datei"), "Ohne ZIP gibt es keine Fotospalte.")
    }

    func testLeereFelderBekommenKlartextStattLeerzelle() {
        let csv = OfficialExport.toCsv(
            state: stand(plakat(adresse: "   ", bemerkung: "")),
            municipality: "Musterstadt"
        )
        let zeile = datenzeile(csv)

        // Eine leere Zelle liest sich im Rathaus wie ein Fehler beim Export.
        XCTAssertTrue(zeile.contains("\"Keine Standortbeschreibung eingetragen\""))
        XCTAssertTrue(zeile.contains("\"Keine Bemerkung\""))
        XCTAssertTrue(zeile.contains("\"Nicht eingetragen\""), "Ohne Abnahmefrist steht das im Klartext.")
    }

    func testNummerierungLaeuftDurch() {
        let csv = OfficialExport.toCsv(
            state: stand(plakat(), plakat(), plakat()),
            municipality: "Musterstadt"
        )
        XCTAssertTrue(datenzeile(csv, 0).hasPrefix("\"1\";"))
        XCTAssertTrue(datenzeile(csv, 2).hasPrefix("\"3\";"))
    }

    // MARK: - ZIP

    func testZipEnthaeltListeUndFoto() throws {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        try Data("nicht wirklich ein Bild".utf8).write(to: ordner.appendingPathComponent("a.jpg"))

        let daten = try OfficialExport.zipData(
            state: stand(plakat(foto: "a.jpg"), plakat(foto: "fehlt.jpg")),
            municipality: "Musterstadt",
            photoURL: { ordner.appendingPathComponent($0) }
        )

        let archiv = try XCTUnwrap(Archive(data: daten, accessMode: .read))
        let eintraege = archiv.map(\.path).sorted()
        XCTAssertEqual(eintraege, ["fotos/plakat_001.jpg", "plakatliste.csv"])
    }

    func testFehlendesFotoStehtAlsHinweisInDerListe() throws {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        // Ein Plakat verweist auf ein Foto, das es nicht mehr gibt. Der Export darf daran nicht
        // scheitern - sonst haengt die Verwaltungsfrist an einer einzigen kaputten Datei.
        let daten = try OfficialExport.zipData(
            state: stand(plakat(foto: "weg.jpg")),
            municipality: "Musterstadt",
            photoURL: { ordner.appendingPathComponent($0) }
        )

        let archiv = try XCTUnwrap(Archive(data: daten, accessMode: .read))
        let eintrag = try XCTUnwrap(archiv["plakatliste.csv"])
        var csv = Data()
        _ = try archiv.extract(eintrag, consumer: { csv.append($0) })

        let zeile = datenzeile(String(decoding: csv, as: UTF8.self))
        XCTAssertTrue(zeile.hasSuffix("\"Kein Foto\""))
    }

    // MARK: - Dateiname

    func testDateinameLesbarUndMitZipEndung() {
        let name = ExportNames.authorityZipName(municipality: "Musterstadt", nowMillis: 1_704_067_200_000)

        XCTAssertTrue(name.hasPrefix("PlakatRadar_Verwaltung_Musterstadt_"))
        XCTAssertTrue(name.hasSuffix(".zip"))
        XCTAssertFalse(name.contains("1704067200000"), "Der Zeitstempel gehoert lesbar in den Namen.")
    }

    func testDateinameEntschaerftUnsichereZeichen() {
        let name = ExportNames.authorityZipName(municipality: "Bad Name !!/\\", nowMillis: 1_704_067_200_000)

        XCTAssertTrue(name.hasPrefix("PlakatRadar_Verwaltung_Bad_Name_"))
        for zeichen in [" ", "!", "/", "\\"] {
            XCTAssertFalse(name.contains(zeichen), "\(zeichen) gehoert nicht in einen Dateinamen.")
        }
    }

    func testDateinameFaelltAufKommuneZurueck() {
        let name = ExportNames.authorityZipName(municipality: "   ", nowMillis: 1_704_067_200_000)
        XCTAssertTrue(name.hasPrefix("PlakatRadar_Verwaltung_Kommune_"))
    }

    func testZweiExporteInDerselbenSekundeKollidierenNicht() {
        // Beim Doppeltippen wuerde sonst der erste Export ueberschrieben.
        XCTAssertNotEqual(
            ExportNames.authorityZipName(municipality: "Musterstadt", nowMillis: 1_704_067_200_000),
            ExportNames.authorityZipName(municipality: "Musterstadt", nowMillis: 1_704_067_201_234)
        )
    }
}
