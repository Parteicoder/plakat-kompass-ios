import CryptoKit
import Foundation
import ZIPFoundation

/// Lesen und Schreiben von `PRSYNC2`-Paketen — das Gegenstück zu `sync/SyncBundleCodec.kt`.
///
/// Dies ist die einzige Stelle, an der iOS und Android sich wirklich berühren. Jedes Byte hier ist
/// Vertrag, nicht Geschmackssache. Die Beschreibung steht in der README des Repos.
public enum SyncBundleCodec {

    static let magic = Data("PRSYNC2\n".utf8)   // 8 Byte
    static let ivBytes = 12
    static let tagBytes = 16

    static let minValidPhotoBytes = 1024
    static let maxSinglePhotoBytes = 8 * 1024 * 1024
    static let maxTotalPhotoBytes = 250 * 1024 * 1024
    static let maxBundleBytes = 300 * 1024 * 1024

    /// Fotodateinamen dürfen keine Pfade vorgeben. Gegenstück zu `isSafeFileName`.
    static let safeFileName = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._-]{1,120}$")

    /// `.` und `..` bestehen den Zeichentest, sind aber keine Dateinamen, sondern Wegweiser.
    ///
    /// Android lässt sie ebenfalls durch den Namenstest und fängt sie eine Stufe später ab:
    /// `safePhotoTarget` löst den Pfad auf und besteht darauf, dass er unterhalb von `photos/`
    /// bleibt. Diese zweite Stufe gibt es hier nicht — `importVerifiedBundle` bekommt nur einen
    /// Bauplan für Ziel-URLs, nicht das Wurzelverzeichnis. Also muss der Namenstest allein tragen.
    ///
    /// Das kann er auch: Über dem Zeichenvorrat `[a-zA-Z0-9._-]` gibt es keinen Schrägstrich, und
    /// damit sind `.` und `..` die **einzigen** Zeichenketten, die aus dem Ordner herausführen.
    /// Wer die beiden ausschließt, hat alle erwischt.
    static let wegweiser: Set<String> = [".", ".."]

    public static func isSafeFileName(_ name: String) -> Bool {
        guard !wegweiser.contains(name) else { return false }
        let bereich = NSRange(name.startIndex..., in: name)
        return safeFileName.firstMatch(in: name, range: bereich) != nil
    }

    // MARK: - Schreiben

    /// Erzeugt ein Paket: `MAGIC | IV | AES-256-GCM(ZIP)`.
    ///
    /// - Parameter photoURL: liefert zu einem Dateinamen den Ort des Fotos auf der Platte.
    public static func createBundle(
        snapshot: SyncSnapshot,
        teamSecret: String,
        photoURL: (String) -> URL?
    ) throws -> Data {
        guard let archive = Archive(accessMode: .create) else {
            throw SyncError.ungueltigesPaket("ZIP liess sich nicht anlegen.")
        }

        let snapshotData = try TeamStateJson.snapshotToJson(snapshot)
        try archive.addEntry(
            with: "snapshot.json",
            type: .file,
            uncompressedSize: Int64(snapshotData.count),
            provider: { position, size in
                snapshotData.subdata(in: Int(position)..<Int(position) + size)
            }
        )

        var gesamt = 0
        var schonDrin = Set<String>()
        for name in snapshot.posters.compactMap(\.localPhotoFileName) where !schonDrin.contains(name) {
            schonDrin.insert(name)
            guard isSafeFileName(name) else {
                throw SyncError.ungueltigesPaket("Unsicherer Fotodateiname: \(name)")
            }
            guard let url = photoURL(name), let foto = try? Data(contentsOf: url) else {
                throw SyncError.ungueltigesPaket("Foto fehlt im Speicher: \(name)")
            }
            guard foto.count >= minValidPhotoBytes else {
                throw SyncError.ungueltigesPaket("Foto ist leer oder beschädigt: \(name)")
            }
            guard foto.count <= maxSinglePhotoBytes else {
                throw SyncError.zuGross("Ein Foto im Sync-Paket")
            }
            gesamt += foto.count
            guard gesamt <= maxTotalPhotoBytes else {
                throw SyncError.zuGross("Die Fotos im Sync-Paket zusammen")
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
            using: Crypto.payloadKey(teamSecret: teamSecret),
            nonce: nonce,
            authenticating: magic
        )

        // Reihenfolge wie in Java: Chiffrat, dann Tag. CryptoKit haelt beides getrennt,
        // Javas CipherOutputStream schreibt sie hintereinander.
        var out = Data()
        out.append(magic)
        out.append(Data(nonce))
        out.append(box.ciphertext)
        out.append(box.tag)
        return out
    }

    // MARK: - Lesen

    /// Prüft, ob eine Datei überhaupt ein Paket dieser App ist, ohne zu entschlüsseln.
    public static func looksLikeBundle(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    /// Entschlüsselt und gibt das enthaltene ZIP zurück.
    static func openBundle(_ data: Data, teamSecret: String) throws -> Data {
        guard data.count <= maxBundleBytes else { throw SyncError.zuGross("Das Sync-Paket") }
        guard looksLikeBundle(data) else {
            throw SyncError.ungueltigesPaket("Kein PRSYNC2-Paket.")
        }
        guard data.count > magic.count + ivBytes + tagBytes else {
            throw SyncError.ungueltigesPaket("Paket ist unvollständig.")
        }

        let iv = data.subdata(in: magic.count..<magic.count + ivBytes)
        let rest = data.subdata(in: magic.count + ivBytes..<data.count)
        let ciphertext = rest.subdata(in: 0..<rest.count - tagBytes)
        let tag = rest.subdata(in: rest.count - tagBytes..<rest.count)

        let box = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: iv),
            ciphertext: ciphertext,
            tag: tag
        )
        do {
            return try AES.GCM.open(
                box,
                using: Crypto.payloadKey(teamSecret: teamSecret),
                authenticating: magic
            )
        } catch {
            // Falscher Team-Schluessel oder veraendertes Paket - GCM unterscheidet das nicht,
            // und das ist Absicht.
            throw SyncError.fremdesTeam
        }
    }

    /// Der sichere Weg hinein. Die Reihenfolge ist Teil des Formats:
    ///
    /// 1. Größe prüfen  2. entschlüsseln  3. **nur** `snapshot.json` lesen
    /// 4. Team prüfen  5. **erst danach** Fotos entpacken, und nur referenzierte
    ///
    /// Wer 4 und 5 vertauscht, schreibt Dateien aus einem Paket auf die Platte, dessen Herkunft
    /// noch gar nicht feststeht.
    public static func importVerifiedBundle(
        data: Data,
        local: LocalTeamState,
        photoTargetURL: (String) -> URL
    ) throws -> SyncSnapshot {
        guard let teamSecret = local.teamSecret else { throw SyncError.fremdesTeam }

        let zipData = try openBundle(data, teamSecret: teamSecret)
        guard let archive = Archive(data: zipData, accessMode: .read) else {
            throw SyncError.ungueltigesPaket("Inhalt ist kein ZIP.")
        }

        // Schritt 3: nur den Snapshot.
        guard let snapshotEntry = archive["snapshot.json"] else {
            throw SyncError.ungueltigesPaket("snapshot.json fehlt.")
        }
        var snapshotBytes = Data()
        _ = try archive.extract(snapshotEntry) { teil in snapshotBytes.append(teil) }
        let snapshot = try TeamStateJson.snapshotFromJson(snapshotBytes)

        // Schritt 4: Team. Vorher wird nichts auf die Platte geschrieben.
        guard SyncMerge.verify(snapshot: snapshot, local: local) else { throw SyncError.fremdesTeam }

        // Schritt 5: Fotos, und nur solche, die der Snapshot auch nennt.
        let erlaubt = Set(snapshot.posters.compactMap(\.localPhotoFileName).filter(isSafeFileName))
        var gesamt = 0

        for entry in archive where entry.path.hasPrefix("photos/") && entry.type == .file {
            let name = String(entry.path.dropFirst("photos/".count))
            guard isSafeFileName(name), erlaubt.contains(name) else { continue }

            guard entry.uncompressedSize <= maxSinglePhotoBytes else {
                throw SyncError.zuGross("Ein Foto im Sync-Paket")
            }
            gesamt += Int(entry.uncompressedSize)
            guard gesamt <= maxTotalPhotoBytes else {
                throw SyncError.zuGross("Die Fotos im Sync-Paket zusammen")
            }

            var foto = Data()
            _ = try archive.extract(entry) { teil in foto.append(teil) }
            guard foto.count >= minValidPhotoBytes else {
                throw SyncError.ungueltigesPaket("Foto ist leer oder beschädigt: \(name)")
            }
            try foto.write(to: photoTargetURL(name), options: .atomic)
        }

        return snapshot
    }

    private static func zufall(_ anzahl: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: anzahl)
        guard SecRandomCopyBytes(kSecRandomDefault, anzahl, &bytes) == errSecSuccess else {
            throw SyncError.ungueltigesPaket("Zufallsquelle nicht verfügbar.")
        }
        return Data(bytes)
    }
}
