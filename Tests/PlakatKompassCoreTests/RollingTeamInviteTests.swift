import XCTest
@testable import PlakatKompassCore

/// Der rollende Team-QR-Code ist ein **Wire-Format mit Android**, kein internes Detail. Deshalb
/// wird hier nicht geprüft, ob Kodieren und Dekodieren zueinander passen — das täten sie auch,
/// wenn beide dieselbe falsche Kodierung benutzten. Geprüft wird die **erwartete Zeichenkette**.
///
/// Der Erwartungswert stammt aus einem Python-Dreizeiler mit `base64.urlsafe_b64encode`, also
/// weder aus dieser Swift-Fassung noch aus der Kotlin-Seite. Genau darin liegt sein Wert.
final class RollingTeamInviteTests: XCTestCase {

    private func beispiel() -> RollingTeamInvite {
        RollingTeamInvite(
            teamId: "11111111-2222-3333-4444-555555555555",
            teamName: "Testteam",
            leaderName: "Anna",
            leaderDeviceId: "aaaaaaaa-0000-0000-0000-000000000001",
            teamKey: "testvektor-team-geheimnis-0123456789abcdef",
            sequence: 7,
            createdAt: 1_700_000_000_000,
            expiresAt: 1_700_000_060_000
        )
    }

    /// Base64-URL **ohne Padding**, zehn Felder, mit `|` verbunden. Ein `=` zu viel oder ein `+`
    /// statt `-` ergibt einen Code, den die Android-Seite nicht liest — und man sucht den Fehler
    /// bei der Kamera.
    func testKodierungTrifftDasVereinbarteFormat() {
        let erwartet = "UExBS0FUUkFEQVI|NQ"
            + "|MTExMTExMTEtMjIyMi0zMzMzLTQ0NDQtNTU1NTU1NTU1NTU1"
            + "|VGVzdHRlYW0|QW5uYQ"
            + "|YWFhYWFhYWEtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAx"
            + "|dGVzdHZla3Rvci10ZWFtLWdlaGVpbW5pcy0wMTIzNDU2Nzg5YWJjZGVm"
            + "|Nw|MTcwMDAwMDAwMDAwMA|MTcwMDAwMDA2MDAwMA"
        XCTAssertEqual(beispiel().encodeForQr(), erwartet)
        XCTAssertFalse(beispiel().encodeForQr().contains("="), "Padding gehört nicht hinein.")
        XCTAssertEqual(beispiel().encodeForQr().split(separator: "|").count, 10)
    }

    func testRueckwegLiefertDasselbe() throws {
        XCTAssertEqual(try RollingTeamInvite.decode(beispiel().encodeForQr()), beispiel())
    }

    /// Der eigentliche Zweck: Ein rollender Code, den `TeamInvite` liest, muss dieselbe Frist
    /// tragen. Sonst wäre er wieder unbegrenzt gültig — und die ganze Übung umsonst.
    func testTeamInviteUebernimmtDieFrist() throws {
        let gelesen = try TeamInvite.decode(beispiel().encodeForQr())
        XCTAssertEqual(gelesen.expiresAt, 1_700_000_060_000)
        XCTAssertNotEqual(gelesen.expiresAt, TeamInvite.permanentExpiresAt)
        XCTAssertFalse(gelesen.istNochGueltig, "Ein Code von 2023 darf heute nicht mehr gelten.")
        XCTAssertEqual(gelesen.teamSecret, beispiel().teamKey)
    }

    /// Ohne Angabe sind es sechzig Sekunden, wie drüben `DEFAULT_TTL_SECONDS`.
    func testVorgabefristSindSechzigSekunden() {
        let frisch = RollingTeamInvite(
            teamId: "t", teamName: "n", leaderName: "l", leaderDeviceId: "d",
            teamKey: "k", sequence: 0, createdAt: 1_000_000
        )
        XCTAssertEqual(frisch.expiresAt - frisch.createdAt, 60_000)
        XCTAssertTrue(frisch.alsEinladung.expiresAt == frisch.expiresAt)
    }

    /// Ein Code der alten, dauerhaften Fassung 4 ist kein rollender.
    func testFassungVierWirdAbgelehnt() {
        let alt = TeamInvite(
            teamId: "t", teamName: "n", leaderName: "l", leaderDeviceId: "d", teamSecret: "k"
        ).encodeForQr()
        XCTAssertThrowsError(try RollingTeamInvite.decode(alt))
    }
}
