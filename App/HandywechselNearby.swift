import Foundation
import NearbyConnections
import PlakatKompassCore

/// Der Umzug auf ein neues iPhone — Gegenstück zu `sync/DeviceBackupNearbyManager.kt`.
///
/// **Warum das nicht in [NearbyAbgleich] steckt, obwohl beides Nearby ist:** Der Abgleich
/// verbindet *alle* Teamgeräte dauerhaft und tauscht Änderungen aus. Der Umzug verbindet genau
/// **zwei** Geräte, einmalig, in festen Rollen — und das neue hat noch gar kein Team, also auch
/// keinen Team-Schlüssel für den Handschlag. Beides in eine Klasse zu zwingen hiesse, in jedem
/// Rückruf erst zu fragen, worum es gerade geht.
///
/// **Der Ablauf, wortgleich mit Android:**
///
/// 1. Beide Seiten kündigen sich an: `PlakatRadarBackup|SEND|…` bzw. `…|RECEIVE|…`
/// 2. Gefunden wird **nur über Kreuz** — zwei Sender warten sonst ewig aufeinander
/// 3. Das alte Gerät schickt zuerst das Transfer-Geheimnis als Byte-Nachricht
/// 4. Danach die verschlüsselte Datei
/// 5. Das neue Gerät entschlüsselt und **ersetzt** seinen Stand
///
/// **Das Geheimnis geht über dieselbe Leitung wie die Datei.** Das klingt zunächst falsch, ist
/// hier aber richtig: Der Schutz kommt nicht daraus, dass die Leitung geheim wäre, sondern
/// daraus, dass die **Datei ohne das Geheimnis wertlos** ist — und das Geheimnis existiert nur
/// für diesen einen Umzug, wird nie gespeichert und ist danach nutzlos. Wer die Datei später
/// irgendwo findet, hat verschlüsselten Müll. Ein Angreifer, der schon im selben WLAN sitzt und
/// beide Nutzlasten mitschneidet, hätte den Stand ohnehin über den Team-Schlüssel.
@MainActor
final class HandywechselNearby: ObservableObject {

    enum Zustand: Equatable {
        case aus
        /// Das Backup wird gepackt, bevor der Funk überhaupt startet — seit dem Off-Main-Fix ein
        /// eigener, sichtbarer Zwischenschritt statt eines stillen Wartens auf `.aus` (siehe
        /// `sende()`).
        case paketWirdErstellt
        /// Läuft und sucht die Gegenseite.
        case sucht(NearbyDienst.BackupRolle)
        case uebertraegt
        case fertig(String)
        case fehler(String)
    }

    @Published private(set) var zustand: Zustand = .aus
    @Published private(set) var protokoll: [String] = []

    private weak var model: AppModel?

    private var manager: ConnectionManager?
    private var werber: Advertiser?
    private var sucher: Discoverer?

    private var rolle: NearbyDienst.BackupRolle?
    private var verbunden: Set<EndpointID> = []

    /// Sender: selbst erzeugt. Empfänger: über Funk bekommen. Nie auf der Platte.
    private var transferGeheimnis: String?
    /// Sender: die fertige, verschlüsselte Datei. Wird nach dem Senden gelöscht.
    private var backupDatei: URL?
    private var eingehende: [PayloadID: URL] = [:]
    private var abbruchUhr: Task<Void, Never>?

    /// So lange wird gesucht, bevor abgebrochen wird. Grosszügig, weil beim Umzug niemand
    /// nebenher etwas anderes tut — aber nicht endlos, sonst funkt ein vergessener Bildschirm
    /// den ganzen Nachmittag.
    private static let geduldSekunden: UInt64 = 120

    var laeuft: Bool {
        if case .aus = zustand { return false }
        if case .fertig = zustand { return false }
        if case .fehler = zustand { return false }
        return true
    }

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Die beiden Seiten

    /// Das **alte** Gerät. Packt sofort das Backup — vor dem Funk, damit ein Fehler beim Packen
    /// auffällt, solange noch niemand wartet.
    func sende() async {
        guard !laeuft else { return }
        guard let model, model.istEingerichtet else {
            zustand = .fehler("Auf diesem Gerät ist nichts eingerichtet, was umziehen könnte.")
            return
        }
        zustand = .paketWirdErstellt
        guard let paket = await model.erzeugeHandywechselBackup() else {
            // stop() kann waehrend des Packens schon wieder auf .aus gestellt haben - dann nicht
            // nachtraeglich einen Fehler ueber einen abgebrochenen Versuch zeigen.
            if case .paketWirdErstellt = zustand {
                zustand = .fehler("Das Backup liess sich nicht packen.")
            }
            return
        }
        // Dasselbe hier: Wurde inzwischen abgebrochen, nicht mehr funken.
        guard case .paketWirdErstellt = zustand else { return }
        backupDatei = paket.datei
        transferGeheimnis = paket.geheimnis
        melde("Backup gepackt: \(model.state.posters.count) Plakate.")
        starte(als: .senden)
    }

