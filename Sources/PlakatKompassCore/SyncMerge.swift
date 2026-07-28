import Foundation

/// Zusammenführen zweier Datenstände — Portierung von `core/SyncMerge.kt`.
///
/// Die Regeln sind nicht frei gewählt, sie müssen mit Android übereinstimmen. Sonst hat dasselbe
/// Team nach einem Abgleich zwei verschiedene Wahrheiten, je nachdem, wessen Gerät zusammengeführt
/// hat. Jede Änderung hier gehört drüben genauso gemacht.
public enum SyncMerge {

    public static func verify(snapshot: SyncSnapshot, local: LocalTeamState) -> Bool {
        guard let localTeamId = local.teamId, let localSecret = local.teamSecret else { return false }
        guard snapshot.teamId == localTeamId else { return false }
        guard Crypto.constantTimeEquals(snapshot.teamSecretHash, Crypto.sha256Hex(localSecret)) else {
            return false
        }
        if snapshot.senderDeviceId == local.deviceId { return true }
        return local.devices.contains {
            $0.deviceId == snapshot.senderDeviceId && $0.approved && !$0.blocked
        }
    }

    public static func merge(local: LocalTeamState, incoming: SyncSnapshot) throws -> LocalTeamState {
        guard verify(snapshot: incoming, local: local) else { throw SyncError.fremdesTeam }

        let incomingSenderIsKnownLeader =
            local.devices.contains {
                $0.deviceId == incoming.senderDeviceId && $0.role == .LEADER && $0.approved && !$0.blocked
            } || (local.role == .LEADER && incoming.senderDeviceId == local.deviceId)

        let incomingSenderApprovedByLocal =
            local.devices.contains {
                $0.deviceId == incoming.senderDeviceId && $0.approved && !$0.blocked
            } || incoming.senderDeviceId == local.deviceId

        var deviceMap: [String: DeviceRecord] = [:]
        for device in local.devices { deviceMap[device.deviceId] = device }

        for incomingDevice in incoming.devices {
            let old = deviceMap[incomingDevice.deviceId]
            guard let safeIncoming = sanitizeIncomingDevice(
                local: local,
                incoming: incoming,
                incomingDevice: incomingDevice,
                old: old,
                incomingSenderIsKnownLeader: incomingSenderIsKnownLeader,
                incomingSenderApprovedByLocal: incomingSenderApprovedByLocal
            ) else { continue }

            let finalOld = deviceMap[safeIncoming.deviceId]
            if finalOld == nil {
                deviceMap[safeIncoming.deviceId] = safeIncoming
            } else if incomingSenderIsKnownLeader {
                deviceMap[safeIncoming.deviceId] = safeIncoming
            } else if finalOld!.blocked {
                deviceMap[safeIncoming.deviceId] = finalOld!
            } else if safeIncoming.deviceId == incoming.senderDeviceId && incomingSenderApprovedByLocal {
                deviceMap[safeIncoming.deviceId] = safeIncoming
            } else {
                deviceMap[safeIncoming.deviceId] = finalOld!
            }
        }

        var approvedDeviceIds = Set(deviceMap.values.filter { $0.approved && !$0.blocked }.map(\.deviceId))
        approvedDeviceIds.insert(local.deviceId)

        // Löschmarker zuerst: Nur solche von freigegebenen Geräten zählen. Ein Marker gewinnt
        // dauerhaft gegen das Plakat mit derselben ID, damit Gelöschtes nicht wieder auftaucht.
        // Bei zwei Markern gewinnt der ÄLTERE — so wie drüben.
        var tombstoneMap: [String: PosterTombstone] = [:]
        for tombstone in local.deletedPosters { tombstoneMap[tombstone.posterId] = tombstone }
        for incomingTombstone in incoming.deletedPosters
        where approvedDeviceIds.contains(incomingTombstone.deletedByDeviceId) {
            let old = tombstoneMap[incomingTombstone.posterId]
            if old == nil || incomingTombstone.deletedAt < old!.deletedAt {
                tombstoneMap[incomingTombstone.posterId] = incomingTombstone
            }
        }

        var posterMap: [String: Poster] = [:]
        for poster in local.posters { posterMap[poster.id] = poster }
        for incomingPoster in incoming.posters
        where approvedDeviceIds.contains(incomingPoster.createdByDeviceId) {
            posterMap[incomingPoster.id] = mergePoster(old: posterMap[incomingPoster.id], incoming: incomingPoster)
        }
        for deletedPosterId in tombstoneMap.keys { posterMap.removeValue(forKey: deletedPosterId) }

        var tourMap: [String: FlyerTour] = [:]
        for tour in local.flyerTours { tourMap[tour.id] = tour }
        for incomingTour in incoming.flyerTours
        where approvedDeviceIds.contains(incomingTour.createdByDeviceId) {
            tourMap[incomingTour.id] = mergeFlyerTour(old: tourMap[incomingTour.id], incoming: incomingTour)
        }

        var eventMap: [String: PosterEvent] = [:]
        for event in local.events { eventMap[event.id] = event }
        for incomingEvent in incoming.events
        where approvedDeviceIds.contains(incomingEvent.actorDeviceId) {
            eventMap[incomingEvent.id] = incomingEvent
        }

        var merged = local
        merged.teamName = local.teamName ?? incoming.teamName
        merged.devices = deviceMap.values.sorted {
            let leftIsLeader = $0.role == .LEADER
            let rightIsLeader = $1.role == .LEADER
            if leftIsLeader != rightIsLeader { return leftIsLeader }
            return $0.displayName < $1.displayName
        }
        merged.posters = posterMap.values.sorted { $0.updatedAt > $1.updatedAt }
        merged.deletedPosters = tombstoneMap.values.sorted { $0.deletedAt > $1.deletedAt }
        merged.flyerTours = tourMap.values.sorted { $0.updatedAt > $1.updatedAt }
        merged.events = eventMap.values.sorted { $0.createdAt > $1.createdAt }
        return merged
    }

