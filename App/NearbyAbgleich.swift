import Foundation
import NearbyConnections
import PlakatKompassCore

/// Der Funk-Abgleich mit Android — dieselbe Schnittstelle, dieselbe Dienstkennung, derselbe
/// Handschlag wie `sync/NearbySyncManager.kt`.
///
/// **Was hier neu ist:** Google liefert Nearby Connections seit 2023 auch als Swift-Paket
/// (`github.com/google/nearby`, Produkt `NearbyConnections`). Die Behauptung im README, es gebe
/// auf iOS keinen Client für dieses Protokoll, war überholt; sie ist mit diesem Stand berichtigt.
///
/// **Was es nicht kann, und das ist die entscheidende Einschränkung:** Auf iOS trägt von allen
/// Funkwegen nur das **WLAN**. Bluetooth, Wi-Fi Direct und AWDL helfen zwischen Android und iPhone
/// nicht — AWDL ist Apples eigener Weg und spricht nur mit Apple-Geräten. Beide Geräte müssen also
/// im **selben Netz** hängen; der Hotspot eines der beiden Telefone reicht dafür. Auf freiem Feld
/// ohne Netz und ohne Hotspot finden sie sich nicht. Zwischen zwei Android-Geräten gilt das nicht,
/// dort bleibt der volle Funkweg.
///
/// **Nebenläufigkeit:** [ConnectionManager] liefert seine Rückrufe auf der Warteschlange, die ihm
/// im `init` mitgegeben wird — hier `.main`. Die Delegatmethoden sind deshalb `nonisolated` und
/// betreten den Hauptakteur mit `assumeIsolated`: kein Sprung, nur die Aussage an den Übersetzer,
/// dass wir bereits dort sind. Die Abschluss-Rückrufe von `startAdvertising` und Freunden kommen
/// dagegen **nicht** garantiert auf dem Hauptfaden; die gehen über `Task { @MainActor in … }`.
@MainActor
final class NearbyAbgleich: ObservableObject {

    @Published private(set) var laeuft = false
    @Published private(set) var protokoll: [String] = []
    /// Wie viele Teamgeräte den Handschlag bestanden haben — die Zahl für die Oberfläche.
    @Published private(set) var gepruefteGeraete = 0
    /// Es läuft, aber nach [stilleSekunden] hat sich kein einziges Gerät gemeldet.
    ///
    /// Der einzige Weg, das verweigerte lokale Netzwerk zu bemerken: iOS bietet **keine**
    /// Abfrage an, ob die Erlaubnis erteilt wurde. Wer sie ablehnt, bekommt eine Suche, die
    /// fehlerfrei läuft und nie etwas findet — nicht von „niemand in der Nähe" zu unterscheiden.
    /// Deshalb kein Schluss auf die Ursache, sondern der Hinweis auf beide möglichen.
    @Published private(set) var nichtsGefunden = false

    /// Ein eigenes Paket auf dem Weg zu einem Gerät.
    private struct Sendung {
        let endpunkt: EndpointID
        let datei: URL
        /// Der Stand, der darin steckt. Wird erst nach **bestätigter** Übertragung gemerkt.
        let stand: LocalTeamState
    }

    private weak var model: AppModel?

    private var manager: ConnectionManager?
    private var werber: Advertiser?
    private var sucher: Discoverer?

    /// Alle bestehenden Verbindungen, geprüft oder nicht — für ein sauberes [stop].
    private var verbunden: Set<EndpointID> = []
    /// Gestellte, noch unbeantwortete Fragen des Handschlags: Endpunkt → Nonce.
    private var offeneFragen: [EndpointID: String] = [:]
    /// Endpunkte, deren Antwort gestimmt hat. Erst danach nehmen wir Dateien von ihnen an.
    private var geprueft: Set<EndpointID> = []
    /// Endpunkte, die uns ihrerseits bestätigt haben. Erst danach senden wir.
    private var bestaetigtUns: Set<EndpointID> = []
    /// Zuletzt bestätigt gesendeter Stand je Endpunkt — verhindert das Hin und Her.
    private var letzterStand: [EndpointID: LocalTeamState] = [:]
    /// Endpunkt → Geräte-ID, aus `senderDeviceId` im Handschlag. Erlaubt [verstosseGeraet], gezielt
    /// **ein** Gerät zu trennen statt mit [stop] alle Verbindungen zu kappen.
    private var endpunktGeraeteId: [EndpointID: String] = [:]
    private var eigeneSendungen: [PayloadID: Sendung] = [:]
    /// Hereinkommende Pakete: Sendung → Ort auf der Platte. Vollständig erst bei `.success`.
    private var eingehendeDateien: [PayloadID: URL] = [:]
    private var stilleUhr: Task<Void, Never>?

