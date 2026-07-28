# Plakat Kompass für iOS

[![CI Status](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/ci-status.yml/badge.svg)](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/ci-status.yml)
[![Swift Test](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/swift-test.yml/badge.svg)](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/swift-test.yml)

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

## Der Team-QR-Code

Die zweite Nahtstelle zu Android, und die, ohne die gar nichts geht: Er ist der einzige Weg, wie
zwei Geräte an dasselbe Team-Geheimnis kommen.

Felder mit `|` verbunden, jedes einzeln **Base64-URL ohne Padding**, UTF-8:

```
Version 4 (stabil):  PLAKATRADAR | 4 | teamId | teamName | leaderName | leaderDeviceId | teamSecret
Version 5 (rollend): … | 5 | … | teamKey | sequence | createdAt | expiresAt     (60 Sekunden gültig)
Version 3 (alt):     … | 3 | … | teamSecret | createdAt | expiresAt
Version 2:           wird abgewiesen
```

Geschrieben wird immer Version 4, damit ein Android-Gerät den Code eines iPhones lesen kann.

Das „ohne Padding" ist die Stelle, an der eine Nachbildung typischerweise danebenliegt:
Foundation liefert Standard-Base64 mit `=`, `+` und `/`. Es müssen `-`, `_` und kein `=` sein.

**Wer beitritt, ist noch nicht dabei.** Das eigene Gerät trägt sich als *nicht freigegeben* ein;
die Freigabe erteilt die Teamleitung. Sonst könnte sich jeder in ein Team schreiben, dessen
QR-Code er einmal gesehen hat.

## Bauen

Xcode auf einem Mac. Das gilt auch für den geteilten Kotlin-Kern: Seine iOS-Binärdateien lassen
sich ausschließlich dort erzeugen.

```bash
brew install xcodegen     # einmalig
xcodegen generate
open PlakatKompass.xcodeproj
```

In Xcode unter „Signing & Capabilities" das eigene Team wählen — die Team-ID gehört nicht ins Repo.

Wer XcodeGen nicht will: in Xcode ein iOS-App-Projekt anlegen, `App/` hineinziehen, das Package
als lokale Abhängigkeit einbinden und `App/Info.plist` übernehmen. `project.yml` sagt, welche
Einstellungen dabei nötig sind.

Nur den Kern prüfen, ohne App:

```bash
swift test
```

## Testvektoren

`Tests/Vektoren/sync-vektor-1.prsync` ist ein vollständiges Sync-Paket mit festen Werten.

Erzeugt hat es `Tools/testvektor_bauen.py` — **weder die Swift- noch die Kotlin-Seite**. Das ist
der Punkt: Käme der Vektor von einer der beiden, bestätigte der Test nur, dass diese Seite mit
sich selbst übereinstimmt. So müssen beide gegen etwas Drittes bestehen.

Dieselbe Datei liegt im Android-Repo unter `app/src/test/resources/vektoren/` und wird dort von
`PrsyncTestvektorTest` gelesen.

Neu erzeugen (ändert die Datei, also nur mit Grund):

```bash
python3 Tools/testvektor_bauen.py
```

Das Skript prüft sich selbst: Rückweg identisch, falscher Schlüssel scheitert, verändertes Byte
scheitert.

## Erste Version

Erfassen, Liste, Karte, Abgleich, Team-Beitritt. Sozialdaten, Flyer-Touren, amtlicher Export und
Handywechsel-Backup kommen danach.

## Wo man sieht, ob es grün ist

Zwei Abzeichen oben im Dokument, beide klickbar. Beide laufen auf GitHubs Runnern — bei einem
öffentlichen Repo sind die kostenlos, **auch die Macs**. Der zehnfache Faktor auf macOS-Minuten
gilt nur für private Repos. Ein eigener Rechner ist also nicht nötig.

**CI Status** (`ubuntu-latest`) erzeugt den Testvektor neu, lässt das Skript sich selbst
gegenprüfen und vergleicht das Ergebnis mit der eingecheckten Datei. Weicht sie ab, wird der Lauf
rot — und genau das ist der Fall, der sonst niemandem auffiele: Dann prüfen der Kotlin- und der
Swift-Test gegen **verschiedene Vorlagen**, und der ganze Kreuztest ist wertlos.

**Swift Test** (`macos-14`) übersetzt den Kern, lässt `swift test` laufen und baut die App über
XcodeGen. Das braucht einen Mac, daran führt kein Weg vorbei: CryptoKit, UIKit und MapKit gibt es
nur auf Apple-Plattformen.

### Warum hier kein selbst gehosteter Runner steht

An einem **öffentlichen** Repo kann jeder forken, einen Pull Request öffnen und damit fremden Code
auf dem eigenen Rechner ausführen lassen. GitHub rät in der eigenen Dokumentation davon ab. Die
Voreinstellung „Freigabe bei Erstbeitragenden" greift nur beim allerersten Mal und ist kein
Ersatz.

Solange das Repo öffentlich ist, gibt es dafür auch keinen Grund: GitHubs Runner kosten nichts und
sind immer da.

## Stand

| | |
|---|---|
| Kern: Modell, JSON, Krypto, `PRSYNC2`, Merge, Team-QR | steht |
| Oberfläche: Erfassen, Liste, Karte, Abgleich, Team-Beitritt | steht |
| Testvektoren und Tests auf beiden Seiten | steht |
| **Auf einem Mac übersetzt** | **noch nie** |

Der letzte Punkt ist kein Nebensatz. Der gesamte Swift-Code ist gegen den Android-Quelltext
geschrieben, aber durch keinen Compiler gelaufen. Der erste `swift test` wird Fehler zeigen. Die
wahrscheinlichsten Stellen: die ZIPFoundation-Schnittstelle (0.9.x liefert `Archive(…)` optional,
neuere Fassungen werfen) und `URL: @retroactive Identifiable`, das Swift 6 braucht — bei 5.9 muss
das Attribut weg.

Noch nicht gebaut: App-Icon, Startbildschirm, Sozialdaten, Flyer-Touren, amtlicher CSV-Export,
Handywechsel-Backup und der Abgleich über den Relay-Server.

## Lizenz

AGPL-3.0, siehe [LICENSE](LICENSE).