    /// Das **neue** Gerät. Wartet auf das alte.
    func empfange() {
        guard !laeuft else { return }
        transferGeheimnis = nil
        melde("Warte auf das alte Gerät.")
        starte(als: .empfangen)
    }

    private func starte(als rolle: NearbyDienst.BackupRolle) {
        let manager = ConnectionManager(serviceID: NearbyDienst.backupKennung, strategy: .cluster)
        manager.delegate = self
        let werber = Advertiser(connectionManager: manager)
        werber.delegate = self
        let sucher = Discoverer(connectionManager: manager)
        sucher.delegate = self
        self.manager = manager
        self.werber = werber
        self.sucher = sucher
        self.rolle = rolle
        zustand = .sucht(rolle)

        let name = Data(rolle.endpunktName(zeit: Date.nowMillis).utf8)
        werber.startAdvertising(using: name) { fehler in
            guard let fehler else { return }
            Task { @MainActor [weak self] in
                self?.brichAb("Sichtbarkeit fehlgeschlagen: \(NearbyFehlertext.fuer(fehler))")
            }
        }
        sucher.startDiscovery { fehler in
            guard let fehler else { return }
            Task { @MainActor [weak self] in
                self?.brichAb("Suche fehlgeschlagen: \(NearbyFehlertext.fuer(fehler))")
            }
        }

        abbruchUhr = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.geduldSekunden * 1_000_000_000)
            guard !Task.isCancelled, let self, self.laeuft, self.verbunden.isEmpty else { return }
            self.brichAb(
                "Kein Gerät gefunden. Beide Telefone müssen im selben WLAN sein, und auf dem "
                + "anderen muss die Gegenseite offen sein."
            )
        }
    }

    func stop() {
        abbruchUhr?.cancel()
        abbruchUhr = nil
        werber?.stopAdvertising()
        sucher?.stopDiscovery()
        verbunden.forEach { manager?.disconnect(from: $0) }
        werber = nil
        sucher = nil
        manager = nil
        rolle = nil
        verbunden.removeAll()
        eingehende.removeAll()
        raeumeAuf()
        if laeuft { zustand = .aus }
    }

    /// Datei und Geheimnis verschwinden zusammen. Ein Backup ohne sein Geheimnis ist nutzlos,
    /// eines **mit** dem Geheimnis im Speicher wäre der Team-Schlüssel im Klartext.
    private func raeumeAuf() {
        if let datei = backupDatei { try? FileManager.default.removeItem(at: datei) }
        backupDatei = nil
        transferGeheimnis = nil
    }

    /// Abbrechen und Ende benutzen beide denselben Weg: erst alles abbauen, DANN den Zustand
    /// setzen. Andersherum überschriebe `stop()` die Meldung wieder mit `.aus`, und auf dem
    /// Bildschirm stünde nach einem Fehlschlag nichts weiter als „aus".
    private func brichAb(_ text: String) {
        melde(text)
        stop()
        zustand = .fehler(text)
    }

    private func fertig(_ text: String) {
        melde(text)
        stop()
        zustand = .fertig(text)
    }

    private func melde(_ text: String) {
        protokoll.append(text)
        Protokoll.geteilt.schreibe("Handywechsel: \(text)")
        if protokoll.count > 60 { protokoll.removeFirst(protokoll.count - 60) }
    }

    // MARK: - Senden

    private func schickeGeheimnisUndDatei(an endpunkt: EndpointID) {
        guard let manager, let geheimnis = transferGeheimnis, let datei = backupDatei else {
            brichAb("Backup-Schlüssel fehlt. Bitte den Handywechsel neu starten.")
            return
        }
        zustand = .uebertraegt

        // Erst der Schluessel als Byte-Nachricht, dann die Datei. Die Reihenfolge ist Teil des
        // Formats: Das neue Geraet braucht den Schluessel, bevor die Datei ankommt, sonst muss
        // es sie zwischenlagern und spaeter noch einmal anfassen.
        let nachricht = Data((NearbyDienst.transferSchluesselPraefix + geheimnis).utf8)
        _ = manager.send(nachricht, to: [endpunkt])
        melde("Schlüssel gesendet. Verschlüsseltes Backup folgt …")

        _ = manager.sendResource(
            at: datei, withName: datei.lastPathComponent, to: [endpunkt], id: PayloadID.unique()
        ) { fehler in
            guard let fehler else { return }
            Task { @MainActor [weak self] in
                self?.brichAb("Senden fehlgeschlagen: \(NearbyFehlertext.fuer(fehler))")
            }
        }
    }
}

// MARK: - Nearby-Rückrufe

extension HandywechselNearby: DiscovererDelegate {