    /// So lange darf es dauern, bis sich das erste Gerät zeigt, bevor der Hinweis kommt.
    ///
    /// Grosszügig bemessen: Über WLAN vergehen zwischen „Suche läuft" und dem ersten Fund
    /// regelmässig zehn Sekunden und mehr. Ein zu früher Hinweis wäre schlimmer als keiner —
    /// er schickte Leute in die Einstellungen, während der Abgleich gerade zustande kommt.
    private static let stilleSekunden: UInt64 = 25

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - An und aus

    func start() {
        guard !laeuft else { return }
        guard let model, AccessPolicy.canSync(model.state) else {
            melde("Ohne Team-Schlüssel gibt es nichts abzugleichen.")
            return
        }

        let manager = ConnectionManager(serviceID: NearbyDienst.kennung, strategy: .cluster)
        manager.delegate = self
        let werber = Advertiser(connectionManager: manager)
        werber.delegate = self
        let sucher = Discoverer(connectionManager: manager)
        sucher.delegate = self
        self.manager = manager
        self.werber = werber
        self.sucher = sucher
        laeuft = true

        let name = Data(endpunktName(model.state).utf8)
        werber.startAdvertising(using: name) { fehler in
            let text = fehler.map { "Sichtbarkeit fehlgeschlagen: \(NearbyFehlertext.fuer($0))" }
                ?? "Dieses iPhone ist für Teamgeräte sichtbar."
            Task { @MainActor [weak self] in self?.melde(text) }
        }
        sucher.startDiscovery { fehler in
            let text = fehler.map { "Suche fehlgeschlagen: \(NearbyFehlertext.fuer($0))" }
                ?? "Suche nach Teamgeräten läuft."
            Task { @MainActor [weak self] in self?.melde(text) }
        }

        nichtsGefunden = false
        stilleUhr = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stilleSekunden * 1_000_000_000)
            guard !Task.isCancelled, let self, self.laeuft, self.verbunden.isEmpty else { return }
            self.nichtsGefunden = true
        }
    }

    func stop() {
        guard laeuft else { return }
        stilleUhr?.cancel()
        stilleUhr = nil
        nichtsGefunden = false
        werber?.stopAdvertising()
        sucher?.stopDiscovery()
        verbunden.forEach { manager?.disconnect(from: $0) }
        Array(eigeneSendungen.keys).forEach(raeumeSendungAuf)

        werber = nil
        sucher = nil
        manager = nil
        verbunden.removeAll()
        offeneFragen.removeAll()
        geprueft.removeAll()
        bestaetigtUns.removeAll()
        letzterStand.removeAll()
        endpunktGeraeteId.removeAll()
        eingehendeDateien.removeAll()
        gepruefteGeraete = 0
        laeuft = false
        melde("Funk-Abgleich gestoppt.")
    }

    /// Wird nach jeder lokalen Änderung aufgerufen, damit geprüfte Geräte sie sofort bekommen und
    /// nicht erst beim nächsten Verbindungsaufbau.
    func zustandGeaendert() {
        guard laeuft else { return }
        geprueft.intersection(bestaetigtUns).forEach(sendeStand)
    }

    private func endpunktName(_ stand: LocalTeamState) -> String {
        "\(NearbyDienst.namensPraefix)\(stand.deviceName)|\(stand.deviceId.prefix(8))"
    }

    /// Es ist ein Gerät aufgetaucht — damit ist die Frage nach dem lokalen Netz beantwortet.
    ///
    /// Schon der **Fund** genügt, nicht erst die Verbindung: Wer bis hierher kommt, hat die
    /// Erlaubnis und hängt im richtigen Netz. Scheitert es danach, liegt es am Team-Schlüssel
    /// oder am anderen Gerät — dann wäre ein Hinweis auf die Einstellungen eine falsche Fährte.
    private func netzLebt() {
        stilleUhr?.cancel()
        stilleUhr = nil
        nichtsGefunden = false
    }

    private func melde(_ text: String) {
        protokoll.append(text)
        // Zusaetzlich in die Datei, die den Neustart ueberlebt - sonst ist beim
        // Fehlerbericht am naechsten Tag nichts mehr da.
        Protokoll.geteilt.schreibe("Abgleich: \(text)")
        // Ein Protokoll, das nie vergisst, wächst über eine Kampagne hinweg ins Unangenehme.
        if protokoll.count > 100 { protokoll.removeFirst(protokoll.count - 100) }
    }

    // MARK: - Handschlag

    /// Wortgleich mit `NearbySyncManager`: `AUTH_CHALLENGE` → `AUTH_RESPONSE` → `AUTH_OK`.
    ///
    /// Der Nachweis ist `HMAC-SHA256(teamSecret, nonce)`. Das Geheimnis selbst geht nie über die
    /// Leitung, und ein mitgeschnittener Nachweis nützt beim nächsten Mal nichts, weil der Nonce
    /// jedes Mal neu ist.
    private func sendeFrage(an endpunkt: EndpointID) {
        guard let stand = model?.state, let teamId = stand.teamId else { return }
        let nonce = Crypto.randomNonceHex()
        offeneFragen[endpunkt] = nonce
        sende([
            "kind": "AUTH_CHALLENGE", "teamId": teamId, "nonce": nonce,
            "senderDeviceId": stand.deviceId, "senderName": stand.deviceName
        ], an: endpunkt)
    }

    private func sende(_ nachricht: [String: String], an endpunkt: EndpointID) {
        guard let manager, let daten = try? JSONSerialization.data(withJSONObject: nachricht) else {
            return
        }
        _ = manager.send(daten, to: [endpunkt])
    }

    private func behandle(_ nachricht: [String: String], von endpunkt: EndpointID) {
        // Frisch aus dem Modell lesen, damit ein zwischenzeitlich erneuerter Team-Schlüssel greift.
        guard let stand = model?.state, let teamId = stand.teamId else { return }
        guard nachricht["teamId"] == teamId else {
            manager?.disconnect(from: endpunkt)
            melde("Fremdes Team abgelehnt.")
            return
        }

        if let geraeteId = nachricht["senderDeviceId"], !geraeteId.isEmpty {
            endpunktGeraeteId[endpunkt] = geraeteId
        }

        switch nachricht["kind"] {
        case "AUTH_CHALLENGE":
            guard let nonce = nachricht["nonce"], !nonce.isEmpty,
                  let geheimnis = stand.teamSecret else { return }
            sende([
                "kind": "AUTH_RESPONSE", "teamId": teamId, "nonce": nonce,
                "proof": Crypto.hmacSha256Hex(secret: geheimnis, message: nonce),
                "senderDeviceId": stand.deviceId, "senderName": stand.deviceName
            ], an: endpunkt)

        case "AUTH_RESPONSE":
            guard let nonce = offeneFragen.removeValue(forKey: endpunkt),
                  let geheimnis = stand.teamSecret else { return }
            let erwartet = Crypto.hmacSha256Hex(secret: geheimnis, message: nonce)
            guard nachricht["nonce"] == nonce,
                  Crypto.constantTimeEquals(nachricht["proof"] ?? "", erwartet)
            else {
                manager?.disconnect(from: endpunkt)
                melde("Gerät abgelehnt: Team-Schlüssel passt nicht.")
                return
            }
            geprueft.insert(endpunkt)
            gepruefteGeraete = geprueft.count
            sende([
                "kind": "AUTH_OK", "teamId": teamId,
                "senderDeviceId": stand.deviceId, "senderName": stand.deviceName
            ], an: endpunkt)
            melde("Teamgerät geprüft. Abgleich kann laufen.")
            sendeStand(an: endpunkt)

        case "AUTH_OK":
            bestaetigtUns.insert(endpunkt)
            sendeStand(an: endpunkt)

        default:
            break
        }
    }

    // MARK: - Senden

    private func sendeStand(an endpunkt: EndpointID) {
        guard let manager, let model,
              geprueft.contains(endpunkt), bestaetigtUns.contains(endpunkt) else { return }
        // Gleicher Inhalt wie zuletzt: nichts tun. Ohne diese Prüfung schaukeln sich zwei Geräte
        // gegenseitig hoch — jedes empfangene Paket ändert den Stand und löste ein neues aus.
        guard letzterStand[endpunkt] != model.state, let datei = model.erzeugeSyncPaket() else {
            return
        }

        let sendung = PayloadID.unique()
        eigeneSendungen[sendung] = Sendung(endpunkt: endpunkt, datei: datei, stand: model.state)
        _ = manager.sendResource(
            at: datei, withName: datei.lastPathComponent, to: [endpunkt], id: sendung
        ) { fehler in
            guard let fehler else { return }
            Task { @MainActor [weak self] in
                // Nicht abgeschickt: Stand **nicht** als gesendet merken, damit es erneut
                // versucht wird, statt denselben Stand für immer zu überspringen.
                self?.raeumeSendungAuf(sendung)
                self?.melde("Senden fehlgeschlagen: \(NearbyFehlertext.fuer(fehler))")
            }
        }
    }

    private func raeumeSendungAuf(_ sendung: PayloadID) {
        guard let eintrag = eigeneSendungen.removeValue(forKey: sendung) else { return }
        try? FileManager.default.removeItem(at: eintrag.datei)
    }

    private func vergiss(_ endpunkt: EndpointID) {
        verbunden.remove(endpunkt)
        offeneFragen.removeValue(forKey: endpunkt)
        geprueft.remove(endpunkt)
        bestaetigtUns.remove(endpunkt)
        letzterStand.removeValue(forKey: endpunkt)
        endpunktGeraeteId.removeValue(forKey: endpunkt)
        gepruefteGeraete = geprueft.count
        eigeneSendungen
            .filter { $0.value.endpunkt == endpunkt }
            .map(\.key)
            .forEach(raeumeSendungAuf)
    }

    /// Trennt sofort die laufende Verbindung zu genau **einem** Gerät — z. B. wenn die Teamleitung
    /// dieses Gerät gerade gesperrt hat. Gegenstück zu `NearbySyncManager.disconnectDevice`.
    ///
    /// Ohne das hier bliebe ein gesperrtes Gerät bis zum natürlichen Verbindungsabbruch weiter im
    /// Live-Abgleich — Minuten, in denen es noch Sync-Pakete empfängt, obwohl sein Zugang gerade
    /// entzogen wurde. [stop] wäre die falsche Antwort: Es kappte auch alle anderen, noch
    /// berechtigten Teamgeräte.
    func verstosseGeraet(deviceId: String) {
        guard laeuft else { return }
        let betroffen = endpunktGeraeteId.filter { $0.value == deviceId }.keys
        guard !betroffen.isEmpty else { return }
        betroffen.forEach { endpunkt in
            manager?.disconnect(from: endpunkt)
            vergiss(endpunkt)
        }
        melde("Gesperrtes Gerät getrennt.")
    }
}

