import Foundation
import PlakatKompassCore
import SwiftUI
import UIKit

/// Der Zustand der App an einer Stelle — das Gegenstück zu `PlakatRadarViewModel` auf Android.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var state: LocalTeamState
    @Published var meldung: String?
    @Published var fehler: String?

    /// Solange kein Foto aufgenommen wurde, steht im Erfassen-Bereich ein Einstiegs-Hinweis.
    /// Genau wie auf Android verschwindet er dauerhaft nach dem ersten Foto.
    @AppStorage("hatFotoAufgenommen") var hatFotoAufgenommen = false

    private let repo: LocalRepository

    init() {
        do {
            // AppModel ist @MainActor, hier ist UIDevice.current.name erlaubt.
            let repo = try LocalRepository.standard(geraeteName: UIDevice.current.name)
            self.repo = repo

            // Abgelaufene Fristen gleich beim Start auswerten. Ohne diese Zeile stünde ein
            // überfälliges Plakat weiter auf „Hängt", bis jemand es zufällig anfasst.
            let geladen = RemovalDeadlinePolicy.applyToState(repo.load())
            self.state = geladen
            try? repo.save(geladen)
        } catch {
            fatalError("Datenverzeichnis lässt sich nicht anlegen: \(error)")
        }
    }

    /// Wird beim Start aufgerufen, nicht im `init` — beides braucht `await`.
    func beimStart() async {
        await Erinnerungen.frageErlaubnis()
        await Erinnerungen.planeNeu(fuer: state)
    }

    /// Wie viele Plakate fällig oder überfällig sind.
    var faelligeAbnahmen: Int {
        RemovalDeadlinePolicy.countDueOrOverdue(state.posters)
    }

    var istImTeam: Bool { state.teamId != nil && state.teamSecret != nil }

    func photoURL(_ name: String) -> URL { repo.photoURL(name) }

    // MARK: - Erfassen

    func erfassePlakat(
        foto: Data,
        latitude: Double,
        longitude: Double,
        adresse: String,
        typ: PosterType,
        abnahmeInTagen: Int,
        amtlicheBemerkung: String,
        interneBemerkung: String
    ) {
        guard let teamId = state.teamId else {
            fehler = "Erst einem Team beitreten, dann erfassen."
            return
        }
        do {
            let dateiname = try repo.speichereFoto(foto)
            let jetzt = Date.nowMillis
            let plakat = Poster(
                teamId: teamId,
                latitude: latitude,
                longitude: longitude,
                addressHint: adresse,
                type: typ,
                status: .HANGING,
                localPhotoFileName: dateiname,
                createdByDeviceId: state.deviceId,
                createdByName: state.deviceName,
                createdAt: jetzt,
                updatedAt: jetzt,
                plannedRemovalAt: jetzt + Int64(abnahmeInTagen) * 24 * 60 * 60 * 1000,
                officialNote: amtlicheBemerkung,
                internalNote: interneBemerkung
            )
            var neu = state
            neu.posters.insert(plakat, at: 0)
            neu.events.insert(
                PosterEvent(
                    posterId: plakat.id, teamId: teamId,
                    actorDeviceId: state.deviceId, actorName: state.deviceName,
                    action: "erfasst"
                ),
                at: 0
            )
            try speichere(neu)
            hatFotoAufgenommen = true
            meldung = "Plakat erfasst."
        } catch {
            fehler = error.localizedDescription
        }
    }

    func setzeStatus(_ plakat: Poster, _ status: PosterStatus) {
        guard let index = state.posters.firstIndex(where: { $0.id == plakat.id }) else { return }
        var neu = state
        neu.posters[index].status = status
        neu.posters[index].updatedAt = Date.nowMillis
        neu.events.insert(
            PosterEvent(
                posterId: plakat.id, teamId: plakat.teamId,
                actorDeviceId: state.deviceId, actorName: state.deviceName,
                action: "Status: \(status.beschriftung)"
            ),
            at: 0
        )
        try? speichere(neu)
    }

    /// Löschen hinterlässt einen Marker. Ohne ihn käme das Plakat beim nächsten Abgleich
    /// von einem anderen Gerät zurück.
    func loesche(_ plakat: Poster) {
        var neu = state
        neu.posters.removeAll { $0.id == plakat.id }
        neu.deletedPosters.insert(
            PosterTombstone(
                posterId: plakat.id,
                teamId: plakat.teamId,
                deletedByDeviceId: state.deviceId,
                deletedByName: state.deviceName
            ),
            at: 0
        )
        try? speichere(neu)
        repo.raeumeVerwaisteFotosAuf(neu)
    }

    // MARK: - Abgleich über den Teilen-Dialog

    /// Baut ein Sync-Paket und legt es als Datei ab, die der Teilen-Dialog verschicken kann.
    func erzeugeSyncPaket() -> URL? {
        guard let teamSecret = state.teamSecret else {
            fehler = "Ohne Team-Schlüssel lässt sich kein Paket erzeugen."
            return nil
        }
        do {
            let snapshot = try repo.toSnapshot(state)
            let paket = try SyncBundleCodec.createBundle(
                snapshot: snapshot,
                teamSecret: teamSecret,
                photoURL: { [repo] name in repo.photoURL(name) }
            )
            let ziel = FileManager.default.temporaryDirectory
                .appendingPathComponent("plakatkompass-sync-\(Date.nowMillis).prsync")
            try paket.write(to: ziel, options: .atomic)
            return ziel
        } catch {
            fehler = error.localizedDescription
            return nil
        }
    }

    /// Nimmt ein Paket entgegen, das über den Teilen-Dialog oder „Öffnen mit" hereinkommt.
    func importiereSyncPaket(von url: URL) {
        let brauchtFreigabe = url.startAccessingSecurityScopedResource()
        defer { if brauchtFreigabe { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try SyncBundleCodec.importVerifiedBundle(
                data: data,
                local: state,
                photoTargetURL: { [repo] name in repo.photoURL(name) }
            )
            let zusammengefuehrt = try SyncMerge.merge(local: state, incoming: snapshot)
            try speichere(zusammengefuehrt)
            meldung = "Paket von \(snapshot.senderName) übernommen."
        } catch {
            fehler = error.localizedDescription
        }
    }

    // MARK: - Export für die Verwaltung

    /// Baut die Plakatliste samt Fotos als ZIP und legt sie als Datei ab, die der Teilen-Dialog
    /// verschicken kann.
    ///
    /// Anders als ein Sync-Paket ist das **unverschlüsselt** — es geht an die Stadtverwaltung,
    /// nicht an ein Teamgerät. Der Team-Schlüssel und die internen Bemerkungen sind deshalb auch
    /// nicht darin: `OfficialExport` schreibt nur die Spalten, die im Rathaus etwas zu suchen haben.
    func erzeugeVerwaltungsExport(kommune: String) -> URL? {
        do {
            let daten = try OfficialExport.zipData(
                state: state,
                municipality: kommune.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Kommune" : kommune,
                photoURL: { [repo] name in repo.photoURL(name) }
            )
            let ziel = FileManager.default.temporaryDirectory
                .appendingPathComponent(ExportNames.authorityZipName(municipality: kommune))
            try daten.write(to: ziel, options: .atomic)
            return ziel
        } catch {
            fehler = error.localizedDescription
            return nil
        }
    }

    // MARK: - Team

    /// Legt ein Team an. Das Geheimnis verlässt das Gerät nur als Hash im Sync-Paket.
    func legeTeamAn(name: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        var neu = state
        neu.teamId = UUID().uuidString
        neu.teamName = name
        neu.teamSecret = bytes.map { String(format: "%02x", $0) }.joined()
        neu.role = .LEADER
        neu.devices = [
            DeviceRecord(
                deviceId: state.deviceId, displayName: state.deviceName,
                role: .LEADER, approved: true, blocked: false
            )
        ]
        try? speichere(neu)
        meldung = "Team „\(name)“ angelegt."
    }

    /// Tritt einem Team über den QR-Code des Teamleiters bei.
    ///
    /// Ohne diesen Weg gäbe es keinen Android-iOS-Abgleich: Er ist die einzige Stelle, an der
    /// zwei Geräte an dasselbe Team-Geheimnis kommen.
    func tritTeamBei(qrInhalt: String) {
        do {
            let einladung = try TeamInvite.decode(qrInhalt)
            guard einladung.istNochGueltig else {
                fehler = "Dieser Team-QR-Code ist abgelaufen. Bitte den Teamleiter um einen neuen bitten."
                return
            }
            try speichere(state.beigetreten(mit: einladung))
            meldung = "Team „\(einladung.teamName)“ beigetreten."
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Der eigene Einladungscode — nur sinnvoll, wenn dieses Gerät die Teamleitung hat.
    func einladungFuerQr() -> String? {
        guard state.role == .LEADER,
              let teamId = state.teamId,
              let teamSecret = state.teamSecret
        else { return nil }
        return TeamInvite(
            teamId: teamId,
            teamName: state.teamName ?? "Plakat-Team",
            leaderName: state.deviceName,
            leaderDeviceId: state.deviceId,
            teamSecret: teamSecret
        ).encodeForQr()
    }

    /// Gibt ein wartendes Gerät frei. Nur die Teamleitung darf das.
    func gibFrei(_ geraet: DeviceRecord) {
        guard state.role == .LEADER,
              let index = state.devices.firstIndex(where: { $0.deviceId == geraet.deviceId })
        else { return }
        var neu = state
        neu.devices[index].approved = true
        neu.devices[index].blocked = false
        try? speichere(neu)
        meldung = "\(geraet.displayName) freigegeben."
    }

    func sperre(_ geraet: DeviceRecord) {
        guard state.role == .LEADER,
              let index = state.devices.firstIndex(where: { $0.deviceId == geraet.deviceId })
        else { return }
        var neu = state
        neu.devices[index].blocked = true
        neu.devices[index].approved = false
        try? speichere(neu)
        meldung = "\(geraet.displayName) gesperrt."
    }

    /// Die einzige Stelle, an der geschrieben wird — und deshalb die einzige, an der die
    /// Erinnerungen nachgezogen werden müssen. Ein Plakat mit neuer Frist, ein gelöschtes, ein
    /// per Abgleich hereingekommenes: alles läuft hier durch.
    private func speichere(_ neu: LocalTeamState) throws {
        try repo.save(neu)
        state = neu
        Task { await Erinnerungen.planeNeu(fuer: neu) }
    }
}

extension PosterStatus {
    var beschriftung: String {
        switch self {
        case .HANGING: return "Hängt"
        case .CHECKED: return "Kontrolliert"
        case .DAMAGED: return "Beschädigt"
        case .MISSING: return "Fehlt"
        case .REPLACED: return "Ersetzt"
        case .REMOVED: return "Entfernt"
        }
    }

    var farbe: Color {
        switch self {
        case .HANGING, .REPLACED: return Color(red: 0.39, green: 0.40, blue: 0.95)
        case .CHECKED: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .DAMAGED, .MISSING: return Color(red: 0.86, green: 0.15, blue: 0.15)
        case .REMOVED: return Color(red: 0.39, green: 0.45, blue: 0.55)
        }
    }
}

extension PosterType {
    var beschriftung: String {
        switch self {
        case .LAMP_POST: return "Laternenmast"
        case .FENCE: return "Zaun"
        case .BANNER: return "Banner"
        case .TRIANGLE_STAND: return "Dreieckständer"
        case .LARGE_FORMAT: return "Großformat"
        case .OTHER: return "Sonstiges"
        }
    }
}
