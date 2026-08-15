import Foundation
import XCTest
@testable import PlakatKompassCore

/// Portierung von `DeviceKeyringPolicyTest.kt`.
final class DeviceKeyringPolicyTests: XCTestCase {

    private let teamSecret = "secret-1"

    func testTeamleitungBehaeltEintraegeFuerBekannteGeraete() {
        let state = LocalTeamState(
            deviceId: "leader-phone",
            deviceName: "David",
            role: .LEADER,
            teamId: "team-1",
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER, approved: true),
                DeviceRecord(deviceId: "member-phone", displayName: "Sven", role: .MEMBER, approved: true)
            ]
        )

        let schluesselbund = DeviceKeyringPolicy.normalizedFor(state)

        XCTAssertEqual(schluesselbund.map(\.deviceId), ["leader-phone", "member-phone"])
        XCTAssertEqual(Set(schluesselbund.map(\.teamSecretHash)), [Crypto.sha256Hex(teamSecret)])
    }

    func testMitgliedBehaeltNurEigenenEintrag() {
        let state = LocalTeamState(
            deviceId: "member-phone",
            deviceName: "Sven",
            role: .MEMBER,
            teamId: "team-1",
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER, approved: true),
                DeviceRecord(deviceId: "member-phone", displayName: "Sven", role: .MEMBER, approved: true)
            ]
        )

        let schluesselbund = DeviceKeyringPolicy.normalizedFor(state)

        XCTAssertEqual(schluesselbund.count, 1)
        XCTAssertEqual(schluesselbund.first?.deviceId, "member-phone")
    }

    func testGesperrtesGeraetIstImTeamleitungsSchluesselbundNichtAktiv() {
        let state = LocalTeamState(
            deviceId: "leader-phone",
            deviceName: "David",
            role: .LEADER,
            teamId: "team-1",
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER, approved: true),
                DeviceRecord(
                    deviceId: "old-phone", displayName: "Ausgeschieden", role: .MEMBER,
                    approved: false, blocked: true
                )
            ]
        )

        let schluesselbund = DeviceKeyringPolicy.normalizedFor(state)

        XCTAssertTrue(schluesselbund.first { $0.deviceId == "leader-phone" }?.active ?? false)
        XCTAssertFalse(schluesselbund.first { $0.deviceId == "old-phone" }?.active ?? true)
    }
}