// MARK: - Nearby-Rückrufe

extension NearbyAbgleich: DiscovererDelegate {

    nonisolated func discoverer(
        _ discoverer: Discoverer, didFind endpointID: EndpointID, with context: Data
    ) {
        MainActor.assumeIsolated {
            // Eine fremde App mit derselben Dienstkennung gibt es zwar nicht, aber die Prüfung
            // kostet nichts und steht auf Android genauso da.
            guard String(decoding: context, as: UTF8.self).hasPrefix(NearbyDienst.namensPraefix),
                  let stand = model?.state else { return }
            netzLebt()
            melde("PlakatRadar-Gerät gefunden. Verbindung wird aufgebaut.")
            discoverer.requestConnection(to: endpointID, using: Data(endpunktName(stand).utf8))
        }
    }

    nonisolated func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) {
        MainActor.assumeIsolated { vergiss(endpointID) }
    }
}

extension NearbyAbgleich: AdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: Advertiser, didReceiveConnectionRequestFrom endpointID: EndpointID,
        with context: Data, connectionRequestHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            let passt = String(decoding: context, as: UTF8.self)
                .hasPrefix(NearbyDienst.namensPraefix)
            // Auch der umgekehrte Weg zaehlt: Wer uns anfragt, hat uns gefunden.
            if passt { netzLebt() }
            melde(passt ? "Anfrage von einem PlakatRadar-Gerät." : "Fremdes Gerät abgelehnt.")
            connectionRequestHandler(passt)
        }
    }
}

