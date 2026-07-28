import XCTest
@testable import PlakatKompassCore

/// Der Test, der die eigentliche Anforderung prüft: **iOS liest, was Android schreibt.**
///
/// Der Vektor stammt aus `Tools/testvektor_bauen.py` und damit weder von der Swift- noch von der
/// Kotlin-Seite. Wäre er von einer der beiden erzeugt, bestätigte dieser Test nur, dass diese
/// Seite mit sich selbst übereinstimmt — der häufigste Weg, sich eine grüne Prüfung zu bauen, die
/// nichts bedeutet. Dieselbe Datei liegt im Android-Repo und wird dort von einem Kotlin-Test
/// gelesen.
final class TestvektorTests: XCTestCase {

    static let teamSecret = "testvektor-team-geheimnis-0123456789abcdef"
    static let teamId = "11111111-2222-3333-4444-555555555555"
    static let geraetA = "aaaaaaaa-0000-0000-0000-000000000001"
    static let geraetB = "bbbbbbbb-0000-0000-0000-000000000002"

    private func vektor() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sync-vektor-1", withExtension: "prsync", subdirectory: "Vektoren"),
            "Testvektor fehlt. Vorher Tools/testvektor_bauen.py laufen lassen."
        )
        return try Data(contentsOf: url)
    }

    /// Der lokale Stand eines iPhones, das zu diesem Team gehört.
    private func lokalerStand() -> LocalTeamState {
        LocalTeamState(
            deviceId: Self.geraetB,
            deviceName: "iPhone-Testgeraet",
            role: .MEMBER,
            teamId: Self.teamId,
            teamName: "Testvektor-Team",
            teamSecret: Self.teamSecret,
            devices: [
                DeviceRecord(deviceId: Self.geraetA, displayName: "Android-Testgeraet", role: .LEADER),
                DeviceRecord(deviceId: Self.geraetB, displayName: "iPhone-Testgeraet", role: .MEMBER)
            ]
        )
    }

    private func fotoZiel() -> (URL, (String) -> URL) {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (ordner, { name in ordner.appendingPathComponent(name) })
    }

    // MARK: - Der Kern der Sache

    func testPaketVonAndroidLaesstSichLesen() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let snapshot = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )

        XCTAssertEqual(snapshot.teamId, Self.teamId)
        XCTAssertEqual(snapshot.teamName, "Testvektor-Team")
        XCTAssertEqual(snapshot.senderDeviceId, Self.geraetA)
        XCTAssertEqual(snapshot.posters.count, 2)
        XCTAssertEqual(snapshot.devices.count, 2)
        XCTAssertEqual(snapshot.deletedPosters.count, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.flyerTours.count, 1)
    }

    func testFelderKommenGenauSoAn() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let snapshot = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )
        let erstes = try XCTUnwrap(snapshot.posters.first { $0.id == "poster-0001" })

        XCTAssertEqual(erstes.latitude, 51.4600, accuracy: 0.000001)
        XCTAssertEqual(erstes.longitude, 12.6330, accuracy: 0.000001)
        XCTAssertEqual(erstes.type, .LAMP_POST)
        XCTAssertEqual(erstes.status, .HANGING)
        XCTAssertEqual(erstes.localPhotoFileName, "poster-testvektor-0001.jpg")
        XCTAssertEqual(erstes.plannedRemovalAt, 1701209800000)
        // Umlaute und Sonderzeichen ueberleben UTF-8 in beide Richtungen.
        XCTAssertEqual(erstes.officialNote, "Umlaut-Probe: Grosse Strasse, Aeschylos, weiss")
    }

    /// Leeres `localPhotoFileName` und fehlende Frist sind die zwei Stellen, an denen sich
    /// Kotlins org.json und Swifts JSONSerialization am ehesten unterschiedlich verhalten.
    func testLeeresFotoUndFehlendeFristWerdenZuNil() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let snapshot = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )
        let zweites = try XCTUnwrap(snapshot.posters.first { $0.id == "poster-0002" })

        XCTAssertNil(zweites.localPhotoFileName, "\"\" muss zu nil werden, nicht zu einem leeren Namen")
        XCTAssertNil(zweites.plannedRemovalAt, "null muss zu nil werden, nicht zu 0")
        XCTAssertEqual(zweites.status, .DAMAGED)
        XCTAssertEqual(zweites.type, .TRIANGLE_STAND)
    }

    func testFotoLandetAufDerPlatte() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        _ = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )
        let foto = ordner.appendingPathComponent("poster-testvektor-0001.jpg")
        let daten = try Data(contentsOf: foto)
        XCTAssertEqual(daten.count, 2048)
        XCTAssertEqual(daten.first, 11)  // (0*7+11) % 256
    }

    func testFlyerTourMitWegpunkten() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let snapshot = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )
        let tour = try XCTUnwrap(snapshot.flyerTours.first)
        XCTAssertEqual(tour.status, .FINISHED)
        XCTAssertEqual(tour.points.count, 2)
        XCTAssertEqual(tour.finishedAt, 1700000700000)
    }

    // MARK: - Was scheitern MUSS

    func testFalscherTeamSchluesselWirdAbgewiesen() throws {
        var fremd = lokalerStand()
        fremd.teamSecret = "ein-anderes-geheimnis"
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(data: try vektor(), local: fremd, photoTargetURL: ziel)
        )
    }

    func testVeraendertesPaketWirdAbgewiesen() throws {
        var kaputt = try vektor()
        kaputt[kaputt.count - 1] ^= 0x01
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(data: kaputt, local: lokalerStand(), photoTargetURL: ziel)
        )
    }

    /// Vor der Teamprüfung darf **kein** Foto auf der Platte landen.
    func testBeiFremdemTeamWirdKeinFotoGeschrieben() throws {
        var fremd = lokalerStand()
        fremd.teamId = "ein-fremdes-team"
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(data: try vektor(), local: fremd, photoTargetURL: ziel)
        )
        let inhalt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        XCTAssertTrue(inhalt.isEmpty, "Vor der Teamprüfung darf nichts geschrieben werden, gefunden: \(inhalt)")
    }

    // MARK: - Der Rückweg

    /// Was iOS schreibt, muss iOS auch wieder lesen können. Dass Android es lesen kann, prüft
    /// der Kotlin-Test drüben gegen denselben Vektor.
    func testEigenesPaketLaesstSichWiederLesen() throws {
        let (ordner, ziel) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let original = try SyncBundleCodec.importVerifiedBundle(
            data: try vektor(), local: lokalerStand(), photoTargetURL: ziel
        )
        let neu = try SyncBundleCodec.createBundle(
            snapshot: original, teamSecret: Self.teamSecret, photoURL: ziel
        )

        let (ordner2, ziel2) = fotoZiel()
        defer { try? FileManager.default.removeItem(at: ordner2) }
        let wieder = try SyncBundleCodec.importVerifiedBundle(
            data: neu, local: lokalerStand(), photoTargetURL: ziel2
        )
        XCTAssertEqual(original, wieder)
    }
}
