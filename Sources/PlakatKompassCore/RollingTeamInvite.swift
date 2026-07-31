import Foundation

/// Der **rollende** Team-QR-Code — Gegenstück zu `core/RollingTeamInvite.kt`.
///
/// **Warum es ihn braucht, und warum sein Fehlen ein Sicherheitsloch war:** Der QR-Code enthält
/// den Team-Schlüssel. Wer ihn abfotografiert, kann dem Team beitreten und jedes Sync-Paket
/// entschlüsseln, das ihm je in die Hände fällt. Android hält deshalb einen Code hin, der nach
/// **60 Sekunden** verfällt und danach durch einen neuen ersetzt wird.
///
/// Diese Fassung konnte rollende Codes von Anfang an **lesen** (Fassung 5 in
/// [TeamInvite.decode]), aber nur Fassung 4 **schreiben** — und die läuft nie ab. Ein Teamleiter
/// mit iPhone gab also einen dauerhaft gültigen Schlüssel aus, während dieselbe Rolle auf Android
/// einen Code für eine Minute ausgab. Zwei Plattformen, dieselbe Aufgabe, verschiedene
/// Sicherheit — und die schwächere fiel niemandem auf, weil beide Seiten sich verstanden.
///
/// Das Format ist byteweise Vertrag mit Android: zehn Felder, jeweils Base64-URL **ohne
/// Padding**, verbunden mit `|`. Die Kodierung teilt es sich mit [TeamInvite].
public struct RollingTeamInvite: Equatable, Sendable {

    /// Sechzig Sekunden, wie drüben `DEFAULT_TTL_SECONDS`. Lang genug, um einen Code
    /// hinzuhalten und scannen zu lassen; kurz genug, dass ein Foto davon wertlos wird.
    public static let ttlSekunden: Int64 = 60

    public let teamId: String
    public let teamName: String
    public let leaderName: String
    public let leaderDeviceId: String
    /// Heisst drüben `teamKey` und ist dasselbe wie `TeamInvite.teamSecret`.
    public let teamKey: String
    /// Zählt hoch, solange derselbe Bildschirm offen ist. Die Gegenseite wertet ihn nicht aus
    /// (`toTeamInvite` lässt ihn fallen) — er steht im Format und wird deshalb mitgeschrieben.
    public let sequence: Int64
    public let createdAt: Int64
    public let expiresAt: Int64

    public init(
        teamId: String,
        teamName: String,
        leaderName: String,
        leaderDeviceId: String,
        teamKey: String,
        sequence: Int64,
        createdAt: Int64 = Date.nowMillis,
        expiresAt: Int64? = nil
    ) {
        self.teamId = teamId
        self.teamName = teamName
        self.leaderName = leaderName
        self.leaderDeviceId = leaderDeviceId
        self.teamKey = teamKey
        self.sequence = sequence
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? (createdAt + Self.ttlSekunden * 1000)
    }

    public func encodeForQr() -> String {
        [
            "PLAKATRADAR", "5", teamId, teamName, leaderName, leaderDeviceId, teamKey,
            String(sequence), String(createdAt), String(expiresAt)
        ]
        .map(TeamInvite.packeBase64Url)
        .joined(separator: "|")
    }

    public static func decode(_ raw: String) throws -> RollingTeamInvite {
        let felder = try raw.split(separator: "|", omittingEmptySubsequences: false)
            .map { try TeamInvite.entpackeBase64Url(String($0)) }
        guard felder.count == 10 else {
            throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.")
        }
        guard felder[0] == "PLAKATRADAR", felder[1] == "5" else {
            throw SyncError.ungueltigesPaket("Das ist kein rollender Team-QR-Code.")
        }
        return RollingTeamInvite(
            teamId: felder[2],
            teamName: felder[3],
            leaderName: felder[4],
            leaderDeviceId: felder[5],
            teamKey: felder[6],
            sequence: Int64(felder[7]) ?? 0,
            createdAt: Int64(felder[8]) ?? Date.nowMillis,
            expiresAt: Int64(felder[9]) ?? 0
        )
    }

    /// Dieselbe Einladung in der Form, die der Beitritt verlangt.
    public var alsEinladung: TeamInvite {
        TeamInvite(
            teamId: teamId,
            teamName: teamName,
            leaderName: leaderName,
            leaderDeviceId: leaderDeviceId,
            teamSecret: teamKey,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}
