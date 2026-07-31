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

    /// Der Funk-Abgleich mit Android. `lazy`, weil er `self` braucht — und weil er nichts tut,
    /// solange ihn niemand startet: Ohne `start()` gibt es weder Sichtbarkeit noch Suche.
    lazy private(set) var nearby = NearbyAbgleich(model: self)

    init() {
        do {
            // AppModel ist @MainActor, hier ist UIDevice.current.name erlaubt.
            let repo = try LocalRepository.standard(geraeteName: UIDevice.current.name)
            self.repo = repo

            // `load` wertet abgelaufene Fristen schon aus; einmal zurückschreiben, damit der
            // neue Status auch auf der Platte steht und nicht bei jedem Start neu entsteht.
            let geladen = repo.load()
            self.state = geladen
            try? repo.save(geladen)
        } catch {
            fatalError("Datenverzeichnis lässt sich nicht anlegen: \(error)")
        }
    }

    /// Wird beim Start aufgerufen, nicht im `init` — beides braucht `await`.
    func beimStart() async {
        haltEineTourAn()
        await Erinnerungen.frageErlaubnis()
        await Erinnerungen.planeNeu(fuer: state)
    }

    /// Eine eigene Tour, die beim Start noch auf „läuft" steht, wird pausiert.
    ///
    /// Beim Start läuft naturgemäß keine Aufzeichnung — der Aufzeichner ist gerade erst entstanden.
    /// Eine Tour, die trotzdem `ACTIVE` ist, stammt also aus einem Lauf, den iOS beendet hat.
    /// Bliebe sie so stehen, behauptete der Status etwas, das nicht stimmt, und der Zustand
    /// wanderte auch noch in jedes Sync-Paket. „Pausiert" ist die Wahrheit, und Fortsetzen ist
    /// ein Fingertipp.
    private func haltEineTourAn() {
        guard let offen = offeneTour, offen.status == .ACTIVE else { return }
        setzeTourStatus(offen, .PAUSED)
    }

    /// Wie viele Plakate fällig oder überfällig sind.
    var faelligeAbnahmen: Int {
        RemovalDeadlinePolicy.countDueOrOverdue(state.posters)
    }

    // Die Regeln stehen in `AccessPolicy` im Kern, nicht hier. Sie hier nachzubauen hiesse,
    // eine zweite Fassung zu pflegen, die von der Android-Seite abweichen kann — und die
    // Fälle „eigenes Gerät gesperrt" und „noch nicht freigegeben" kannten meine
    // selbstgebauten Eigenschaften gar nicht.
    var istEingerichtet: Bool { AccessPolicy.canAddPoster(state) }
    var kannAbgleichen: Bool { AccessPolicy.canSync(state) }
    var kannExportieren: Bool { AccessPolicy.canExportForAuthority(state) }
    var istTeamleitung: Bool { AccessPolicy.canManageTeamSecurity(state) }

    /// Gesperrte Geräte sollen erfahren, warum plötzlich nichts mehr geht.
    var istGesperrt: Bool { AccessPolicy.isSelfBlocked(state) }

    func photoURL(_ name: String) -> URL { repo.photoURL(name) }

    // MARK: - Erfassen

    /// Gibt zurück, ob es geklappt hat.
    ///
    /// Der Rückgabewert ist kein Zierrat: Die Oberfläche darf das Foto erst wegwerfen, wenn es
    /// wirklich gespeichert ist. Vorher wurde es in jedem Fall verworfen — nach einem Fehler
    /// stand der Nutzer mit einer Meldung da und ohne Bild, mitten auf der Straße, und musste
    /// zum Plakat zurück.
    @discardableResult
    func erfassePlakat(
        foto: Data,
        latitude: Double,
        longitude: Double,
        adresse: String,
        typ: PosterType,
        abnahmeInTagen: Int,
        amtlicheBemerkung: String,
        interneBemerkung: String
    ) -> Bool {
        guard let teamId = state.teamId else {
            fehler = "Erst einem Team beitreten, dann erfassen."
            return false
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
            return true
        } catch {
            fehler = error.localizedDescription
            return false
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
            // Fristen direkt nach dem Zusammenführen auswerten, nicht erst beim nächsten Start:
            // Ein hereingekommenes Plakat kann längst überfällig sein.
            let zusammengefuehrt = RemovalDeadlinePolicy.applyToState(
                try SyncMerge.merge(local: state, incoming: snapshot)
            )
            try speichere(zusammengefuehrt)
            meldung = "Paket von \(snapshot.senderName) übernommen."
        } catch {
            fehler = error.localizedDescription
        }
    }

    // MARK: - Flyer-Touren

    /// Die eigene laufende oder pausierte Tour, falls es eine gibt.
    var offeneTour: FlyerTour? {
        state.flyerTours.first { $0.createdByDeviceId == state.deviceId && $0.status != .FINISHED }
    }

    func starteTour(name: String) -> FlyerTour? {
        do {
            let neu = try repo.startFlyerTour(state, name: name)
            state = neu
            meldung = "Tour gestartet."
            return offeneTour
        } catch {
            fehler = error.localizedDescription
            return nil
        }
    }

    /// Wegpunkte kommen im Sekundentakt herein, während man läuft.
    ///
    /// Fehler werden hier bewusst **verschluckt**: Eine Fehlermeldung mitten auf der Straße,
    /// weil eine einzelne Ortung unbrauchbar war, hilft niemandem — die Tour läuft weiter und
    /// der nächste Punkt kommt in ein paar Sekunden.
    func merkeWegpunkt(tourId: String, latitude: Double, longitude: Double) {
        state = (try? repo.addFlyerTrackPoint(
            state, tourId: tourId, latitude: latitude, longitude: longitude
        )) ?? state
    }

    func setzeTourStatus(_ tour: FlyerTour, _ status: FlyerTourStatus) {
        do {
            state = try repo.setFlyerTourStatus(state, tour: tour, status: status)
        } catch {
            fehler = error.localizedDescription
        }
    }

    func loescheTour(_ tour: FlyerTour) {
        do {
            state = try repo.deleteFlyerTour(state, tour: tour)
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
    ///
    /// `eigenerName` ist kein Zierrat, siehe [benenneGeraet]: Ohne ihn hiesse die Teamleitung in
    /// ihrer eigenen Geräteliste „iPhone".
    func legeTeamAn(name: String, eigenerName: String = "") {
        var neu = state
        let meinName = eigenerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !meinName.isEmpty { neu.deviceName = meinName }
        neu.teamId = UUID().uuidString
        neu.teamName = name
        // Dieselben 32 Zufallsbytes als Hex wie auf Android — jetzt aus `Crypto`, wo die
        // Erzeugung ohnehin für den Handschlag gebraucht wird.
        neu.teamSecret = Crypto.randomNonceHex()
        neu.role = .LEADER
        neu.devices = [
            DeviceRecord(
                deviceId: state.deviceId, displayName: neu.deviceName,
                role: .LEADER, approved: true, blocked: false
            )
        ]
        try? speichere(neu)
        meldung = "Team „\(name)“ angelegt."
    }

    /// Loslegen ohne Team. Gegenstück zu `enterWithoutQr` auf Android.
    ///
    /// Nicht jeder plakatiert im Verbund. Wer allein für seine Gemeinde unterwegs ist, brauchte
    /// bis hierhin trotzdem erst ein Team — und stand damit vor einer Hürde, die für ihn keinen
    /// Zweck hat.
    ///
    /// Die Team-Kennung ist `offline-<Geräte-ID>`, das Geheimnis bleibt **leer**. Damit greift
    /// alles Weitere von allein richtig: Erfassen, Liste, Karte und der amtliche Export
    /// funktionieren, ein Sync-Paket lässt sich nicht erzeugen (`erzeugeSyncPaket` verlangt das
    /// Geheimnis) und keines annehmen (`SyncMerge.verify` ebenso). Es braucht dafür keine
    /// einzige Sonderbehandlung.
    func losOhneTeam(name: String) {
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else {
            fehler = "Bitte einen Namen eingeben."
            return
        }
        var neu = state
        neu.deviceName = sauber
        neu.role = .MEMBER
        neu.teamId = "offline-\(state.deviceId)"
        neu.teamName = "Ohne Team"
        neu.teamSecret = nil
        neu.devices = [
            DeviceRecord(deviceId: state.deviceId, displayName: sauber, role: .MEMBER, approved: true)
        ]
        try? speichere(neu)
        meldung = "Los geht's. Für den Abgleich mit anderen später einem Team beitreten."
    }

    /// Ohne Team-Geheimnis geht kein Abgleich — aber alles andere schon.
    var istOhneTeamUnterwegs: Bool { state.teamId != nil && state.teamSecret == nil }

    /// Tritt einem Team über den QR-Code des Teamleiters bei.
    ///
    /// Ohne diesen Weg gäbe es keinen Android-iOS-Abgleich: Er ist die einzige Stelle, an der
    /// zwei Geräte an dasselbe Team-Geheimnis kommen.
    func tritTeamBei(qrInhalt: String, eigenerName: String = "") {
        do {
            let einladung = try TeamInvite.decode(qrInhalt)
            guard einladung.istNochGueltig else {
                fehler = "Dieser Team-QR-Code ist abgelaufen. Bitte den Teamleiter um einen neuen bitten."
                return
            }
            // `beigetreten` konnte den Namen schon immer übernehmen — nur gab ihn hier nie jemand
            // mit. Siehe [benenneGeraet]: Das Ergebnis war ein Team, in dem jedes iPhone „iPhone"
            // hiess.
            let meinName = eigenerName.trimmingCharacters(in: .whitespacesAndNewlines)
            try speichere(state.beigetreten(mit: einladung, eigenerName: meinName.isEmpty ? nil : meinName))
            meldung = "Team „\(einladung.teamName)“ beigetreten."
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Benennt dieses Gerät um — auch nachträglich.
    ///
    /// **Warum es das überhaupt braucht:** Seit iOS 16 gibt `UIDevice.current.name` ohne
    /// Sonderberechtigung nur noch das Modell zurück, also schlicht „iPhone". Der Name wurde
    /// bisher allein im Weg „allein loslegen" gesetzt; wer per QR beitrat oder ein Team gründete,
    /// blieb „iPhone" — in der Geräteliste, im Verlauf jedes Plakats, in der Spalte „erfasst von"
    /// des amtlichen Exports und im Endpunktnamen des Funk-Abgleichs. Bei drei iPhones im Team
    /// konnte die Teamleitung nicht mehr erkennen, welches Gerät sie gerade freigibt oder sperrt.
    ///
    /// Der eigene Eintrag in der Geräteliste wird mitgezogen. Ohne das stünde der neue Name oben
    /// unter „Dieses Gerät" und der alte weiter unten in derselben Liste.
    func benenneGeraet(_ name: String) {
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty, sauber != state.deviceName else { return }
        var neu = state
        neu.deviceName = sauber
        if let index = neu.devices.firstIndex(where: { $0.deviceId == state.deviceId }) {
            neu.devices[index].displayName = sauber
        }
        try? speichere(neu)
        meldung = "Dieses Gerät heisst jetzt „\(sauber)“."
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
        do {
            var neu = try repo.setDeviceBlocked(state, deviceId: geraet.deviceId, blocked: false)
            if let index = neu.devices.firstIndex(where: { $0.deviceId == geraet.deviceId }) {
                neu.devices[index].approved = true
                try speichere(neu)
            }
            meldung = "\(geraet.displayName) freigegeben."
        } catch {
            fehler = error.localizedDescription
        }
    }

    func sperre(_ geraet: DeviceRecord) {
        do {
            state = try repo.setDeviceBlocked(state, deviceId: geraet.deviceId, blocked: true)
            meldung = "\(geraet.displayName) gesperrt."
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Erneuert das Team-Geheimnis.
    ///
    /// Der Weg für ein verlorenes Telefon. Ein Gerät zu sperren reicht nicht: Wer das alte
    /// Geheimnis hat, kann weiterhin jedes Paket entschlüsseln, das ihm in die Hände fällt.
    func erneuereTeamSchluessel() {
        do {
            state = try repo.rotateTeamSecret(state)
            meldung = "Team-Schlüssel erneuert. Alle anderen Geräte brauchen einen neuen QR-Code."
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Die einzige Stelle, an der geschrieben wird — und deshalb die einzige, an der die
    /// Erinnerungen nachgezogen werden müssen. Ein Plakat mit neuer Frist, ein gelöschtes, ein
    /// per Abgleich hereingekommenes: alles läuft hier durch.
    private func speichere(_ neu: LocalTeamState) throws {
        try repo.save(neu)
        state = neu
        Task { await Erinnerungen.planeNeu(fuer: neu) }
        // Aus demselben Grund hier: Wer gerade ein Plakat erfasst hat, soll es nicht erst beim
        // nächsten Verbindungsaufbau auf den anderen Geräten sehen. Läuft der Funk-Abgleich
        // nicht, kostet der Aufruf nichts.
        nearby.zustandGeaendert()
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
