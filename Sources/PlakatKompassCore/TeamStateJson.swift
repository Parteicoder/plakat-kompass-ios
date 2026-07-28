import Foundation

public enum SyncError: LocalizedError, Equatable {
    case ungueltigesPaket(String)
    case fremdesTeam
    case feldFehlt(String)
    case ungueltigeKoordinate(String)
    case zuGross(String)
    case neueresSchema
    /// Beim Verwaltungs-Export, nicht beim Abgleich — die Meldung landet vor jemandem, der
    /// gerade eine Liste fürs Rathaus bauen wollte und mit „Sync-Paket" nichts anfangen kann.
    case exportFehlgeschlagen(String)

    public var errorDescription: String? {
        switch self {
        case .ungueltigesPaket(let grund): return "Ungültiges Sync-Paket: \(grund)"
        case .fremdesTeam: return "Fremdes oder ungültiges Team-Paket."
        case .feldFehlt(let name): return "Im Sync-Paket fehlt das Feld „\(name)“."
        case .ungueltigeKoordinate(let quelle): return "\(quelle) enthält eine ungültige Koordinate."
        case .zuGross(let was): return "\(was) ist zu groß."
        case .neueresSchema:
            return "Sync-Paket stammt aus einer neueren App-Version. Bitte zuerst die App aktualisieren."
        case .exportFehlgeschlagen(let grund): return "Export für die Verwaltung fehlgeschlagen: \(grund)"
        }
    }
}

/// Übersetzung des Teamstands nach JSON und zurück — das Gegenstück zu `data/TeamStateJson.kt`.
///
/// Die Feldnamen sind der Vertrag mit Android. Jede Abweichung hier bedeutet, dass ein von einem
/// Android-Gerät geschriebenes Paket auf dem iPhone nicht mehr oder falsch gelesen wird, und zwar
/// ohne dass irgendetwas beim Übersetzen auffällt. Deshalb steht hier nichts „schöner" als drüben.
public enum TeamStateJson {

    static let snapshotSchemaVersion = 2

    // MARK: - Koordinaten

    /// Gegenstück zu `requireValidCoordinate`.
    ///
    /// Auf Android fehlte diese Prüfung eine Zeit lang im Backup-Pfad, wodurch NaN und
    /// Breitengrade jenseits von 90 in den Bestand gelangen konnten (Issue #204). Hier gilt sie
    /// von Anfang an überall.
    static func requireValidCoordinate(_ latitude: Double, _ longitude: Double, _ quelle: String) throws {
        guard latitude.isFinite, latitude >= -90, latitude <= 90 else {
            throw SyncError.ungueltigeKoordinate(quelle)
        }
        guard longitude.isFinite, longitude >= -180, longitude <= 180 else {
            throw SyncError.ungueltigeKoordinate(quelle)
        }
    }

    // MARK: - Snapshot

    public static func snapshotToJson(_ snapshot: SyncSnapshot) throws -> Data {
        let root: [String: Any] = [
            "schemaVersion": snapshotSchemaVersion,
            "teamId": snapshot.teamId,
            "teamName": snapshot.teamName,
            "senderDeviceId": snapshot.senderDeviceId,
            "senderName": snapshot.senderName,
            "teamSecretHash": snapshot.teamSecretHash,
            "devices": snapshot.devices.map(deviceToJson),
            "posters": try snapshot.posters.map(posterToJson),
            "deletedPosters": snapshot.deletedPosters.map(tombstoneToJson),
            "events": snapshot.events.map(eventToJson),
            "flyerTours": try snapshot.flyerTours.map(flyerTourToJson),
            "createdAt": snapshot.createdAt
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func snapshotFromJson(_ data: Data) throws -> SyncSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.ungueltigesPaket("snapshot.json ist kein Objekt.")
        }
        let schemaVersion = root["schemaVersion"] as? Int ?? snapshotSchemaVersion
        guard schemaVersion <= snapshotSchemaVersion else { throw SyncError.neueresSchema }

        return SyncSnapshot(
            teamId: try requiredString(root, "teamId"),
            teamName: try requiredString(root, "teamName"),
            senderDeviceId: try requiredString(root, "senderDeviceId"),
            senderName: try requiredString(root, "senderName"),
            teamSecretHash: try requiredString(root, "teamSecretHash"),
            devices: try array(root, "devices").map(deviceFromJson),
            posters: try array(root, "posters").map(posterFromJson),
            deletedPosters: try array(root, "deletedPosters").map(tombstoneFromJson),
            events: try array(root, "events").map(eventFromJson),
            flyerTours: try array(root, "flyerTours").map(flyerTourFromJson),
            createdAt: optLong(root, "createdAt", Date.nowMillis)
        )
    }

