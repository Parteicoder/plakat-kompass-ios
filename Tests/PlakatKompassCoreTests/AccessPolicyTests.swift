import Foundation
import XCTest
@testable import PlakatKompassCore

/// Wer darf was — und die Erneuerung des Team-Schlüssels.
///
/// Die Fälle stammen aus `AccessPolicyTest.kt` und `DeviceKeyringPolicyTest.kt` auf Android,
/// erweitert um die beiden Zustände, die es auf iOS bisher gar nicht gab: „allein unterwegs"
/// und „eigenes Gerät gesperrt".
final class AccessPolicyTests: XCTestCase {

    private func team(
        rolle: MemberRole = .MEMBER,
        geheimnis: String? = "secret-1",
        eigenesApproved: Bool = true,
        eigenesBlocked: Bool = false
    ) -> LocalTeamState {
        LocalTeamState(
            deviceId: "me",
            deviceName: "Mein Gerät",
            role: rolle,
            teamId: "team-1",
            teamName: "Team",
            teamSecret: geheimnis,
            devices: [
                DeviceRecord(
                    deviceId: "me", displayName: "Mein Gerät", role: rolle,
                    approved: eigenesApproved, blocked: eigenesBlocked
                ),
                DeviceRecord(deviceId: "leader", displayName: "David", role: .LEADER)
            ]
        )
    }

    /// Wer allein losgelegt hat: Team-Kennung ja, Geheimnis nein.
    private func allein() -> LocalTeamState {
        LocalTeamState(
            deviceId: "me", deviceName: "Ich", role: .MEMBER,
            teamId: "offline-me", teamName: "Ohne Team", teamSecret: nil,
            devices: [DeviceRecord(deviceId: "me", displayName: "Ich", role: .MEMBER)]
        )
    }

    private func garNichts() -> LocalTeamState {
        LocalTeamState(deviceId: "me", deviceName: "Ich")
    }

    // MARK: - Erfassen

    func testErfassenBrauchtKeinGeheimnis() {
        XCTAssertTrue(AccessPolicy.canAddPoster(allein()), "Wer allein plakatiert, muss erfassen koennen.")
        XCTAssertTrue(AccessPolicy.canAddPoster(team()))
        XCTAssertFalse(AccessPolicy.canAddPoster(garNichts()))
    }

    // MARK: - Abgleich

    func testAbgleichBrauchtDasGeheimnis() {
        XCTAssertTrue(AccessPolicy.canSync(team()))
        XCTAssertFalse(AccessPolicy.canSync(allein()), "Ohne Geheimnis liesse sich kein Paket oeffnen.")
        XCTAssertFalse(AccessPolicy.canSync(garNichts()))
    }

    func testNochNichtFreigegebenDarfNichtAbgleichen() {
        // Nach dem Beitritt traegt sich das eigene Geraet als nicht freigegeben ein. Bis die
        // Teamleitung es freischaltet, ist der Abgleich zu.
        XCTAssertFalse(AccessPolicy.canSync(team(eigenesApproved: false)))
    }

    func testGesperrtesGeraetDarfNichtAbgleichen() {
        XCTAssertFalse(AccessPolicy.canSync(team(eigenesBlocked: true)))
        XCTAssertTrue(AccessPolicy.isSelfBlocked(team(eigenesBlocked: true)))
    }

    func testDieTeamleitungGiltImmerAlsFreigegeben() {
        // Sonst koennte sie sich selbst aussperren und kaeme an den eigenen Schluessel nicht mehr.
        XCTAssertTrue(AccessPolicy.isSelfApproved(team(rolle: .LEADER, eigenesApproved: false)))
        XCTAssertTrue(AccessPolicy.canShowQr(team(rolle: .LEADER, eigenesApproved: false)))
    }

    // MARK: - Amtlicher Export

    func testExportGehtAuchOhneTeam() {
        XCTAssertTrue(AccessPolicy.canExportForAuthority(allein()))
        XCTAssertTrue(AccessPolicy.canExportForAuthority(team()))
        XCTAssertFalse(AccessPolicy.canExportForAuthority(garNichts()))
    }