    private static func sanitizeIncomingDevice(
        local: LocalTeamState,
        incoming: SyncSnapshot,
        incomingDevice: DeviceRecord,
        old: DeviceRecord?,
        incomingSenderIsKnownLeader: Bool,
        incomingSenderApprovedByLocal: Bool
    ) -> DeviceRecord? {
        if incomingDevice.deviceId == local.deviceId {
            if let old { return old }
            var eigenes = incomingDevice
            eigenes.role = local.role ?? incomingDevice.role
            eigenes.approved = true
            eigenes.blocked = false
            return eigenes
        }

        if incomingSenderIsKnownLeader { return incomingDevice }

        if incomingSenderApprovedByLocal && incomingDevice.deviceId == incoming.senderDeviceId {
            if var vorhanden = old {
                if !incomingDevice.displayName.isEmpty { vorhanden.displayName = incomingDevice.displayName }
                return vorhanden
            }
            var neu = incomingDevice
            neu.role = .MEMBER
            neu.approved = false
            neu.blocked = false
            return neu
        }

        if local.role == .LEADER, old == nil, incomingDevice.deviceId == incoming.senderDeviceId {
            var neu = incomingDevice
            neu.role = .MEMBER
            neu.approved = incomingDevice.approved && !incomingDevice.blocked
            neu.blocked = false
            return neu
        }

        return old
    }

    private static func mergePoster(old: Poster?, incoming: Poster) -> Poster {
        guard let old else { return incoming }

        if incoming.updatedAt == old.updatedAt {
            var merged = old
            merged.localPhotoFileName = old.localPhotoFileName ?? incoming.localPhotoFileName
            if old.addressHint.isEmpty { merged.addressHint = incoming.addressHint }
            if old.officialNote.isEmpty { merged.officialNote = incoming.officialNote }
            if old.internalNote.isEmpty { merged.internalNote = incoming.internalNote }
            merged.plannedRemovalAt = old.plannedRemovalAt ?? incoming.plannedRemovalAt
            return merged
        }

        if incoming.updatedAt < old.updatedAt { return old }

        var merged = incoming
        merged.localPhotoFileName = incoming.localPhotoFileName ?? old.localPhotoFileName
        if incoming.addressHint.isEmpty { merged.addressHint = old.addressHint }
        if incoming.officialNote.isEmpty { merged.officialNote = old.officialNote }
        if incoming.internalNote.isEmpty { merged.internalNote = old.internalNote }
        merged.plannedRemovalAt = incoming.plannedRemovalAt ?? old.plannedRemovalAt
        return merged
    }

    private static func mergeFlyerTour(old: FlyerTour?, incoming: FlyerTour) -> FlyerTour {
        guard let old else { return incoming }

        var gesehen = Set<String>()
        let mergedPoints = (old.points + incoming.points)
            .filter { point in
                let schluessel = "\(point.createdAt):\(point.latitude):\(point.longitude)"
                return gesehen.insert(schluessel).inserted
            }
            .sorted { $0.createdAt < $1.createdAt }

        let bevorzugtIstIncoming: Bool
        if incoming.updatedAt > old.updatedAt {
            bevorzugtIstIncoming = true
        } else if incoming.updatedAt < old.updatedAt {
            bevorzugtIstIncoming = false
        } else {
            bevorzugtIstIncoming = statusRank(incoming.status) > statusRank(old.status)
        }

        let preferred = bevorzugtIstIncoming ? incoming : old
        let fallback = bevorzugtIstIncoming ? old : incoming

        var merged = preferred
        merged.points = mergedPoints
        if preferred.name.isEmpty { merged.name = fallback.name }
        if preferred.createdByDeviceId.isEmpty { merged.createdByDeviceId = fallback.createdByDeviceId }
        if preferred.createdByName.isEmpty { merged.createdByName = fallback.createdByName }
        merged.startedAt = min(old.startedAt, incoming.startedAt)
        merged.updatedAt = max(old.updatedAt, incoming.updatedAt)
        merged.finishedAt = preferred.finishedAt ?? fallback.finishedAt
        return merged
    }

    private static func statusRank(_ status: FlyerTourStatus) -> Int {
        switch status {
        case .ACTIVE: return 0
        case .PAUSED: return 1
        case .FINISHED: return 2
        }
    }
}