    // MARK: - Geräte

    static func deviceToJson(_ device: DeviceRecord) -> [String: Any] {
        [
            "deviceId": device.deviceId,
            "displayName": device.displayName,
            "role": device.role.rawValue,
            "joinedAt": device.joinedAt,
            "approved": device.approved,
            "blocked": device.blocked
        ]
    }

    static func deviceFromJson(_ o: [String: Any]) throws -> DeviceRecord {
        let role = try requiredEnum(o, "role", MemberRole.self)
        return DeviceRecord(
            deviceId: try requiredString(o, "deviceId"),
            displayName: try requiredString(o, "displayName"),
            role: role,
            joinedAt: optLong(o, "joinedAt", Date.nowMillis),
            approved: o["approved"] as? Bool ?? (role == .LEADER),
            blocked: o["blocked"] as? Bool ?? false
        )
    }

    // MARK: - Plakate

    static func posterToJson(_ p: Poster) throws -> [String: Any] {
        try requireValidCoordinate(p.latitude, p.longitude, "Plakat \(p.id)")
        return [
            "id": p.id,
            "teamId": p.teamId,
            "latitude": p.latitude,
            "longitude": p.longitude,
            "addressHint": p.addressHint,
            "type": p.type.rawValue,
            "status": p.status.rawValue,
            // Android schreibt hier "" statt null.
            "localPhotoFileName": p.localPhotoFileName ?? "",
            "createdByDeviceId": p.createdByDeviceId,
            "createdByName": p.createdByName,
            "createdAt": p.createdAt,
            "updatedAt": p.updatedAt,
            "plannedRemovalAt": p.plannedRemovalAt.map { $0 as Any } ?? NSNull(),
            "officialNote": p.officialNote,
            "internalNote": p.internalNote
        ]
    }

    static func posterFromJson(_ o: [String: Any]) throws -> Poster {
        let id = try requiredString(o, "id")
        let latitude = try requiredDouble(o, "latitude")
        let longitude = try requiredDouble(o, "longitude")
        try requireValidCoordinate(latitude, longitude, "Plakat \(id)")
        let photo = optString(o, "localPhotoFileName")
        return Poster(
            id: id,
            teamId: try requiredString(o, "teamId"),
            latitude: latitude,
            longitude: longitude,
            addressHint: optString(o, "addressHint"),
            type: optEnum(o, "type", PosterType.self, .LAMP_POST),
            status: optEnum(o, "status", PosterStatus.self, .HANGING),
            localPhotoFileName: photo.isEmpty ? nil : photo,
            createdByDeviceId: optString(o, "createdByDeviceId"),
            createdByName: optString(o, "createdByName"),
            createdAt: optLong(o, "createdAt", 0),
            updatedAt: optLong(o, "updatedAt", 0),
            plannedRemovalAt: optLongOrNil(o, "plannedRemovalAt"),
            officialNote: optString(o, "officialNote"),
            internalNote: optString(o, "internalNote")
        )
    }

    // MARK: - Löschmarker

    static func tombstoneToJson(_ t: PosterTombstone) -> [String: Any] {
        [
            "posterId": t.posterId,
            "teamId": t.teamId,
            "deletedByDeviceId": t.deletedByDeviceId,
            "deletedByName": t.deletedByName,
            "deletedAt": t.deletedAt
        ]
    }

    static func tombstoneFromJson(_ o: [String: Any]) throws -> PosterTombstone {
        PosterTombstone(
            posterId: try requiredString(o, "posterId"),
            teamId: optString(o, "teamId"),
            deletedByDeviceId: optString(o, "deletedByDeviceId"),
            deletedByName: optString(o, "deletedByName"),
            deletedAt: optLong(o, "deletedAt", Date.nowMillis)
        )
    }

    // MARK: - Flyer-Touren

    static func flyerTourToJson(_ tour: FlyerTour) throws -> [String: Any] {
        [
            "id": tour.id,
            "teamId": tour.teamId,
            "name": tour.name,
            "status": tour.status.rawValue,
            "points": try tour.points.map(trackPointToJson),
            "createdByDeviceId": tour.createdByDeviceId,
            "createdByName": tour.createdByName,
            "startedAt": tour.startedAt,
            "updatedAt": tour.updatedAt,
            "finishedAt": tour.finishedAt.map { $0 as Any } ?? NSNull()
        ]
    }

