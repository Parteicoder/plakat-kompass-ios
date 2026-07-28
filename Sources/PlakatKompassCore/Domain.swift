import Foundation

/// Das Datenmodell, eins zu eins zur Android-Fassung in `core/Domain.kt`.
///
/// Die Namen der Fälle sind absichtlich die der Kotlin-Enums (`LAMP_POST` statt `lampPost`):
/// Genau diese Zeichenketten stehen im JSON eines Sync-Pakets. Wer sie hier „swiftiger" macht,
/// bricht die Kompatibilität mit Android, ohne dass es beim Übersetzen auffällt.

public enum MemberRole: String, Codable, Sendable {
    case LEADER
    case MEMBER
}

public enum PosterStatus: String, Codable, CaseIterable, Sendable {
    case HANGING
    case CHECKED
    case DAMAGED
    case MISSING
    case REPLACED
    case REMOVED
}

public enum PosterType: String, Codable, CaseIterable, Sendable {
    case LAMP_POST
    case FENCE
    case BANNER
    case TRIANGLE_STAND
    case LARGE_FORMAT
    case OTHER
}

public enum FlyerTourStatus: String, Codable, Sendable {
    case ACTIVE
    case PAUSED
    case FINISHED
}

public struct DeviceRecord: Equatable, Sendable {
    public var deviceId: String
    public var displayName: String
    public var role: MemberRole
    public var joinedAt: Int64
    public var approved: Bool
    public var blocked: Bool

    public init(
        deviceId: String,
        displayName: String,
        role: MemberRole,
        joinedAt: Int64 = Date.nowMillis,
        approved: Bool = true,
        blocked: Bool = false
    ) {
        self.deviceId = deviceId
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
        self.approved = approved
        self.blocked = blocked
    }
}

/// Lokaler Eintrag im Geräte-Schlüsselbund. Bleibt im lokalen Stand und wird **nicht** als Teil
/// eines Sync-Pakets verteilt.
public struct DeviceKeyRecord: Equatable, Sendable {
    public var deviceId: String
    public var displayName: String
    public var role: MemberRole
    public var teamSecretHash: String
    public var keyVersion: Int64
    public var createdAt: Int64
    public var active: Bool

    public init(
        deviceId: String,
        displayName: String,
        role: MemberRole,
        teamSecretHash: String,
        keyVersion: Int64 = 1,
        createdAt: Int64 = Date.nowMillis,
        active: Bool = true
    ) {
        self.deviceId = deviceId
        self.displayName = displayName
        self.role = role
        self.teamSecretHash = teamSecretHash
        self.keyVersion = keyVersion
        self.createdAt = createdAt
        self.active = active
    }
}

public struct Poster: Equatable, Identifiable, Sendable {
    public var id: String
    public var teamId: String
    public var latitude: Double
    public var longitude: Double
    public var addressHint: String
    public var type: PosterType
    public var status: PosterStatus
    public var localPhotoFileName: String?
    public var createdByDeviceId: String
    public var createdByName: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var plannedRemovalAt: Int64?
    public var officialNote: String
    public var internalNote: String

    public init(
        id: String = UUID().uuidString,
        teamId: String,
        latitude: Double,
        longitude: Double,
        addressHint: String = "",
        type: PosterType = .LAMP_POST,
        status: PosterStatus = .HANGING,
        localPhotoFileName: String? = nil,
        createdByDeviceId: String,
        createdByName: String,
        createdAt: Int64 = Date.nowMillis,
        updatedAt: Int64 = Date.nowMillis,
        plannedRemovalAt: Int64? = nil,
        officialNote: String = "",
        internalNote: String = ""
    ) {
        self.id = id
        self.teamId = teamId
        self.latitude = latitude
        self.longitude = longitude
        self.addressHint = addressHint
        self.type = type
        self.status = status
        self.localPhotoFileName = localPhotoFileName
        self.createdByDeviceId = createdByDeviceId
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plannedRemovalAt = plannedRemovalAt
        self.officialNote = officialNote
        self.internalNote = internalNote
    }
}

