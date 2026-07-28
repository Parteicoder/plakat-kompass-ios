import Foundation

/// Der lokale Datenstand auf der Platte.
///
/// Android verschlüsselt diese Datei von Hand über den Android Keystore. Auf iOS ist das nicht
/// nötig: Mit `.completeFileProtection` verschlüsselt das System die Datei selbst, der Schlüssel
/// hängt am Gerätecode und ist nur bei entsperrtem Gerät verfügbar. Selbst gebaute Verschlüsselung
/// wäre hier mehr Code für weniger Sicherheit.
public final class LocalRepository {

    private let ordner: URL
    private let statusDatei: URL
    public let photosDir: URL

    public init(ordner: URL) throws {
        self.ordner = ordner
        self.statusDatei = ordner.appendingPathComponent("teamstate.json")
        self.photosDir = ordner.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
    }

    public static func standard() throws -> LocalRepository {
        let basis = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try LocalRepository(ordner: basis.appendingPathComponent("PlakatKompass", isDirectory: true))
    }

    // MARK: - Laden und speichern

    public func load() -> LocalTeamState {
        guard let data = try? Data(contentsOf: statusDatei),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return neuerStand()
        }
        return (try? stateFromJson(root)) ?? neuerStand()
    }

    public func save(_ state: LocalTeamState) throws {
        let data = try JSONSerialization.data(
            withJSONObject: stateToJson(state), options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: statusDatei, options: [.atomic, .completeFileProtection])
    }

    private func neuerStand() -> LocalTeamState {
        LocalTeamState(
            deviceId: UUID().uuidString,
            deviceName: geraeteName()
        )
    }

    private func geraeteName() -> String {
        #if canImport(UIKit)
        return UIDeviceName.aktuell
        #else
        return "iPhone"
        #endif
    }

    // MARK: - Fotos

    public func photoURL(_ name: String) -> URL {
        photosDir.appendingPathComponent(name)
    }

    /// Legt ein Foto unter einem sicheren Namen ab und gibt diesen zurück.
    public func speichereFoto(_ data: Data) throws -> String {
        let name = "poster-\(UUID().uuidString).jpg"
        try data.write(to: photoURL(name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Löscht Fotos, die kein Plakat mehr nennt. Ohne das wächst der Ordner unbegrenzt.
    public func raeumeVerwaisteFotosAuf(_ state: LocalTeamState) {
        let gebraucht = Set(state.posters.compactMap(\.localPhotoFileName))
        let vorhanden = (try? FileManager.default.contentsOfDirectory(atPath: photosDir.path)) ?? []
        for name in vorhanden where !gebraucht.contains(name) {
            try? FileManager.default.removeItem(at: photoURL(name))
        }
    }

    // MARK: - Der lokale Stand als JSON
    //
    // Bewusst NICHT dasselbe Schema wie ein Sync-Paket: Hier stehen zusätzlich das
    // Team-Geheimnis und der Schlüsselbund, die ein Paket niemals verlassen dürfen.

    private func stateToJson(_ s: LocalTeamState) -> [String: Any] {
        var root: [String: Any] = [
            "schemaVersion": 1,
            "deviceId": s.deviceId,
            "deviceName": s.deviceName,
            "devices": s.devices.map(TeamStateJson.deviceToJson),
            "posters": (try? s.posters.map(TeamStateJson.posterToJson)) ?? [],
            "deletedPosters": s.deletedPosters.map(TeamStateJson.tombstoneToJson),
            "events": s.events.map(TeamStateJson.eventToJson),
            "flyerTours": (try? s.flyerTours.map(TeamStateJson.flyerTourToJson)) ?? []
        ]
        if let role = s.role { root["role"] = role.rawValue }
        if let teamId = s.teamId { root["teamId"] = teamId }
        if let teamName = s.teamName { root["teamName"] = teamName }
        if let teamSecret = s.teamSecret { root["teamSecret"] = teamSecret }
        return root
    }

    private func stateFromJson(_ root: [String: Any]) throws -> LocalTeamState {
        LocalTeamState(
            deviceId: try TeamStateJson.requiredString(root, "deviceId"),
            deviceName: TeamStateJson.optString(root, "deviceName", "iPhone"),
            role: (root["role"] as? String).flatMap(MemberRole.init(rawValue:)),
            teamId: root["teamId"] as? String,
            teamName: root["teamName"] as? String,
            teamSecret: root["teamSecret"] as? String,
            devices: try TeamStateJson.array(root, "devices").map(TeamStateJson.deviceFromJson),
            posters: try TeamStateJson.array(root, "posters").map(TeamStateJson.posterFromJson),
            deletedPosters: try TeamStateJson.array(root, "deletedPosters").map(TeamStateJson.tombstoneFromJson),
            events: try TeamStateJson.array(root, "events").map(TeamStateJson.eventFromJson),
            flyerTours: try TeamStateJson.array(root, "flyerTours").map(TeamStateJson.flyerTourFromJson)
        )
    }

    // MARK: - Ein Sync-Paket aus dem eigenen Stand

    public func toSnapshot(_ s: LocalTeamState) throws -> SyncSnapshot {
        guard let teamId = s.teamId, let teamSecret = s.teamSecret else {
            throw SyncError.fremdesTeam
        }
        return SyncSnapshot(
            teamId: teamId,
            teamName: s.teamName ?? "",
            senderDeviceId: s.deviceId,
            senderName: s.deviceName,
            teamSecretHash: Crypto.sha256Hex(teamSecret),
            devices: s.devices,
            posters: s.posters,
            deletedPosters: s.deletedPosters,
            events: s.events,
            flyerTours: s.flyerTours
        )
    }
}

#if canImport(UIKit)
import UIKit
enum UIDeviceName {
    @MainActor static var aktuell: String { UIDevice.current.name }
}
#endif
