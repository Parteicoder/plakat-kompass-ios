# Plakat Kompass für iOS

iOS-Fassung von [Plakat Kompass](https://github.com/Parteicoder/plakat-radar-intern). Die App
erfasst Wahlplakate mit Foto und Standort, verwaltet ihren Zustand bis zur Abnahme und gleicht sich
mit den Geräten des Teams ab.

**Die Anforderung, an der alles hängt:** Die iOS-Fassung muss sich mit der Android-Fassung
abgleichen können. Nicht nebeneinander existieren — miteinander reden.

## Wie der Abgleich zwischen Android und iOS läuft

Der Android-Abgleich von Gerät zu Gerät läuft über **Google Nearby Connections**. Diese
Schnittstelle gibt es auf iOS nicht, und es gibt auch keinen Client, der ihr Protokoll spricht.
Zwischen Android und iOS ist dieser Weg damit versperrt, egal wie gut der Rest portiert ist.

Der gemeinsame Weg ist stattdessen die **Datei**: Ein Gerät erzeugt ein verschlüsseltes Sync-Paket
und verschickt es über den normalen Teilen-Dialog des Systems — Messenger, Mail, AirDrop,
Dateiablage, was gerade da ist. Das Gegenstück öffnet die Datei und führt sie zusammen.

Auf Android ist dieser Weg bereits vollständig eingebaut und ausgeliefert:

| | |
|---|---|
| Erzeugen und teilen | `PlakatRadarViewModel.shareSyncBundle()` |
| Empfangen | `importSyncBundle(uri)`, dazu Intent-Filter im Manifest |

Für iOS heißt das: Es ist **kein Netzwerkcode nötig**, kein Bonjour, kein eigenes Protokoll. Die
gesamte Schnittstelle zwischen den beiden Apps ist das unten beschriebene Dateiformat. Wer es
byteweise trifft, ist kompatibel; wer daneben liegt, ist es nicht.

Ein Abgleich über einen eigenen Relay-Server ist als späterer Zusatzweg vorgesehen
([Backend](https://github.com/Parteicoder/plakat-kompass-backend)), aber nicht Voraussetzung.

## Das Sync-Paket, `PRSYNC2`

Maßgeblich ist der Android-Quelltext
`app/src/main/java/de/bsw/plakatradar/sync/SyncBundleCodec.kt`. Weicht dieses Dokument davon ab,
gilt der Quelltext.

### Aufbau der Datei

```
"PRSYNC2\n"        8 Byte, ASCII, mit abschließendem Zeilenumbruch
IV                12 Byte, kryptographisch zufällig, je Paket neu
Chiffrat          AES-256-GCM, Authentifizierungs-Tag 128 Bit am Ende
```

| | |
|---|---|
| Schlüssel | `SHA-256(teamSecret)`, die **rohen 32 Byte**, nicht als Hex |
| `teamSecret` | die UTF-8-Bytes der Zeichenkette |
| AAD | genau die 8 Magic-Bytes `PRSYNC2\n` |
| Tag | 128 Bit; Javas `CipherOutputStream` hängt es an das Chiffrat an, `CryptoKit` erwartet es dort ebenfalls |

Der Klartext ist ein **ZIP**:

```
snapshot.json           der Datenstand als JSON, UTF-8
photos/<dateiname>      je ein JPEG pro Plakatfoto
```

Dateinamen der Fotos müssen `[a-zA-Z0-9._-]{1,120}` erfüllen. Alles andere wird abgewiesen — ein
Paket von einem fremden Gerät darf keine Pfade vorgeben.

### Grenzwerte

Sie schützen vor ZIP-Bomben und beschädigten Paketen. Die iOS-Seite muss sie **beim Streamen**
prüfen, nicht erst nach dem vollständigen Entpacken.

| Grenze | Wert |
|---|---|
| Foto mindestens | 1 KiB |
| Foto höchstens | 8 MiB |
| Fotos zusammen höchstens | 250 MiB |
| Paket höchstens | 300 MiB |

### Reihenfolge beim Import — sicherheitsrelevant

Diese Reihenfolge ist keine Empfehlung, sondern Teil des Formats:

1. Paketgröße gegen die Obergrenze prüfen.
2. Entschlüsseln. Schlägt die GCM-Prüfung fehl, hier abbrechen.
3. **Nur `snapshot.json` lesen**, sonst nichts.
4. Team prüfen (siehe unten). Scheitert das, hier abbrechen — es wird **kein** Foto entpackt.
5. Erst danach Fotos entpacken, und nur solche, die im Snapshot auch wirklich vorkommen.

### Teamprüfung

```
snapshot.teamId == lokale teamId
  und  snapshot.teamSecretHash == sha256Hex(lokales teamSecret)   in konstanter Zeit vergleichen
  und  ( Absender ist dieses Gerät selbst
         oder Absender steht lokal als Gerät, das approved und nicht blocked ist )
```

Vorbild ist `core/SyncMerge.kt`, `verify()`.

### `snapshot.json`

```json
{
  "schemaVersion": 1,
  "teamId": "…",
  "teamName": "…",
  "senderDeviceId": "…",
  "senderName": "…",
  "teamSecretHash": "hex(sha256(teamSecret))",
  "devices": [ … ],
  "posters": [ … ],
  "deletedPosters": [ … ],
  "events": [ … ],
  "flyerTours": [ … ],
  "createdAt": 1234567890000
}
```

Ist `schemaVersion` **größer** als die eigene, wird das Paket abgewiesen mit dem Hinweis, zuerst die
App zu aktualisieren. Kleinere Versionen werden gelesen.

Einrückung und Reihenfolge der Schlüssel sind **frei**. Über das JSON wird nichts gehasht,
`teamSecretHash` ist der Hash des Geheimnisses und nicht des Dokuments. Android schreibt mit
Einrückung 2, das ist Bequemlichkeit beim Lesen, keine Vorschrift.

## Aufbau des Projekts

Der Kern — Datenmodell, Zusammenführen, JSON, `PRSYNC2`, Krypto — wird **nicht** in Swift
nachgebaut, sondern als **Kotlin-Multiplatform-Modul** aus dem Android-Repo geteilt und hier als
`XCFramework` eingebunden. Grund: Das Einzige, was zwischen den Plattformen übereinstimmen muss,
ist genau dieser Code. Zweimal geschrieben läuft er früher oder später auseinander, und zwar
stillschweigend — man merkt es erst, wenn im Feld Daten fehlen.

Nativ in Swift entsteht alles darüber: Oberfläche in SwiftUI, Kamera, Standort, Karte über MapKit,
Teilen und Empfangen über die Systemdialoge.

## Gegen das Auseinanderlaufen

Im Repo liegen **Testvektoren**: feste Eingaben mit erwarteten Bytes. Die Kotlin-Tests und die
Swift-Tests lesen dieselben Dateien. Dazu ein kreuzweiser Durchlauf — ein von Kotlin erzeugtes
Paket wird von Swift entschlüsselt und umgekehrt. Weicht eine Seite ab, wird der Build rot statt
des Nutzers im Feld ratlos.

## Erste Version

Erfassen, Liste, Karte, Abgleich. Sozialdaten, Flyer-Touren, amtlicher Export und
Handywechsel-Backup kommen danach.

## Voraussetzung zum Bauen

Xcode auf einem Mac. Das gilt auch für den geteilten Kotlin-Kern: Seine iOS-Binärdateien lassen
sich ausschließlich dort erzeugen.

## Lizenz

AGPL-3.0, siehe [LICENSE](LICENSE).
