import Foundation
import XCTest
@testable import PlakatKompassCore

/// Der Rückkanal beim Beitritt: Ein frisch per QR beigetretenes Gerät meldet sich zum ersten Mal.
///
/// Genau das ging nicht (Beobachtungen #233 und #235, siehe Android `SyncMergeBeitrittTest.kt`).
/// `verify` verlangte, dass der Absender bereits in der Geräteliste steht – ein neues Gerät steht
/// dort nie, es will sich ja gerade anmelden.
final class SyncMergeBeitrittTests: XCTestCase {

    private let teamId = "team-1"
    private let teamSecret = "secret-1"

    private func leitung(devices: [DeviceRecord]) -> LocalTeamState {
        LocalTeamState(
            deviceId: "leader-phone",
            deviceName: "David",
            role: .LEADER,
            teamId: teamId,
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: devices
        )
    }

    private var leitungAllein: LocalTeamState {
        leitung(devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)])
    }

    private func paketVomNeuling(
        secret: String? = nil,
        senderId: String = "member-phone"
    ) -> SyncSnapshot {
        SyncSnapshot(
            teamId: teamId,
            teamName: "BSW Nordsachsen",
            senderDeviceId: senderId,
            senderName: "Neues Handy",
            teamSecretHash: Crypto.sha256Hex(secret ?? teamSecret),
            // Das neue Gerät schickt sich selbst mit - so erfährt die Leitung überhaupt von ihm.
            devices: [DeviceRecord(deviceId: senderId, displayName: "Neues Handy", role: .MEMBER)],
            posters: [],
            events: []
        )
    }

    func testTeamleitungNimmtDenErstenGrussEinesNeuenGeraetsAn() {
        XCTAssertTrue(SyncMerge.verify(snapshot: paketVomNeuling(), local: leitungAllein))
    }

    func testDasNeueGeraetLandetAlsMitgliedInDerListe() throws {
        let danach = try SyncMerge.merge(local: leitungAllein, incoming: paketVomNeuling())
        let neu = try XCTUnwrap(danach.devices.first { $0.deviceId == "member-phone" })
        // Als Mitglied, nicht als zweite Leitung - egal was im Paket stand.
        XCTAssertEqual(neu.role, .MEMBER)
        // Und freigegeben, sonst würde schon der nächste Abgleich wieder abgewiesen.
        XCTAssertTrue(neu.approved)
        XCTAssertFalse(neu.blocked)
        // Die Leitung selbst bleibt in der Liste.
        XCTAssertTrue(danach.devices.contains { $0.deviceId == "leader-phone" && $0.role == .LEADER })
    }

    func testOhneDenTeamSchluesselHilftAuchDieLeitungNicht() {
        // Der Team-Schlüssel bleibt die Eintrittskarte. Daran ändert die Behebung nichts.
        XCTAssertFalse(SyncMerge.verify(snapshot: paketVomNeuling(secret: "falsch"), local: leitungAllein))
    }

    func testEinGesperrtesGeraetBleibtGesperrt() {
        // Das war der eigentliche Zweck der alten Zeile, und der muss erhalten bleiben: Wer
        // hinausgeworfen wurde, kommt mit demselben Schlüssel nicht wieder herein.
        let mitGesperrtem = leitung(devices: [
            DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER),
            DeviceRecord(deviceId: "member-phone", displayName: "Rausgeworfen", role: .MEMBER, blocked: true)
        ])
        XCTAssertFalse(SyncMerge.verify(snapshot: paketVomNeuling(), local: mitGesperrtem))
    }

    func testEinNochNichtFreigegebenesGeraetBleibtDraussen() {
        let mitUnbestaetigtem = leitung(devices: [
            DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER),
            DeviceRecord(deviceId: "member-phone", displayName: "Wartet", role: .MEMBER, approved: false)
        ])
        XCTAssertFalse(SyncMerge.verify(snapshot: paketVomNeuling(), local: mitUnbestaetigtem))
    }

    func testEinMitgliedNimmtKeineUnbekanntenAn() {
        // Aufnehmen darf nur die Leitung. Sonst schriebe sich ein neues Gerät an ihr vorbei über
        // ein beliebiges anderes Mitglied ins Team.
        let mitglied = LocalTeamState(
            deviceId: "other-member",
            deviceName: "Zweites Mitglied",
            role: .MEMBER,
            teamId: teamId,
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: "other-member", displayName: "Zweites Mitglied", role: .MEMBER),
                DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)
            ]
        )
        XCTAssertFalse(SyncMerge.verify(snapshot: paketVomNeuling(), local: mitglied))
    }

    func testDasEigeneGeraetGehtWeiterhinImmerDurch() {
        XCTAssertTrue(SyncMerge.verify(snapshot: paketVomNeuling(senderId: "leader-phone"), local: leitungAllein))
    }
}
