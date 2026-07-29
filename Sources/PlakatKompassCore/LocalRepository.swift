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
    private let geraeteName: String
    public let photosDir: URL

    /// [geraeteName] kommt von der App, nicht von hier.
    ///
    /// `UIDevice.current.name` ist an den Hauptthread gebunden; von einer beliebigen Stelle im
    /// Kern aus gelesen ist das ein Fehler, und zwar einer, der nur beim Bauen fuer iOS auffaellt.
    /// Grundsaetzlicher: Der Kern hat in UIKit nichts verloren - er soll auch ohne laufen.
    public init(ordner: URL, geraeteName: String = "iPhone") throws {
        self.ordner = ordner
        self.geraeteName = geraeteName
        self.statusDatei = ordner.appendingPathComponent("teamstate.json")
        self.photosDir = ordner.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
    }

    public static func standard(geraeteName: String = "iPhone") throws -> LocalRepository {
        let basis = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try LocalRepository(
            ordner: basis.appendingPathComponent("PlakatKompass", isDirectory: true),
            geraeteName: geraeteName
        )
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
        LocalTeamState(deviceId: UUID().uuidString, deviceName: geraeteName)
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

    // MARK: - Teamsicherheit

    /// Erneuert das Team-Geheimnis. Gegenstück zu `rotateTeamSecret` auf Android.
    ///
    /// Das ist die Antwort auf ein verlorenes oder gestohlenes Telefon. Ein Gerät zu sperren
    /// reicht dafür nicht: Wer das alte Geheimnis hat, kann weiterhin jedes Paket des Teams
    /// entschlüsseln, das ihm in die Hände fällt. Erst ein neues Geheimnis macht die alten
    /// Pakete für ihn wertlos.
    ///
    /// Der Preis ist unvermeidlich und muss in der Oberfläche stehen: **Alle anderen Geräte
    /// müssen einen neuen QR-Code scannen.** Wer das nicht tut, kann nicht mehr abgleichen.
    public func rotateTeamSecret(_ state: LocalTeamState) throws -> LocalTeamState {
        guard AccessPolicy.canManageTeamSecurity(state) else {
            throw SyncError.nichtErlaubt("Nur die Teamleitung kann den Team-Schlüssel erneuern.")
        }
        guard let teamId = state.teamId else { throw SyncError.fremdesTeam }

        var neu = state
        neu.teamSecret = neuesGeheimnis()
        neu.events.insert(
            PosterEvent(
                posterId: "TEAM",
                teamId: teamId,
                actorDeviceId: state.deviceId,
                actorName: state.deviceName,
                action: "Team-Schlüssel erneuert. Teammitglieder müssen einen neuen Teamleiter-QR scannen."
            ),
            at: 0
        )
        try save(neu)
        return neu
    }

    /// Sperrt ein Gerät oder gibt es wieder frei.
    ///
    /// Das eigene Gerät ist ausgenommen: Wer sich selbst sperrt, kommt an den eigenen Schlüssel
    /// nicht mehr heran und hat kein Mittel, das rückgängig zu machen.
    public func setDeviceBlocked(
        _ state: LocalTeamState, deviceId: String, blocked: Bool
    ) throws -> LocalTeamState {
        guard AccessPolicy.canManageTeamSecurity(state) else {
            throw SyncError.nichtErlaubt("Nur die Teamleitung kann Geräte sperren oder freigeben.")
        }
        guard deviceId != state.deviceId else {
            throw SyncError.nichtErlaubt("Das eigene Gerät lässt sich nicht sperren.")
        }
        guard let teamId = state.teamId,
              let index = state.devices.firstIndex(where: { $0.deviceId == deviceId })
        else { throw SyncError.fremdesTeam }

        var neu = state
        neu.devices[index].blocked = blocked
        neu.devices[index].approved = blocked ? false : neu.devices[index].approved
        let name = neu.devices[index].displayName.isEmpty
            ? String(deviceId.prefix(8))
            : neu.devices[index].displayName
        neu.events.insert(
            PosterEvent(
                posterId: "TEAM",
                teamId: teamId,
                actorDeviceId: state.deviceId,
                actorName: state.deviceName,
                action: blocked ? "Gerät gesperrt: \(name)" : "Gerät entsperrt: \(name)"
            ),
            at: 0
        )
        try save(neu)
        return neu
    }

    /// 32 Byte aus der Systemquelle, hexadezimal.
    ///
    /// Android setzt hier zwei UUIDs aneinander. Gleich lang, aber UUIDv4 liefert nur 122
    /// nutzbare Bits je Stück; hier stehen 256 echte Zufallsbits. Das Format ist frei — das
    /// Geheimnis geht nur als Hash ins Paket und wird sonst nirgends verglichen.
    private func neuesGeheimnis() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
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
