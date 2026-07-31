import Foundation
import XCTest
@testable import PlakatKompassCore

/// Der Handywechsel — die eine Stelle, an der ein Fehler den ganzen Datenbestand kostet.
///
/// Wer sein altes Handy schon zurückgegeben hat und dann merkt, dass das Backup nicht aufgeht,
/// hat nichts mehr. Deshalb prüft das hier nicht nur „läuft durch", sondern dass **jedes Feld**
/// wieder herauskommt, das hineinging — allen voran der `teamSecret`, ohne den das neue Gerät
/// zwar alle Plakate hätte, aber nie wieder abgleichen könnte.
final class DeviceBackupCodecTests: XCTestCase {

    private var ordner: URL!
    private var fotos: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fotos = ordner.appendingPathComponent("fotos", isDirectory: true)
        try FileManager.default.createDirectory(at: fotos, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func stand() -> LocalTeamState {
        LocalTeamState(
            deviceId: "altes-iphone",
            deviceName: "Davids iPhone",
            role: .LEADER,
            teamId: "team-umzug",
            teamName: "Ortsverband Süd",
            teamSecret: "das-geheimnis-das-mitmuss",
            devices: [
                DeviceRecord(deviceId: "altes-iphone", displayName: "Davids iPhone", role: .LEADER),
                DeviceRecord(deviceId: "handy-2", displayName: "Maltes Handy", role: .MEMBER)
            ],
            posters: [
                Poster(
                    id: "p1", teamId: "team-umzug", latitude: 51.46, longitude: 12.63,
                    localPhotoFileName: "p1.jpg",
                    createdByDeviceId: "altes-iphone", createdByName: "David"
                ),
                Poster(
                    id: "p2", teamId: "team-umzug", latitude: 51.47, longitude: 12.64,
                    createdByDeviceId: "handy-2", createdByName: "Malte"
                )
            ]
        )
    }

    /// Ein Foto, das die Mindestgroesse von 1 KiB ueberschreitet - darunter gilt es als kaputt.
    private func legeFotoAn(_ name: String) throws {
        try Data(repeating: 0x42, count: 2048).write(to: fotos.appendingPathComponent(name))
    }

    private func fotoQuelle(_ name: String) -> URL? {
        let url = fotos.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Der Umzug selbst

    func testBackupBringtDenGanzenStandZurueck() throws {
        try legeFotoAn("p1.jpg")
        let vorher = stand()
        let geheimnis = DeviceBackupCodec.neuesTransferGeheimnis()

        let paket = try DeviceBackupCodec.createBackup(
            state: vorher, transferSecret: geheimnis, photoURL: fotoQuelle
        )

        let ziel = ordner.appendingPathComponent("neu", isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        let nachher = try DeviceBackupCodec.restoreBackup(
            paket, transferSecret: geheimnis,
            photoTargetURL: { ziel.appendingPathComponent($0) }
        )

        XCTAssertEqual(nachher, vorher, "Der Stand ist beim Umzug nicht unverändert angekommen.")
        // Ausdruecklich noch einmal einzeln: Ohne den Team-Schluessel haette das neue Geraet
        // zwar alle Plakate, koennte aber nie wieder abgleichen - und das faellt erst auf,
        // wenn das alte Handy schon weg ist.
        XCTAssertEqual(nachher.teamSecret, "das-geheimnis-das-mitmuss")
        XCTAssertEqual(nachher.role, .LEADER)
        XCTAssertEqual(nachher.devices.count, 2)

        let angekommenesFoto = ziel.appendingPathComponent("p1.jpg")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: angekommenesFoto.path),
            "Das Foto ist nicht mitgekommen."
        )
        XCTAssertEqual(try Data(contentsOf: angekommenesFoto).count, 2048)
    }

    /// Ein Plakat ohne Foto darf kein Problem sein, und ein Foto, das auf der Platte fehlt,
    /// darf den ganzen Umzug nicht verhindern.
    func testFehlendesFotoLaesstDenUmzugTrotzdemZu() throws {
        // "p1.jpg" wird bewusst NICHT angelegt.
        let geheimnis = DeviceBackupCodec.neuesTransferGeheimnis()
        let paket = try DeviceBackupCodec.createBackup(
            state: stand(), transferSecret: geheimnis, photoURL: fotoQuelle
        )
        let nachher = try DeviceBackupCodec.restoreBackup(
            paket, transferSecret: geheimnis,
            photoTargetURL: { self.ordner.appendingPathComponent($0) }
        )
        XCTAssertEqual(nachher.posters.count, 2)
    }

    // MARK: - Was nicht passieren darf

    func testFalschesTransferGeheimnisOeffnetNichts() throws {
        try legeFotoAn("p1.jpg")
        let paket = try DeviceBackupCodec.createBackup(
            state: stand(), transferSecret: "richtig", photoURL: fotoQuelle
        )
        XCTAssertThrowsError(
            try DeviceBackupCodec.restoreBackup(
                paket, transferSecret: "falsch",
                photoTargetURL: { self.ordner.appendingPathComponent($0) }
            )
        ) { fehler in
            XCTAssertEqual(fehler as? SyncError, .fremdesTeam)
        }
    }

    /// **Der Punkt, an dem ein Backup kein Sync-Paket ist.** Beide sind AES-256-GCM über ein
    /// ZIP, beide sehen von aussen gleich aus. Wäre der Schlüssel derselbe, könnte ein
    /// Sync-Paket als Backup durchgehen — und damit ein fremder Stand die eigene Rolle und den
    /// eigenen Teamzugang überschreiben. Der Zusatz in der Schlüsselableitung verhindert das.
    func testTeamSchluesselOeffnetKeinBackup() throws {
        try legeFotoAn("p1.jpg")
        let teamSecret = "das-geheimnis-das-mitmuss"
        let paket = try DeviceBackupCodec.createBackup(
            state: stand(), transferSecret: teamSecret, photoURL: fotoQuelle
        )
        // Gleiches Geheimnis, andere Ableitung: Der Paket-Schluessel darf hier nicht passen.
        XCTAssertNotEqual(
            DeviceBackupCodec.transferKey(teamSecret).withUnsafeBytes { Data($0) },
            Crypto.payloadKey(teamSecret: teamSecret).withUnsafeBytes { Data($0) },
            "Backup- und Paket-Schlüssel sind identisch — die Trennung der Zwecke fehlt."
        )
        XCTAssertFalse(SyncBundleCodec.looksLikeBundle(paket), "Ein Backup gibt sich als Sync-Paket aus.")
        XCTAssertTrue(DeviceBackupCodec.looksLikeBackup(paket))
    }

    func testAbgeschnittenesPaketWirdAbgelehnt() throws {
        let paket = try DeviceBackupCodec.createBackup(
            state: stand(), transferSecret: "egal", photoURL: fotoQuelle
        )
        let halb = paket.prefix(DeviceBackupCodec.magic.count + 4)
        XCTAssertThrowsError(
            try DeviceBackupCodec.restoreBackup(
                Data(halb), transferSecret: "egal",
                photoTargetURL: { self.ordner.appendingPathComponent($0) }
            )
        )
    }

    /// Ein Backup muss auf Android lesbar sein. Die Feldnamen sind dafür der Vertrag.
    func testJsonTraegtDieFelderDieAndroidErwartet() throws {
        let daten = try DeviceBackupCodec.stateToJson(stand())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: daten) as? [String: Any])

        XCTAssertEqual(root["format"] as? String, "plakatradar-device-backup")
        XCTAssertEqual(root["schemaVersion"] as? Int, 2)
        XCTAssertEqual(root["teamSecret"] as? String, "das-geheimnis-das-mitmuss")
        XCTAssertEqual(root["role"] as? String, "LEADER")
        // Android liest dieses Feld; es fehlen zu lassen waere ein stiller Unterschied.
        XCTAssertNotNil(root["deviceKeyring"], "deviceKeyring fehlt — Android stolpert darüber.")
        for schluessel in ["devices", "posters", "deletedPosters", "events", "flyerTours"] {
            XCTAssertNotNil(root[schluessel] as? [Any], "Feld \(schluessel) fehlt oder ist keine Liste.")
        }
    }

    func testFremdesJsonWirdNichtAlsBackupGelesen() throws {
        let daten = try JSONSerialization.data(withJSONObject: ["format": "irgendwas"])
        XCTAssertThrowsError(try DeviceBackupCodec.stateFromJson(daten))
    }
}
