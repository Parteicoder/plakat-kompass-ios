import CryptoKit
import Foundation
import ZIPFoundation

/// Vollbackup für den Handywechsel — das Gegenstück zu `data/DeviceBackupCodec.kt`.
///
/// **Unterschied zum Sync-Paket, und er ist der ganze Punkt:** Ein Sync-Paket enthält den
/// *geteilten* Teamstand und ist mit dem Team-Schlüssel verschlüsselt, den ohnehin jedes
/// Teamgerät hat. Ein Handywechsel-Backup enthält den **kompletten Gerätestand samt
/// Teamzugang** — wer es öffnen kann, ist das Team. Deshalb hängt es *nicht* am
/// Team-Schlüssel, sondern an einem **einmaligen Transfer-Schlüssel**, der nur für diesen
/// einen Umzug gilt und getrennt von der Datei übergeben wird.
///
/// Format, byte-gleich mit Android:
///
///     MAGIC ("PRBACKUP2\n", 10 Byte) | IV (12 Byte) | AES-256-GCM(ZIP) | Tag (16 Byte)
///
/// - Schlüssel: `SHA-256("PlakatRadarDeviceBackup|v2|" + transferSecret)`
/// - Zusatzdaten (AAD): das MAGIC. Damit lässt sich der Kopf nicht unbemerkt austauschen.
/// - Inhalt des ZIP: `device_state.json` und `photos/<name>`
///
/// **Warum ein eigener Codec und nicht `SyncBundleCodec` mit anderem Schlüssel:** Der Inhalt
/// ist ein anderer. Ein Sync-Paket trägt einen `SyncSnapshot` — den *teilbaren* Ausschnitt.
/// Ein Backup trägt den `LocalTeamState` mitsamt `teamSecret` und Rolle. Beides in ein Format
/// zu pressen hiesse, den Team-Schlüssel versehentlich in jedes Sync-Paket zu schreiben.
public enum DeviceBackupCodec {

    static let magic = Data("PRBACKUP2\n".utf8)   // 10 Byte
    static let schemaVersion = 2
    static let ivBytes = 12
    static let tagBytes = 16

    static let maxStateBytes = 2 * 1024 * 1024
    static let minValidPhotoBytes = 1024
    static let maxSinglePhotoBytes = 8 * 1024 * 1024
    static let maxTotalPhotoBytes = 250 * 1024 * 1024
    static let maxBackupBytes = 300 * 1024 * 1024