extension NearbyAbgleich: ConnectionManagerDelegate {

    /// Der Zahlencode, den Nearby beiden Seiten zeigt, damit ein Mensch ihn vergleicht.
    ///
    /// Wir bestätigen ihn ohne Rückfrage — und das ist kein Nachlassen: Der Team-Schlüssel leistet
    /// dasselbe, nur ohne dass zwei Leute nebeneinanderstehen und Ziffern vorlesen müssen. Wer ihn
    /// nicht hat, scheitert eine Stufe später am Handschlag. Android macht es genauso.
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
                verbunden.insert(endpointID)
                melde("Verbunden. Team-Zugang wird geprüft.")
                sendeFrage(an: endpointID)
            case .rejected, .disconnected:
                vergiss(endpointID)
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
            guard let roh = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            behandle(roh.compactMapValues { $0 as? String }, von: endpointID)
        }
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager,
        didStartReceivingResourceWithID payloadID: PayloadID, from endpointID: EndpointID,
        at localURL: URL, withName name: String, cancellationToken token: CancellationToken
    ) {
        MainActor.assumeIsolated {
            // Ein Paket von einem ungeprüften Gerät wird gar nicht erst angenommen. Entschlüsseln
            // liesse es sich ohnehin nicht — aber beliebig gross machen schon.
            guard geprueft.contains(endpointID), bestaetigtUns.contains(endpointID) else {
                token.cancel()
                connectionManager.disconnect(from: endpointID)
                melde("Ungeprüftes Sync-Paket abgelehnt.")
                return
            }
            eingehendeDateien[payloadID] = localURL
            melde("Sync-Paket kommt herein …")
        }
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceive stream: InputStream,
        withID payloadID: PayloadID, from endpointID: EndpointID,
        cancellationToken token: CancellationToken
    ) {
        // Wir senden keine Ströme, also nehmen wir auch keine an.
        token.cancel()
    }

    nonisolated func connectionManager(
        _ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
        from endpointID: EndpointID, forPayload payloadID: PayloadID
    ) {
        MainActor.assumeIsolated {
            switch update {
            case .success:
                // Erst jetzt gilt der Stand als angekommen. Vorher gemerkt, hätte ein
                // abgebrochener Versand denselben Stand für immer übersprungen.
                if let eintrag = eigeneSendungen.removeValue(forKey: payloadID) {
                    letzterStand[eintrag.endpunkt] = eintrag.stand
                    try? FileManager.default.removeItem(at: eintrag.datei)
                    melde("Sync-Daten an Teamgerät gesendet.")
                }
                if let url = eingehendeDateien.removeValue(forKey: payloadID) {
                    melde("Sync-Paket empfangen. Zusammenführen läuft …")
                    model?.importiereSyncPaket(von: url, quelle: "Funk-Abgleich")
                }
            case .failure, .canceled:
                raeumeSendungAuf(payloadID)
                eingehendeDateien.removeValue(forKey: payloadID)
                melde("Übertragung abgebrochen.")
            case .progress:
                break
            }
        }
    }
}