public struct FlyerTrackPoint: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var createdAt: Int64

    public init(latitude: Double, longitude: Double, createdAt: Int64 = Date.nowMillis) {
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

public struct FlyerTour: Equatable, Identifiable, Sendable {
    public var id: String
    public var teamId: String
    public var name: String
    public var status: FlyerTourStatus
    public var points: [FlyerTrackPoint]
    public var createdByDeviceId: String
    public var createdByName: String
    public var startedAt: Int64
    public var updatedAt: Int64
    public var finishedAt: Int64?

    public init(
        id: String = UUID().uuidString,
        teamId: String,
        name: String,
        status: FlyerTourStatus = .ACTIVE,
        points: [FlyerTrackPoint] = [],
        createdByDeviceId: String,
        createdByName: String,
        startedAt: Int64 = Date.nowMillis,
        updatedAt: Int64 = Date.nowMillis,
        finishedAt: Int64? = nil
    ) {
        self.id = id
        self.teamId = teamId
        self.name = name
        self.status = status
        self.points = points
        self.createdByDeviceId = createdByDeviceId
        self.createdByName = createdByName
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
    }
}

/// Löschmarker für ein Plakat.
///
/// Ohne ihn würde ein gelöschtes Plakat beim nächsten Abgleich von einem anderen Gerät wieder
/// auftauchen. Der Marker gewinnt beim Zusammenführen dauerhaft gegen das Plakat mit derselben ID.
public struct PosterTombstone: Equatable, Sendable {
    public var posterId: String
    public var teamId: String
    public var deletedByDeviceId: String
    public var deletedByName: String
    public var deletedAt: Int64

    public init(
        posterId: String,
        teamId: String,
        deletedByDeviceId: String,
        deletedByName: String,
        deletedAt: Int64 = Date.nowMillis
    ) {
        self.posterId = posterId
        self.teamId = teamId
        self.deletedByDeviceId = deletedByDeviceId
        self.deletedByName = deletedByName
        self.deletedAt = deletedAt
    }
}

public struct PosterEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var posterId: String
    public var teamId: String
    public var actorDeviceId: String
    public var actorName: String
    public var action: String
    public var createdAt: Int64

    public init(
        id: String = UUID().uuidString,
        posterId: String,
        teamId: String,
        actorDeviceId: String,
        actorName: String,
        action: String,
        createdAt: Int64 = Date.nowMillis
    ) {
        self.id = id
        self.posterId = posterId
        self.teamId = teamId
        self.actorDeviceId = actorDeviceId
        self.actorName = actorName
        self.action = action
        self.createdAt = createdAt
    }
}

public struct LocalTeamState: Equatable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var role: MemberRole?
    public var teamId: String?
    public var teamName: String?
    public var teamSecret: String?
    public var devices: [DeviceRecord]
    public var deviceKeyring: [DeviceKeyRecord]
    public var posters: [Poster]
    public var deletedPosters: [PosterTombstone]
    public var events: [PosterEvent]
    public var flyerTours: [FlyerTour]

    public init(
        deviceId: String,
        deviceName: String,
        role: MemberRole? = nil,
        teamId: String? = nil,
        teamName: String? = nil,
        teamSecret: String? = nil,
        devices: [DeviceRecord] = [],
        deviceKeyring: [DeviceKeyRecord] = [],
        posters: [Poster] = [],
        deletedPosters: [PosterTombstone] = [],
        events: [PosterEvent] = [],
        flyerTours: [FlyerTour] = []
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.role = role
        self.teamId = teamId
        self.teamName = teamName
        self.teamSecret = teamSecret
        self.devices = devices
        self.deviceKeyring = deviceKeyring
        self.posters = posters
        self.deletedPosters = deletedPosters
        self.events = events
        self.flyerTours = flyerTours
    }
}

public struct SyncSnapshot: Equatable, Sendable {
    public var teamId: String
    public var teamName: String
    public var senderDeviceId: String
    public var senderName: String
    public var teamSecretHash: String
    public var devices: [DeviceRecord]
    public var posters: [Poster]
    public var deletedPosters: [PosterTombstone]
    public var events: [PosterEvent]
    public var flyerTours: [FlyerTour]
    public var createdAt: Int64

    public init(
        teamId: String,
        teamName: String,
        senderDeviceId: String,
        senderName: String,
        teamSecretHash: String,
        devices: [DeviceRecord],
        posters: [Poster],
        deletedPosters: [PosterTombstone] = [],
        events: [PosterEvent],
        flyerTours: [FlyerTour] = [],
        createdAt: Int64 = Date.nowMillis
    ) {
        self.teamId = teamId
        self.teamName = teamName
        self.senderDeviceId = senderDeviceId
        self.senderName = senderName
        self.teamSecretHash = teamSecretHash
        self.devices = devices
        self.posters = posters
        self.deletedPosters = deletedPosters
        self.events = events
        self.flyerTours = flyerTours
        self.createdAt = createdAt
    }
}

extension Date {
    /// Android speichert Zeitstempel als Millisekunden seit 1970. Swift rechnet in Sekunden als
    /// `Double` — die Umrechnung gehört an eine Stelle, sonst schleicht sich der Faktor 1000
    /// irgendwo ein und die Fristen stimmen nicht mehr.
    public static var nowMillis: Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    public init(millis: Int64) {
        self.init(timeIntervalSince1970: Double(millis) / 1000.0)
    }
}