    nonisolated func discoverer(
        _ discoverer: Discoverer, didFind endpointID: EndpointID, with context: Data
    ) {
        MainActor.assumeIsolated {
            guard let rolle else { return }
            // NUR UEBER KREUZ. Ohne diese Pruefung faenden sich zwei Sender gegenseitig, bauten
            // eine Verbindung auf und warteten beide auf ein Backup, das nie kommt.
            let name = String(decoding: context, as: UTF8.self)
            guard rolle.passtZu(endpunktName: name) else { return }
            melde("Gegenseite gefunden. Verbindung wird aufgebaut.")
            discoverer.requestConnection(to: endpointID, using: Data(rolle.verbindungsName.utf8))
        }
    }

    nonisolated func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) {
        MainActor.assumeIsolated { verbunden.remove(endpointID) }
    }
}

extension HandywechselNearby: AdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: Advertiser, didReceiveConnectionRequestFrom endpointID: EndpointID,
        with context: Data, connectionRequestHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            let name = String(decoding: context, as: UTF8.self)
            // Der Verbindungswunsch traegt die LANGE Form (SENDING/RECEIVING), nicht die kurze -
            // so macht es Android, siehe NearbyDienst.BackupRolle.verbindungsName. Geprueft wird
            // deshalb nur das Praefix; die Rollenpruefung ist beim Finden schon passiert.
            let passt = name.hasPrefix(NearbyDienst.backupPraefix)
            if passt { melde("Anfrage vom anderen Gerät.") }
            connectionRequestHandler(passt)
        }
    }
}

extension HandywechselNearby: ConnectionManagerDelegate {

    /// Beim Umzug stehen beide Telefone nebeneinander — trotzdem keine Rückfrage nach dem
    /// Zahlencode. Sie brächte nichts: Ohne das Transfer-Geheimnis, das gleich darauf über
    /// dieselbe Verbindung kommt, ist die Datei nicht zu öffnen.
    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceive verificationCode: String,
        from endpointID: EndpointID, verificationHandler: @escaping (Bool) -> Void
    ) {
        verificationHandler(true)
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didChangeTo state: ConnectionState,
        for endpointID: EndpointID
    ) {
        MainActor.assumeIsolated {
            switch state {
            case .connected:
                abbruchUhr?.cancel()
                abbruchUhr = nil
                verbunden.insert(endpointID)
                melde("Verbunden.")
                if rolle == .senden { schickeGeheimnisUndDatei(an: endpointID) }
            case .rejected, .disconnected:
                verbunden.remove(endpointID)
            case .connecting:
                break
            }
        }
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID,
        from endpointID: EndpointID
    ) {
        MainActor.assumeIsolated {
            guard rolle == .empfangen else { return }
            let roh = String(decoding: data, as: UTF8.self)
            guard roh.hasPrefix(NearbyDienst.transferSchluesselPraefix) else { return }
            let geheimnis = String(roh.dropFirst(NearbyDienst.transferSchluesselPraefix.count))
            guard !geheimnis.isEmpty else { return }
            transferGeheimnis = geheimnis
            zustand = .uebertraegt
            melde("Schlüssel empfangen. Warte auf das Backup …")
        }
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager,
        didStartReceivingResourceWithID payloadID: PayloadID, from endpointID: EndpointID,
        at localURL: URL, withName name: String, cancellationToken token: CancellationToken
    ) {
        MainActor.assumeIsolated {
            // Ohne Schluessel waere die Datei ohnehin nicht zu oeffnen - aber beliebig gross
            // machen liesse sie sich schon.
            guard rolle == .empfangen, transferGeheimnis != nil else {
                token.cancel()
                return
            }
            eingehende[payloadID] = localURL
            melde("Backup kommt herein …")
        }
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceive stream: InputStream,
        withID payloadID: PayloadID, from endpointID: EndpointID,
        cancellationToken token: CancellationToken
    ) {
        token.cancel()
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
        from endpointID: EndpointID, forPayload payloadID: PayloadID
    ) {
        MainActor.assumeIsolated {
            switch update {
            case .success:
                if rolle == .senden, backupDatei != nil {
                    // Das alte Geraet ist fertig, sobald die Datei drueben ist. Ob der Umzug
                    // dort GELINGT, sagt nur das neue Geraet - deshalb der vorsichtige Text.
                    fertig("Backup übertragen. Prüfe jetzt auf dem neuen Gerät, ob alles da ist.")
                }
                if rolle == .empfangen, let url = eingehende.removeValue(forKey: payloadID),
                   let geheimnis = transferGeheimnis {
                    melde("Backup vollständig. Wird übernommen …")
                    model?.uebernimmHandywechselBackup(von: url, geheimnis: geheimnis)
                    let anzahl = model?.state.posters.count ?? 0
                    fertig("Umzug abgeschlossen: \(anzahl) Plakate.")
                }
            case .failure, .canceled:
                eingehende.removeValue(forKey: payloadID)
                brichAb("Übertragung abgebrochen.")
            case .progress:
                break
            }
        }
    }
}