    func testGesperrtesGeraetExportiertNicht() {
        // Wer aus dem Team geworfen wurde, soll nicht in dessen Namen bei der Gemeinde auftreten.
        XCTAssertFalse(AccessPolicy.canExportForAuthority(team(eigenesBlocked: true)))
    }

    // MARK: - QR und Teamsicherheit

    func testNurDieTeamleitungZeigtDenQrCode() {
        XCTAssertTrue(AccessPolicy.canShowQr(team(rolle: .LEADER)))
        XCTAssertFalse(AccessPolicy.canShowQr(team(rolle: .MEMBER)))
        XCTAssertFalse(AccessPolicy.canShowQr(allein()))
    }

    // MARK: - Schlüssel erneuern

    private func repository() throws -> (LocalRepository, URL) {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (try LocalRepository(ordner: ordner, geraeteName: "Test"), ordner)
    }

    func testErneuernAendertDasGeheimnisUndHinterlaesstEinEreignis() throws {
        let (repo, ordner) = try repository()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let vorher = team(rolle: .LEADER)
        let nachher = try repo.rotateTeamSecret(vorher)

        XCTAssertNotEqual(nachher.teamSecret, vorher.teamSecret)
        XCTAssertEqual(nachher.teamSecret?.count, 64, "32 Byte hexadezimal.")
        XCTAssertEqual(nachher.events.first?.posterId, "TEAM")
        XCTAssertTrue(nachher.events.first?.action.contains("erneuert") == true)

        // Und es liegt auf der Platte, nicht nur im Speicher.
        XCTAssertEqual(repo.load().teamSecret, nachher.teamSecret)
    }

    func testAlteePaketeLassenSichNachDemErneuernNichtMehrOeffnen() throws {
        let (repo, ordner) = try repository()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let vorher = team(rolle: .LEADER)
        let paket = try SyncBundleCodec.createBundle(
            snapshot: repo.toSnapshot(vorher), teamSecret: try XCTUnwrap(vorher.teamSecret),
            photoURL: { _ in nil }
        )

        let nachher = try repo.rotateTeamSecret(vorher)

        // Genau darum geht es: Wer das alte Geheimnis hat, kommt an neue Pakete nicht mehr heran -
        // und alte Pakete passen nicht mehr zum neuen Stand.
        XCTAssertThrowsError(
            try SyncBundleCodec.importVerifiedBundle(
                data: paket, local: nachher, photoTargetURL: { ordner.appendingPathComponent($0) }
            )
        )
    }

    func testNurDieTeamleitungDarfErneuern() throws {
        let (repo, ordner) = try repository()
        defer { try? FileManager.default.removeItem(at: ordner) }

        XCTAssertThrowsError(try repo.rotateTeamSecret(team(rolle: .MEMBER))) { fehler in
            guard case .nichtErlaubt = fehler as? SyncError else {
                return XCTFail("Erwartet wurde nichtErlaubt, kam: \(fehler)")
            }
        }
    }

    func testDasEigeneGeraetLaesstSichNichtSperren() throws {
        let (repo, ordner) = try repository()
        defer { try? FileManager.default.removeItem(at: ordner) }

        // Sonst kaeme man an den eigenen Schluessel nicht mehr heran, ohne ein Mittel dagegen.
        XCTAssertThrowsError(
            try repo.setDeviceBlocked(team(rolle: .LEADER), deviceId: "me", blocked: true)
        )
    }

    func testSperrenNimmtDieFreigabeMit() throws {
        let (repo, ordner) = try repository()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let nachher = try repo.setDeviceBlocked(team(rolle: .LEADER), deviceId: "leader", blocked: true)
        let gesperrt = try XCTUnwrap(nachher.devices.first { $0.deviceId == "leader" })

        XCTAssertTrue(gesperrt.blocked)
        XCTAssertFalse(gesperrt.approved, "Gesperrt und trotzdem freigegeben waere ein Widerspruch.")
        XCTAssertTrue(nachher.events.first?.action.contains("gesperrt") == true)
    }
}
