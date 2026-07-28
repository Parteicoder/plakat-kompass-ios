import Foundation

/// Die QR-Einladung des Teamleiters — Gegenstück zu `core/TeamInvite.kt` und
/// `core/RollingTeamInvite.kt`.
///
/// **Ohne diese Datei gibt es keinen Android-iOS-Abgleich.** Sie ist der einzige Weg, wie zwei
/// Geräte an dasselbe Team-Geheimnis kommen, und ohne gemeinsames Geheimnis lässt sich kein
/// Sync-Paket öffnen.
///
/// Aufbau: Felder mit `|` verbunden, jedes einzeln Base64-URL **ohne Padding**, UTF-8.
///
/// ```
/// Version 4 (stabil):  PLAKATRADAR | 4 | teamId | teamName | leaderName | leaderDeviceId | teamSecret
/// Version 5 (rollend): … | 5 | … | teamKey | sequence | createdAt | expiresAt      (60 s gültig)
/// Version 3 (alt):     … | 3 | … | teamSecret | createdAt | expiresAt
/// Version 2:           wird abgewiesen
/// ```
public struct TeamInvite: Equatable, Sendable {

    /// Entspricht `Long.MAX_VALUE` auf der Android-Seite: Einladung ohne Ablauf.
    public static let permanentExpiresAt: Int64 = .max

    public var teamId: String
    public var teamName: String
    public var leaderName: String
    public var leaderDeviceId: String
    public var teamSecret: String
    public var createdAt: Int64
    public var expiresAt: Int64

    public init(
        teamId: String,
        teamName: String,
        leaderName: String,
        leaderDeviceId: String,
        teamSecret: String,
        createdAt: Int64 = Date.nowMillis,
        expiresAt: Int64 = TeamInvite.permanentExpiresAt
    ) {
        self.teamId = teamId
        self.teamName = teamName
        self.leaderName = leaderName
        self.leaderDeviceId = leaderDeviceId
        self.teamSecret = teamSecret
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var istNochGueltig: Bool {
        expiresAt == Self.permanentExpiresAt || Date.nowMillis <= expiresAt
    }

    // MARK: - Lesen

    public static func decode(_ raw: String) throws -> TeamInvite {
        let felder = try raw.split(separator: "|", omittingEmptySubsequences: false).map {
            try entpackeBase64Url(String($0))
        }
        guard felder.first == "PLAKATRADAR" else {
            throw SyncError.ungueltigesPaket("Das ist kein Plakat-Kompass-QR-Code.")
        }
        guard felder.count >= 2 else { throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.") }

        switch felder[1] {
        case "4":
            guard felder.count == 7 else { throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.") }
            return TeamInvite(
                teamId: felder[2], teamName: felder[3], leaderName: felder[4],
                leaderDeviceId: felder[5], teamSecret: felder[6],
                expiresAt: permanentExpiresAt
            )

        case "5":
            guard felder.count == 10 else { throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.") }
            return TeamInvite(
                teamId: felder[2], teamName: felder[3], leaderName: felder[4],
                leaderDeviceId: felder[5], teamSecret: felder[6],
                createdAt: Int64(felder[8]) ?? Date.nowMillis,
                expiresAt: Int64(felder[9]) ?? 0
            )

        case "3":
            guard felder.count == 9 else { throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.") }
            return TeamInvite(
                teamId: felder[2], teamName: felder[3], leaderName: felder[4],
                leaderDeviceId: felder[5], teamSecret: felder[6],
                createdAt: Int64(felder[7]) ?? Date.nowMillis,
                expiresAt: Int64(felder[8]) ?? 0
            )

        case "2":
            throw SyncError.ungueltigesPaket(
                "Dieser alte Team-QR-Code wird nicht mehr unterstützt. Bitte einen neuen vom Teamleiter scannen."
            )

        default:
            throw SyncError.ungueltigesPaket("Diese QR-Code-Version wird nicht unterstützt.")
        }
    }

    // MARK: - Schreiben

    /// Version 4, damit ein Android-Gerät den Code eines iPhones lesen kann.
    public func encodeForQr() -> String {
        [
            "PLAKATRADAR", "4", teamId, teamName, leaderName, leaderDeviceId, teamSecret
        ]
        .map(packeBase64Url)
        .joined(separator: "|")
    }

    // MARK: - Base64-URL ohne Padding
    //
    // Java macht das mit `Base64.getUrlEncoder().withoutPadding()`. Foundation kennt nur
    // Standard-Base64 mit Padding, deshalb hier von Hand: - statt +, _ statt /, kein =.
    // Wer das übersieht, bekommt einen QR-Code, den Android nicht liest — und umgekehrt.

    static func packeBase64Url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func entpackeBase64Url(_ text: String) throws -> String {
        var roh = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rest = roh.count % 4
        if rest > 0 { roh += String(repeating: "=", count: 4 - rest) }

        guard let data = Data(base64Encoded: roh), let text = String(data: data, encoding: .utf8) else {
            throw SyncError.ungueltigesPaket("Ungültiger Team-QR-Code.")
        }
        return text
    }
}

extension LocalTeamState {
    /// Tritt einem Team über eine Einladung bei.
    ///
    /// Das eigene Gerät trägt sich als noch **nicht freigegebenes** Mitglied ein. Die Freigabe
    /// erteilt der Teamleiter beim nächsten Abgleich — genauso wie auf Android. Wer sich selbst
    /// freigäbe, könnte sich in jedes Team schreiben, dessen QR-Code er einmal gesehen hat.
    public func beigetreten(mit einladung: TeamInvite, eigenerName: String? = nil) -> LocalTeamState {
        var neu = self
        neu.teamId = einladung.teamId
        neu.teamName = einladung.teamName
        neu.teamSecret = einladung.teamSecret
        neu.role = .MEMBER
        if let eigenerName, !eigenerName.isEmpty { neu.deviceName = eigenerName }

        var geraete: [DeviceRecord] = [
            DeviceRecord(
                deviceId: einladung.leaderDeviceId,
                displayName: einladung.leaderName,
                role: .LEADER,
                approved: true,
                blocked: false
            )
        ]
        if einladung.leaderDeviceId != deviceId {
            geraete.append(
                DeviceRecord(
                    deviceId: deviceId,
                    displayName: neu.deviceName,
                    role: .MEMBER,
                    approved: false,
                    blocked: false
                )
            )
        }
        neu.devices = geraete
        return neu
    }
}