    /// Der Schlüssel wird aus dem Transfer-Geheimnis abgeleitet, nicht aus dem Team-Schlüssel.
    ///
    /// Der Zusatz `PlakatRadarDeviceBackup|v2|` ist keine Zierde: Ohne ihn ergäbe dasselbe
    /// Geheimnis in zwei verschiedenen Zusammenhängen denselben Schlüssel. Mit ihm ist ein
    /// Backup-Schlüssel niemals zufällig auch ein Paket-Schlüssel.
    public static func transferKey(_ transferSecret: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("PlakatRadarDeviceBackup|v2|\(transferSecret)".utf8)))
    }

    /// Ein frisches Transfer-Geheimnis. Gilt für **einen** Umzug und wird nie gespeichert.
    public static func neuesTransferGeheimnis() -> String {
        Crypto.randomNonceHex()
    }

    // MARK: - Schreiben

    public static func createBackup(
        state: LocalTeamState,
        transferSecret: String,
        photoURL: (String) -> URL?
    ) throws -> Data {
        guard let archive = Archive(accessMode: .create) else {
            throw SyncError.ungueltigesPaket("ZIP liess sich nicht anlegen.")
        }

        let stateData = try stateToJson(state)
        guard stateData.count <= maxStateBytes else {
            throw SyncError.zuGross("Der Gerätestand im Backup")
        }
        try archive.addEntry(
            with: "device_state.json",
            type: .file,
            uncompressedSize: Int64(stateData.count),
            provider: { position, size in
                stateData.subdata(in: Int(position)..<Int(position) + size)
            }
        )

        var gesamt = 0
        var schonDrin = Set<String>()
        for name in state.posters.compactMap(\.localPhotoFileName) where !schonDrin.contains(name) {
            schonDrin.insert(name)
            guard SyncBundleCodec.isSafeFileName(name) else {
                throw SyncError.ungueltigesPaket("Unsicherer Fotodateiname: \(name)")
            }
            // Ein fehlendes Foto laesst das Backup NICHT scheitern - anders als beim
            // Sync-Paket. Beim Umzug zaehlt, dass die Plakate ankommen; ein einzelnes
            // verlorenes Bild darf nicht den ganzen Handywechsel verhindern. Android
            // ueberspringt es an dieser Stelle genauso.
            guard let url = photoURL(name), let foto = try? Data(contentsOf: url) else { continue }
            guard foto.count >= minValidPhotoBytes else {
                throw SyncError.ungueltigesPaket("Ein Foto im Backup ist leer oder beschädigt: \(name)")
            }
            guard foto.count <= maxSinglePhotoBytes else {
                throw SyncError.zuGross("Ein Foto im Backup")
            }
            gesamt += foto.count
            guard gesamt <= maxTotalPhotoBytes else {
                throw SyncError.zuGross("Die Fotos im Backup zusammen")
            }
            try archive.addEntry(
                with: "photos/\(name)",
                type: .file,
                uncompressedSize: Int64(foto.count),
                provider: { position, size in
                    foto.subdata(in: Int(position)..<Int(position) + size)
                }
            )
        }

        guard let zipData = archive.data else {
            throw SyncError.ungueltigesPaket("ZIP liess sich nicht abschliessen.")
        }

        let nonce = try AES.GCM.Nonce(data: zufall(ivBytes))
        let box = try AES.GCM.seal(
            zipData,
            using: transferKey(transferSecret),
            nonce: nonce,
            authenticating: magic
        )

        var out = Data()
        out.append(magic)
        out.append(Data(nonce))
        out.append(box.ciphertext)
        out.append(box.tag)
        guard out.count <= maxBackupBytes else { throw SyncError.zuGross("Das Handywechsel-Backup") }
        return out
    }

    // MARK: - Lesen

    public static func looksLikeBackup(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    /// Entschlüsselt, liest den Stand und schreibt die Fotos — **in dieser Reihenfolge**.
    ///
    /// Erst wenn `device_state.json` gelesen und für gültig befunden ist, geht ein einziges
    /// Byte auf die Platte. Wer das vertauscht, entpackt Dateien aus einem Paket, dessen
    /// Herkunft noch gar nicht feststeht.
    ///
    /// Anders als beim Sync-Import gibt es hier **keine Teamprüfung**: Ein Backup ist der
    /// eigene Stand, nicht der eines fremden Geräts. Den Platz der Prüfung nimmt der
    /// Transfer-Schlüssel ein — wer ihn nicht hat, kommt nicht bis hierher.
    public static func restoreBackup(
        _ data: Data,
        transferSecret: String,
        photoTargetURL: (String) -> URL
    ) throws -> LocalTeamState {
        guard data.count <= maxBackupBytes else { throw SyncError.zuGross("Das Handywechsel-Backup") }
        guard looksLikeBackup(data) else {
            throw SyncError.ungueltigesPaket("Kein PRBACKUP2-Paket.")
        }
        guard data.count > magic.count + ivBytes + tagBytes else {
            throw SyncError.ungueltigesPaket("Backup ist unvollständig.")
        }

        let iv = data.subdata(in: magic.count..<magic.count + ivBytes)
        let rest = data.subdata(in: magic.count + ivBytes..<data.count)
        let ciphertext = rest.subdata(in: 0..<rest.count - tagBytes)
        let tag = rest.subdata(in: rest.count - tagBytes..<rest.count)

        let zipData: Data
        do {
            zipData = try AES.GCM.open(
                AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag),
                using: transferKey(transferSecret),
                authenticating: magic
            )
        } catch {
            // Falscher Transfer-Schluessel oder veraendertes Paket - GCM unterscheidet das
            // nicht, und das ist Absicht.
            throw SyncError.fremdesTeam
        }

        guard let archive = Archive(data: zipData, accessMode: .read) else {
            throw SyncError.ungueltigesPaket("Inhalt ist kein ZIP.")
        }
        guard let eintrag = archive["device_state.json"] else {
            throw SyncError.ungueltigesPaket("device_state.json fehlt.")
        }
        guard eintrag.uncompressedSize <= maxStateBytes else {
            throw SyncError.zuGross("Der Gerätestand im Backup")
        }
        var stateBytes = Data()
        _ = try archive.extract(eintrag) { teil in stateBytes.append(teil) }
        let state = try stateFromJson(stateBytes)

        // Erst jetzt auf die Platte, und nur, was der Stand auch nennt.
        let erlaubt = Set(state.posters.compactMap(\.localPhotoFileName).filter(SyncBundleCodec.isSafeFileName))
        var gesamt = 0
        for entry in archive where entry.path.hasPrefix("photos/") && entry.type == .file {
            let name = String(entry.path.dropFirst("photos/".count))
            guard SyncBundleCodec.isSafeFileName(name), erlaubt.contains(name) else { continue }
            guard entry.uncompressedSize <= maxSinglePhotoBytes else {
                throw SyncError.zuGross("Ein Foto im Backup")
            }
            gesamt += Int(entry.uncompressedSize)
            guard gesamt <= maxTotalPhotoBytes else {
                throw SyncError.zuGross("Die Fotos im Backup zusammen")
            }
            var foto = Data()
            _ = try archive.extract(entry) { teil in foto.append(teil) }
            guard foto.count >= minValidPhotoBytes else {
                throw SyncError.ungueltigesPaket("Ein Foto im Backup ist leer oder beschädigt: \(name)")
            }
            try foto.write(to: photoTargetURL(name), options: .atomic)
        }

        return state
    }

    // MARK: - Der Stand als JSON

    /// Feldnamen und Reihenfolge wortgleich mit `stateToJson` auf Android.
    static func stateToJson(_ state: LocalTeamState) throws -> Data {
        let root: [String: Any] = [
            "format": "plakatradar-device-backup",
            "schemaVersion": schemaVersion,
            "deviceId": state.deviceId,
            "deviceName": state.deviceName,
            "role": state.role?.rawValue ?? "",
            "teamId": state.teamId ?? "",
            "teamName": state.teamName ?? "",
            "teamSecret": state.teamSecret ?? "",
            "devices": state.devices.map(TeamStateJson.deviceToJson),
            "deviceKeyring": state.deviceKeyring.map(TeamStateJson.deviceKeyRecordToJson),
            "posters": try state.posters.map(TeamStateJson.posterToJson),
            "deletedPosters": state.deletedPosters.map(TeamStateJson.tombstoneToJson),
            "events": state.events.map(TeamStateJson.eventToJson),
            "flyerTours": try state.flyerTours.map(TeamStateJson.flyerTourToJson),
            "createdAt": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func stateFromJson(_ data: Data) throws -> LocalTeamState {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.ungueltigesPaket("device_state.json ist kein Objekt.")
        }
        guard TeamStateJson.optString(root, "format") == "plakatradar-device-backup" else {
            throw SyncError.ungueltigesPaket("Das ist kein Handywechsel-Backup.")
        }
        let version = Int(TeamStateJson.optLong(root, "schemaVersion", Int64(schemaVersion)))
        guard version <= schemaVersion else { throw SyncError.neueresSchema }

        return LocalTeamState(
            deviceId: try TeamStateJson.requiredString(root, "deviceId"),
            deviceName: TeamStateJson.optString(root, "deviceName", "Dieses iPhone"),
            // Nicht ueber optEnum: Das verlangt einen Rueckfallwert, und "keine Rolle" ist
            // hier ein gueltiger Zustand - wer allein losgelegt hat, hat keine.
            role: MemberRole(rawValue: TeamStateJson.optString(root, "role")),
            teamId: leerAlsNil(TeamStateJson.optString(root, "teamId")),
            teamName: leerAlsNil(TeamStateJson.optString(root, "teamName")),
            teamSecret: leerAlsNil(TeamStateJson.optString(root, "teamSecret")),
            devices: try TeamStateJson.array(root, "devices").map(TeamStateJson.deviceFromJson),
            posters: try TeamStateJson.array(root, "posters").map(TeamStateJson.posterFromJson),
            deletedPosters: try TeamStateJson.array(root, "deletedPosters").map(TeamStateJson.tombstoneFromJson),
            events: try TeamStateJson.array(root, "events").map(TeamStateJson.eventFromJson),
            flyerTours: try TeamStateJson.array(root, "flyerTours").map(TeamStateJson.flyerTourFromJson),
            deviceKeyring: (try? TeamStateJson.array(root, "deviceKeyring").map(TeamStateJson.deviceKeyRecordFromJson)) ?? []
        )
    }

    private static func leerAlsNil(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    private static func zufall(_ anzahl: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: anzahl)
        guard SecRandomCopyBytes(kSecRandomDefault, anzahl, &bytes) == errSecSuccess else {
            throw SyncError.ungueltigesPaket("Zufallsquelle nicht verfügbar.")
        }
        return Data(bytes)
    }
}
