import XCTest
@testable import PlakatKompassCore

/// Der QR-Code ist die zweite Nahtstelle zu Android — und die, ohne die gar nichts geht: Er ist
/// der einzige Weg, wie zwei Geräte an dasselbe Team-Geheimnis kommen.
///
/// Der Code unten ist nach Androids Regeln erzeugt (Felder mit `|` verbunden, jedes Base64-URL
/// **ohne** Padding) und nicht mit dem Swift-Code hier. Er passt zum Team des Sync-Testvektors,
/// sodass Beitritt und Paket zusammen geprüft werden können.
final class TeamInviteTests: XCTestCase {

    static let androidCodeV4 = """
    UExBS0FUUkFEQVI|NA|MTExMTExMTEtMjIyMi0zMzMzLTQ0NDQtNTU1NTU1NTU1NTU1|VGVzdHZla3Rvci1UZWFt|\
    QW5kcm9pZC1UZXN0Z2VyYWV0|YWFhYWFhYWEtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAx|\
    dGVzdHZla3Rvci10ZWFtLWdlaGVpbW5pcy0wMTIzNDU2Nzg5YWJjZGVm
    """

    func testCodeVonAndroidLaesstSichLesen() throws {
        let einladung = try TeamInvite.decode(Self.androidCodeV4)

        XCTAssertEqual(einladung.teamId, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(einladung.teamName, "Testvektor-Team")
        XCTAssertEqual(einladung.leaderName, "Android-Testgeraet")
        XCTAssertEqual(einladung.leaderDeviceId, "aaaaaaaa-0000-0000-0000-000000000001")
        XCTAssertEqual(einladung.teamSecret, "testvektor-team-geheimnis-0123456789abcdef")
        XCTAssertEqual(einladung.expiresAt, TeamInvite.permanentExpiresAt)
        XCTAssertTrue(einladung.istNochGueltig)
    }

    /// Das Ergebnis muss Byte für Byte dem entsprechen, was Android schreiben würde — sonst kann
    /// ein Android-Gerät den QR-Code eines iPhones nicht lesen.
    func testEigenerCodeSiehtAusWieDerVonAndroid() throws {
        let einladung = try TeamInvite.decode(Self.androidCodeV4)
        XCTAssertEqual(einladung.encodeForQr(), Self.androidCodeV4)
    }

    /// Base64-URL ohne Padding ist die Stelle, an der eine Nachbildung am ehesten danebenliegt:
    /// Foundation liefert Standard-Base64 mit `=`, `+` und `/`.
    func testBase64OhneFuellzeichenUndMitUrlAlphabet() {
        let code = try! TeamInvite.decode(Self.androidCodeV4).encodeForQr()
        XCTAssertFalse(code.contains("="), "Padding gehört nicht hinein")
        XCTAssertFalse(code.contains("+"), "+ gehört zum Standard-Alphabet, nicht zum URL-Alphabet")
        XCTAssertFalse(code.contains("/"), "/ gehört zum Standard-Alphabet, nicht zum URL-Alphabet")
    }

    func testUmlauteImTeamnamenUeberlebenHinUndRueckweg() throws {
        let original = TeamInvite(
            teamId: "t-1", teamName: "Bündnis Grünheide", leaderName: "Jörg Müller",
            leaderDeviceId: "d-1", teamSecret: "geheim"
        )
        let wieder = try TeamInvite.decode(original.encodeForQr())
        XCTAssertEqual(wieder.teamName, "Bündnis Grünheide")
        XCTAssertEqual(wieder.leaderName, "Jörg Müller")
    }

    func testRollenderCodeMitAblaufWirdGelesen() throws {
        let felder = [
            "PLAKATRADAR", "5", "t-1", "Team", "Leiter", "d-1", "schluessel",
            "7", "1700000000000", "1700000060000"
        ]
        let code = felder.map(TeamInvite.packeBase64Url).joined(separator: "|")
        let einladung = try TeamInvite.decode(code)

        XCTAssertEqual(einladung.teamSecret, "schluessel")
        XCTAssertEqual(einladung.expiresAt, 1_700_000_060_000)
        XCTAssertFalse(einladung.istNochGueltig, "Der Code ist von 2023 und muss abgelaufen sein")
    }

    func testFremderQrCodeWirdAbgewiesen() {
        let fremd = ["IRGENDWAS", "4", "x"].map(TeamInvite.packeBase64Url).joined(separator: "|")
        XCTAssertThrowsError(try TeamInvite.decode(fremd))
        XCTAssertThrowsError(try TeamInvite.decode("kein base64 |||"))
    }

    func testAlteVersionZweiWirdAbgewiesen() {
        let alt = ["PLAKATRADAR", "2", "t", "n"].map(TeamInvite.packeBase64Url).joined(separator: "|")
        XCTAssertThrowsError(try TeamInvite.decode(alt))
    }

    // MARK: - Beitritt

    /// Das eigene Gerät trägt sich **nicht** als freigegeben ein. Wer das täte, könnte sich in
    /// jedes Team schreiben, dessen QR-Code er einmal gesehen hat.
    func testNachBeitrittIstDasEigeneGeraetNochNichtFreigegeben() throws {
        let einladung = try TeamInvite.decode(Self.androidCodeV4)
        let vorher = LocalTeamState(deviceId: "mein-iphone", deviceName: "iPhone")
        let nachher = vorher.beigetreten(mit: einladung)

        XCTAssertEqual(nachher.teamId, einladung.teamId)
        XCTAssertEqual(nachher.teamSecret, einladung.teamSecret)
        XCTAssertEqual(nachher.role, .MEMBER)

        let eigenes = try XCTUnwrap(nachher.devices.first { $0.deviceId == "mein-iphone" })
        XCTAssertFalse(eigenes.approved, "Freigeben darf nur die Teamleitung")

        let leitung = try XCTUnwrap(nachher.devices.first { $0.deviceId == einladung.leaderDeviceId })
        XCTAssertEqual(leitung.role, .LEADER)
        XCTAssertTrue(leitung.approved)
    }

    /// Nach dem Beitritt muss sich der Sync-Testvektor öffnen lassen. Das ist der Beweis, dass
    /// beide Nahtstellen zusammenpassen: erst der QR-Code, dann das Paket.
    func testNachBeitrittLaesstSichDasPaketOeffnen() throws {
        let einladung = try TeamInvite.decode(Self.androidCodeV4)
        let stand = LocalTeamState(deviceId: "mein-iphone", deviceName: "iPhone")
            .beigetreten(mit: einladung)

        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sync-vektor-1", withExtension: "prsync", subdirectory: "Vektoren")
        )
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk-join-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let snapshot = try SyncBundleCodec.importVerifiedBundle(
            data: try Data(contentsOf: url),
            local: stand,
            photoTargetURL: { ordner.appendingPathComponent($0) }
        )
        XCTAssertEqual(snapshot.posters.count, 2)
    }
}