    static func flyerTourFromJson(_ o: [String: Any]) throws -> FlyerTour {
        FlyerTour(
            id: try requiredString(o, "id"),
            teamId: try requiredString(o, "teamId"),
            name: optString(o, "name", "Flyer-Tour"),
            status: optEnum(o, "status", FlyerTourStatus.self, .FINISHED),
            points: try (o["points"] as? [[String: Any]] ?? []).map(trackPointFromJson),
            createdByDeviceId: optString(o, "createdByDeviceId"),
            createdByName: optString(o, "createdByName"),
            startedAt: optLong(o, "startedAt", Date.nowMillis),
            updatedAt: optLong(o, "updatedAt", Date.nowMillis),
            finishedAt: optLongOrNil(o, "finishedAt")
        )
    }

    static func trackPointToJson(_ point: FlyerTrackPoint) throws -> [String: Any] {
        try requireValidCoordinate(point.latitude, point.longitude, "Flyer-Wegpunkt")
        return [
            "latitude": point.latitude,
            "longitude": point.longitude,
            "createdAt": point.createdAt
        ]
    }

    static func trackPointFromJson(_ o: [String: Any]) throws -> FlyerTrackPoint {
        let latitude = try requiredDouble(o, "latitude")
        let longitude = try requiredDouble(o, "longitude")
        try requireValidCoordinate(latitude, longitude, "Flyer-Wegpunkt")
        return FlyerTrackPoint(
            latitude: latitude,
            longitude: longitude,
            createdAt: optLong(o, "createdAt", Date.nowMillis)
        )
    }

    // MARK: - Ereignisse

    static func eventToJson(_ e: PosterEvent) -> [String: Any] {
        [
            "id": e.id,
            "posterId": e.posterId,
            "teamId": e.teamId,
            "actorDeviceId": e.actorDeviceId,
            "actorName": e.actorName,
            "action": e.action,
            "createdAt": e.createdAt
        ]
    }

    static func eventFromJson(_ o: [String: Any]) throws -> PosterEvent {
        PosterEvent(
            id: try requiredString(o, "id"),
            posterId: try requiredString(o, "posterId"),
            teamId: try requiredString(o, "teamId"),
            actorDeviceId: try requiredString(o, "actorDeviceId"),
            actorName: try requiredString(o, "actorName"),
            action: try requiredString(o, "action"),
            createdAt: optLong(o, "createdAt", 0)
        )
    }

    // MARK: - Lesehilfen
    //
    // Sie bilden die Semantik von Androids org.json nach: getString wirft, optString liefert "",
    // optLong liefert den Vorgabewert. Ohne diese Nachbildung verhielte sich dieselbe Datei auf
    // beiden Plattformen unterschiedlich, sobald ein Feld fehlt.

    static func array(_ o: [String: Any], _ key: String) -> [[String: Any]] {
        o[key] as? [[String: Any]] ?? []
    }

    static func requiredString(_ o: [String: Any], _ key: String) throws -> String {
        guard let value = o[key] as? String else { throw SyncError.feldFehlt(key) }
        return value
    }

    static func requiredDouble(_ o: [String: Any], _ key: String) throws -> Double {
        guard let number = o[key] as? NSNumber else { throw SyncError.feldFehlt(key) }
        return number.doubleValue
    }

    static func requiredEnum<T: RawRepresentable>(
        _ o: [String: Any], _ key: String, _ type: T.Type
    ) throws -> T where T.RawValue == String {
        guard let raw = o[key] as? String, let value = T(rawValue: raw) else {
            throw SyncError.feldFehlt(key)
        }
        return value
    }

    static func optString(_ o: [String: Any], _ key: String, _ fallback: String = "") -> String {
        (o[key] as? String) ?? fallback
    }

    static func optLong(_ o: [String: Any], _ key: String, _ fallback: Int64) -> Int64 {
        (o[key] as? NSNumber)?.int64Value ?? fallback
    }

    static func optLongOrNil(_ o: [String: Any], _ key: String) -> Int64? {
        guard let number = o[key] as? NSNumber else { return nil }
        return number.int64Value
    }

    static func optEnum<T: RawRepresentable>(
        _ o: [String: Any], _ key: String, _ type: T.Type, _ fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = o[key] as? String, let value = T(rawValue: raw) else { return fallback }
        return value
    }
}
