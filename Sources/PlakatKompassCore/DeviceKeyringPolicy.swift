import Foundation

/// Baut den lokalen Geräte-Schlüsselbund aus dem aktuellen Gerätestand. Portierung von
/// `DeviceKeyringPolicy.kt`.
///
/// Wichtig: Der Schlüsselbund ist lokaler Sicherheitszustand. Er wird nicht als Teil von
/// `SyncSnapshot` verteilt. Die Teamleitung hält Einträge für bekannte Teamgeräte, ein
/// Teammitglied nur für sein eigenes Gerät.
public enum DeviceKeyringPolicy {
    public static func normalizedFor(_ state: LocalTeamState) -> [DeviceKeyRecord] {
        guard let secret = state.teamSecret, let role = state.role else { return [] }
        let currentHash = Crypto.sha256Hex(secret)
        let existing = Dictionary(uniqueKeysWithValues: state.deviceKeyring.map { ($0.deviceId, $0) })

        let visibleDevices: [DeviceRecord]
        switch role {
        case .LEADER:
            visibleDevices = state.devices
        case .MEMBER:
            visibleDevices = [
                state.devices.first { $0.deviceId == state.deviceId }
                    ?? DeviceRecord(
                        deviceId: state.deviceId, displayName: state.deviceName, role: .MEMBER,
                        approved: true, blocked: false
                    )
            ]
        }

        var gesehen = Set<String>()
        return visibleDevices
            .filter { gesehen.insert($0.deviceId).inserted }
            .map { device -> DeviceKeyRecord in
                let old = existing[device.deviceId]
                return DeviceKeyRecord(
                    deviceId: device.deviceId,
                    displayName: device.displayName,
                    role: device.role,
                    teamSecretHash: currentHash,
                    keyVersion: old?.keyVersion ?? 1,
                    createdAt: old?.createdAt ?? Date.nowMillis,
                    active: device.approved && !device.blocked
                )
            }
            .sorted {
                let leftIsLeader = $0.role == .LEADER
                let rightIsLeader = $1.role == .LEADER
                if leftIsLeader != rightIsLeader { return leftIsLeader }
                return $0.displayName < $1.displayName
            }
    }

    public static func withNormalizedKeyring(_ state: LocalTeamState) -> LocalTeamState {
        var neu = state
        neu.deviceKeyring = normalizedFor(state)
        return neu
    }
}
