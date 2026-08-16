import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import PlakatKompassCore

/// Was passiert, wenn jemand ein Paket **absichtlich** falsch baut.
///
/// Der Testvektor prüft den guten Fall. Hier geht es um den anderen: Ein Sync-Paket kommt über
/// einen Messenger herein, und wer den Team-Schlüssel einmal hat — ein ausgeschiedenes Mitglied,
/// jemand mit einem alten Screenshot des QR-Codes — kann den Inhalt frei gestalten. Die
/// Verschlüsselung hilft dagegen nicht: Sie beweist nur, dass der Absender den Schlüssel kennt,
/// nicht dass er wohlwollend ist.
///
/// Deshalb baut dieser Test die Pakete selbst zusammen, statt `createBundle` zu benutzen —
/// `createBundle` schreibt nur wohlgeformte Pakete, und genau die sind hier nicht interessant.
final class SyncBundleAbwehrTests: XCTestCase {

    private let teamSecret = "abwehr-team-geheimnis"
    private let teamId = "team-abwehr"
    private let absender = "leader-phone"

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func ziel(_ name: String) -> URL { ordner.appendingPathComponent(name) }

    private func lokalerStand() -> LocalTeamState {
        LocalTeamState(
            deviceId: "member-phone",
            deviceName: "Mitglied",
            role: .MEMBER,
            teamId: teamId,
            teamName: "Abwehr",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER),
                DeviceRecord(deviceId: absender, displayName: "David", role: .LEADER)
            ]
        )
    }

    private func plakat(foto: String?) -> Poster {
        Poster(
            id: "poster-1", teamId: teamId, latitude: 51.46, longitude: 12.63,
            localPhotoFileName: foto,
            createdByDeviceId: absender, createdByName: "David"
        )
    }

    /// Baut ein Paket von Hand: beliebige ZIP-Einträge, danach echt verschlüsselt.
    private func gebasteltesPaket(
        posters: [Poster],
        dateien: [String: Data]
    ) throws -> Data {
        let snapshot = SyncSnapshot(
            teamId: teamId,
            teamName: "Abwehr",
            senderDeviceId: absender,
            senderName: "David",
            teamSecretHash: Crypto.sha256Hex(teamSecret),
            devices: [],
            posters: posters,
            events: []
        )

        let archiv = try XCTUnwrap(Archive(accessMode: .create))
        let snapshotBytes = try TeamStateJson.snapshotToJson(snapshot)
        try archiv.addEntry(
            with: "snapshot.json", type: .file, uncompressedSize: Int64(snapshotBytes.count),
            provider: { pos, len in snapshotBytes.subdata(in: Int(pos)..<Int(pos) + len) }
        )
        for (pfad, inhalt) in dateien.sorted(by: { $0.key < $1.key }) {
            try archiv.addEntry(
                with: pfad, type: .file, uncompressedSize: Int64(inhalt.count),
                provider: { pos, len in inhalt.subdata(in: Int(pos)..<Int(pos) + len) }
            )
        }
        let zip = try XCTUnwrap(archiv.data)

        var iv = Data(count: SyncBundleCodec.ivBytes)
        iv[0] = 7
        let box = try AES.GCM.seal(
            zip,
            using: Crypto.payloadKey(teamSecret: teamSecret),
            nonce: try AES.GCM.Nonce(data: iv),
            authenticating: SyncBundleCodec.magic
        )
        return SyncBundleCodec.magic + iv + box.ciphertext + box.tag
    }

    private func gueltigesFoto(_ groesse: Int = 2048) -> Data {
        Data(repeating: 0xAB, count: groesse)
    }

    // MARK: - Dateinamen

    /// `.` und `..` sind der interessante Teil: Sie bestehen den Zeichentest und wurden erst
    /// durch diesen Test auffällig. Android fängt sie eine Stufe später ab, indem es den Pfad
    /// auflöst; auf der Swift-Seite gibt es diese zweite Stufe nicht.
    func testUnsichereDateinamenWerdenErkannt() {
        for name in ["../evil.jpg", "photos/../evil.jpg", "/etc/passwd", "..", ".", "", "a/b.jpg",
                     "foto mit leerzeichen.jpg", String(repeating: "a", count: 121)] {
            XCTAssertFalse(SyncBundleCodec.isSafeFileName(name), "„\(name)“ darf nicht durchgehen.")
        }
        for name in ["poster-1.jpg", "a.png", "A_B-c.1.jpeg", String(repeating: "a", count: 120)] {
            XCTAssertTrue(SyncBundleCodec.isSafeFileName(name), "„\(name)“ ist harmlos.")
        }
    }

    // MARK: - Was im Paket steckt, aber nicht im Snapshot steht

    func testNichtGenannteDateiWirdNichtGeschrieben() throws {
        // Der Angriff: ein zusaetzlicher Eintrag im ZIP, den kein Plakat nennt. Wuerde er
        // geschrieben, koennte ein Absender beliebige Dateien im Fotoordner ablegen.
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "echt.jpg")],
            dateien: [
                "photos/echt.jpg": gueltigesFoto(),
                "photos/heimlich.jpg": gueltigesFoto()
            ]
        )

        _ = try SyncBundleCodec.importVerifiedBundle(
            data: paket, local: lokalerStand(), photoTargetURL: ziel
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: ziel("echt.jpg").path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ziel("heimlich.jpg").path),
            "Nur Fotos, die der Snapshot nennt, duerfen auf die Platte."
        )
    }

    func testEintragAusserhalbVonPhotosWirdUebergangen() throws {
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "echt.jpg")],
            dateien: ["photos/echt.jpg": gueltigesFoto(), "anderswo.jpg": gueltigesFoto()]
        )

        _ = try SyncBundleCodec.importVerifiedBundle(
            data: paket, local: lokalerStand(), photoTargetURL: ziel
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: ziel("anderswo.jpg").path))
    }

    // MARK: - Größen

    func testZuGrossesFotoBrichtDenImportAb() throws {
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "riesig.jpg")],
            dateien: ["photos/riesig.jpg": gueltigesFoto(SyncBundleCodec.maxSinglePhotoBytes + 1)]
        )

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(
                data: paket, local: lokalerStand(), photoTargetURL: ziel
            )
        ) { fehler in
            XCTAssertEqual(fehler as? SyncError, .zuGross("Ein Foto im Sync-Paket"))
        }
    }

    func testZuGrosserSnapshotWirdAbgewiesen() throws {
        // Fotos sind einzeln und zusammen gedeckelt, der Snapshot-Eintrag im ZIP war es nicht —
        // eine als snapshot.json getarnte Zip-Bombe waere unbegrenzt entpackt worden.
        let archiv = try XCTUnwrap(Archive(accessMode: .create))
        let riesig = Data(repeating: 0x41, count: SyncBundleCodec.maxSnapshotBytes + 1)
        try archiv.addEntry(
            with: "snapshot.json", type: .file, uncompressedSize: Int64(riesig.count),
            provider: { pos, len in riesig.subdata(in: Int(pos)..<Int(pos) + len) }
        )
        let zip = try XCTUnwrap(archiv.data)
        var iv = Data(count: SyncBundleCodec.ivBytes)
        iv[0] = 11
        let box = try AES.GCM.seal(
            zip, using: Crypto.payloadKey(teamSecret: teamSecret),
            nonce: try AES.GCM.Nonce(data: iv), authenticating: SyncBundleCodec.magic
        )
        let paket = SyncBundleCodec.magic + iv + box.ciphertext + box.tag

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(
                data: paket, local: lokalerStand(), photoTargetURL: ziel
            )
        ) { fehler in
            XCTAssertEqual(fehler as? SyncError, .zuGross("Der Snapshot im Sync-Paket"))
        }
    }

    func testWinzigesFotoGiltAlsBeschaedigt() throws {
        // Unter 1 KB ist kein echtes Foto. Der Fall faengt abgeschnittene Uebertragungen ab,
        // die sonst als leeres Bild in der Liste stehen bleiben.
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "winzig.jpg")],
            dateien: ["photos/winzig.jpg": Data(repeating: 1, count: 10)]
        )

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(
                data: paket, local: lokalerStand(), photoTargetURL: ziel
            )
        )
    }

    // MARK: - Kaputte Hülle

    func testFremdeDateiIstKeinPaket() {
        XCTAssertThrowsError(
            try SyncBundleCodec.openBundle(Data("das ist ein Urlaubsfoto".utf8), teamSecret: teamSecret)
        ) { fehler in
            XCTAssertEqual(fehler as? SyncError, .ungueltigesPaket("Kein PRSYNC2-Paket."))
        }
    }

    func testAbgeschnittenesPaketWirdErkannt() throws {
        let paket = try gebasteltesPaket(posters: [plakat(foto: nil)], dateien: [:])
        let stumpf = paket.prefix(SyncBundleCodec.magic.count + 4)

        XCTAssertThrowsError(try SyncBundleCodec.openBundle(Data(stumpf), teamSecret: teamSecret))
    }

    func testPaketOhneSnapshotWirdAbgewiesen() throws {
        // Von Hand ein ZIP ohne snapshot.json, sonst gueltig verschluesselt.
        let archiv = try XCTUnwrap(Archive(accessMode: .create))
        let inhalt = gueltigesFoto()
        try archiv.addEntry(
            with: "photos/allein.jpg", type: .file, uncompressedSize: Int64(inhalt.count),
            provider: { pos, len in inhalt.subdata(in: Int(pos)..<Int(pos) + len) }
        )
        let zip = try XCTUnwrap(archiv.data)
        var iv = Data(count: SyncBundleCodec.ivBytes)
        iv[0] = 9
        let box = try AES.GCM.seal(
            zip, using: Crypto.payloadKey(teamSecret: teamSecret),
            nonce: try AES.GCM.Nonce(data: iv), authenticating: SyncBundleCodec.magic
        )
        let paket = SyncBundleCodec.magic + iv + box.ciphertext + box.tag

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(
                data: paket, local: lokalerStand(), photoTargetURL: ziel
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: ziel("allein.jpg").path))
    }

    // MARK: - Reihenfolge

    func testBeiFremdemTeamWirdNichtsGeschrieben() throws {
        // Das Paket ist technisch einwandfrei, gehoert aber zu einem anderen Team. Weil die
        // Team-Pruefung VOR dem Entpacken steht, darf keine einzige Datei entstehen.
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "echt.jpg")],
            dateien: ["photos/echt.jpg": gueltigesFoto()]
        )
        var fremd = lokalerStand()
        fremd.teamId = "ein-anderes-team"

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(data: paket, local: fremd, photoTargetURL: ziel)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: ziel("echt.jpg").path))
    }

    func testGesperrterAbsenderKommtNichtDurch() throws {
        let paket = try gebasteltesPaket(
            posters: [plakat(foto: "echt.jpg")],
            dateien: ["photos/echt.jpg": gueltigesFoto()]
        )
        var lokal = lokalerStand()
        lokal.devices = [
            DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER),
            DeviceRecord(deviceId: absender, displayName: "David", role: .LEADER, blocked: true)
        ]

        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(data: paket, local: lokal, photoTargetURL: ziel)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: ziel("echt.jpg").path))
    }
}
