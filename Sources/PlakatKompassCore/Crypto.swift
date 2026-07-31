import CryptoKit
import Foundation

/// Krypto-Bausteine, exakt so wie die Android-Fassung sie benutzt.
///
/// Nichts davon ist selbst gebaut — es sind Aufrufe an CryptoKit. Der Wert dieser Datei liegt
/// allein darin, dass die Ableitungen und Kodierungen an **einer** Stelle stehen und dokumentiert
/// ist, welche Android-Zeile jeweils das Gegenstück ist.
public enum Crypto {

    /// `MessageDigest.getInstance("SHA-256").digest(text.toByteArray(UTF_8))`
    public static func sha256(_ text: String) -> Data {
        Data(SHA256.hash(data: Data(text.utf8)))
    }

    /// Gegenstück zu `sha256Hex` in `core/Hashing.kt`. Kleinbuchstaben, keine Trennzeichen.
    public static func sha256Hex(_ text: String) -> String {
        hex(sha256(text))
    }

    /// Gegenstück zu `hmacSha256Hex(secret, message)` in `core/Hashing.kt`.
    /// Wird für den Nachweis im Handschlag gebraucht und später für `relayAuthSecret`.
    public static func hmacSha256Hex(secret: String, message: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return hex(Data(mac))
    }

    /// Der Schlüssel eines Sync-Pakets: die **rohen** 32 Byte aus `SHA-256(teamSecret)`.
    ///
    /// Nicht der Hex-String. Das ist die häufigste Art, dieses Format falsch nachzubauen — der
    /// Hex-String wäre 64 Byte und ergäbe einen völlig anderen Schlüssel.
    public static func payloadKey(teamSecret: String) -> SymmetricKey {
        SymmetricKey(data: sha256(teamSecret))
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Gegenstück zu `randomNonceHex(bytes)` in `core/Hashing.kt` — 32 Byte, Kleinbuchstaben.
    ///
    /// Die Länge ist kein Geschmack: Der Nonce ist die einzige Zufallszahl im Handschlag. Wer ihn
    /// erraten könnte, bereitete eine gültige Antwort vor, ohne den Team-Schlüssel zu kennen.
    ///
    /// `SymmetricKey(size:)` statt `Int.random` oder `SecRandomCopyBytes`: CryptoKit zieht
    /// Schlüsselmaterial aus derselben Quelle, kann dabei nicht fehlschlagen und ist hier ohnehin
    /// schon importiert. `Int.random` wäre an dieser Stelle schlicht falsch — das ist ein
    /// Zufallsgenerator für Spielkarten, nicht für Krypto.
    public static func randomNonceHex(bytes: Int = 32) -> String {
        hex(SymmetricKey(size: .init(bitCount: bytes * 8)).withUnsafeBytes { Data($0) })
    }

    /// Vergleich in konstanter Zeit, Gegenstück zu `constantTimeEqualsHex`.
    ///
    /// Ein `==` auf Strings bricht beim ersten ungleichen Zeichen ab. Wer viele Pakete schickt und
    /// die Antwortzeit misst, kann daraus Zeichen für Zeichen den erwarteten Wert ableiten.
    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8)
        let right = Array(b.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }
}
