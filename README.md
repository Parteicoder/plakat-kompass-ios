# Plakat Kompass für iOS

[![CI Status](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/ci-status.yml/badge.svg)](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/ci-status.yml)
[![Swift Test](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/swift-test.yml/badge.svg)](https://github.com/Parteicoder/plakat-kompass-ios/actions/workflows/swift-test.yml)

iOS-Fassung von **Plakat Kompass**. Die App
erfasst Wahlplakate mit Foto und Standort, verwaltet ihren Zustand bis zur Abnahme und gleicht sich
mit den Geräten des Teams ab.

**Die Anforderung, an der alles hängt:** Die iOS-Fassung muss sich mit der Android-Fassung
abgleichen können. Nicht nebeneinander existieren — miteinander reden.

## Wie der Abgleich zwischen Android und iOS läuft

Es gibt zwei Wege. Beide tragen denselben Inhalt — das unten beschriebene `PRSYNC2`-Paket.

### 1. Die Datei

Ein Gerät erzeugt ein verschlüsseltes Sync-Paket und verschickt es über den normalen
Teilen-Dialog des Systems — Messenger, Mail, AirDrop, Dateiablage, was gerade da ist. Das
Gegenstück öffnet die Datei und führt sie zusammen. Auf Android ist dieser Weg vollständig
eingebaut und ausgeliefert:

| | |
|---|---|
| Erzeugen und teilen | `PlakatRadarViewModel.shareSyncBundle()` |
| Empfangen | `importSyncBundle(uri)`, dazu Intent-Filter im Manifest |

Dieser Weg braucht **keinen Netzwerkcode**, kein Bonjour, kein eigenes Protokoll. Die ganze
Schnittstelle zwischen den beiden Apps ist das Dateiformat. Wer es byteweise trifft, ist
kompatibel; wer daneben liegt, ist es nicht.

### 2. Der Funk-Abgleich über Nearby Connections

Der Abgleich von Gerät zu Gerät läuft auf Android über **Google Nearby Connections**. An dieser
Stelle stand hier lange, die Schnittstelle gebe es auf iOS nicht und es gebe auch keinen Client
für ihr Protokoll. **Das war falsch.** Google liefert Nearby Connections seit 2023 als
Swift-Paket ([`google/nearby`](https://github.com/google/nearby), Produkt `NearbyConnections`),
und der Abgleich zwischen Android und iOS ist ausdrücklich vorgesehen, solange Dienstkennung und
Strategie auf beiden Seiten übereinstimmen. Beides tut es hier: `de.bsw.plakatradar.LOCAL_SYNC`
und `P2P_CLUSTER`. Der Handschlag ist derselbe wie auf Android — `AUTH_CHALLENGE` →
`AUTH_RESPONSE` mit `HMAC-SHA256(teamSecret, nonce)` → `AUTH_OK`, danach das `PRSYNC2`-Paket.

Was auf iOS **nicht** geht, und das ist die entscheidende Einschränkung: Von allen Funkwegen
trägt hier nur das **WLAN**. Bluetooth, Wi-Fi Direct und AWDL helfen zwischen Android und iPhone
nicht — AWDL ist Apples eigener Weg und spricht nur mit Apple-Geräten. Beide Geräte müssen also
im selben Netz hängen; der Hotspot eines der beiden Telefone genügt. Auf freiem Feld ohne Netz
und ohne Hotspot finden sie sich nicht, dann bleibt Weg 1. Zwischen zwei Android-Geräten gilt das
nicht: dort bleibt der volle Funkweg über Bluetooth und Wi-Fi Direct.

Drei Dinge, die beim Nachbauen Zeit kosten, wenn man sie nicht weiß:

- **Das Paket hat keinen brauchbaren Tag.** Der einzige ist `v0.0.1-ios` von November 2021 und
  liegt lange vor dem Swift-Paket. `project.yml` nagelt deshalb eine Revision fest. Ein Branch
  wäre die schlechtere Wahl: Dann änderte ein fremder Push den eigenen Bau, unbemerkt.
- **`NSBonjourServices` muss den richtigen Typ enthalten.** Nearby leitet ihn aus der
  Dienstkennung ab: `_` + erste sechs Byte von `SHA-256(Dienstkennung)` in Großhex + `._tcp`,
  hier also `_EA0A851F84A0._tcp`. Steht der falsche Typ dort, blockt iOS die Suche seit Version
  14 lautlos — kein Absturz, kein Log, nur nie ein gefundenes Gerät. `NearbyDienst.swift` rechnet
  ihn aus, `NearbyDienstTests` prüft die Ableitung gegen Googles eigenes Beispiel, und ein
  CI-Schritt prüft den Wert in der **gebauten** App.
- **Das Paket bringt kein Datenschutz-Manifest mit** (`find . -name "*.xcprivacy"` im Nearby-Repo
  findet nichts). Damit fällt die Frage, welche begründungspflichtigen Schnittstellen es benutzt,
  auf diese App zurück. Sie ist beantwortet — siehe unten.

Ein Abgleich über einen eigenen Relay-Server ist als späterer Zusatzweg vorgesehen, aber nicht
Voraussetzung.

## Das Sync-Paket, `PRSYNC2`

Die Android-App ist nicht öffentlich. Dieses Dokument ist deshalb die vollständige und
maßgebliche Beschreibung des Formats — es ist aus `sync/SyncBundleCodec.kt` der Android-Fassung
abgeleitet, aber es setzt nichts voraus, was man dort nachschlagen müsste.

Wer prüfen will, ob eine eigene Umsetzung stimmt, braucht den Quelltext auch gar nicht: Unter
`Tests/PlakatKompassCoreTests/Vektoren/` liegt ein vollständiges Paket mit bekanntem Schlüssel. Wer es öffnet und die
Werte aus `sync-vektor-1.json` herausbekommt, ist kompatibel.

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
  "schemaVersion": 2,
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

```
Sources/PlakatKompassCore/   Datenmodell, JSON, Krypto, PRSYNC2, Merge, Team-QR, Persistenz
App/                         SwiftUI: Erfassen, Liste, Karte, Abgleich, Team
Tests/                       Kreuztests gegen den Testvektor
Tools/                       Erzeuger des Testvektors
```

Der Kern ist in Swift geschrieben, nicht mit Android geteilt. Ursprünglich war ein gemeinsames
Kotlin-Multiplatform-Modul geplant — das hätte die Formatlogik zu buchstäblich demselben Code
gemacht und ein Auseinanderlaufen unmöglich. Dagegen sprach, dass die Android-App dafür in Module
umgebaut werden müsste und jeder iOS-Bau dann von einem erzeugten `XCFramework` abhinge.

Der Preis dieser Entscheidung ist real: Dieselbe Logik steht zweimal, in zwei Sprachen. Genau
deshalb sind die Testvektoren im nächsten Abschnitt keine Kür, sondern das, was die Entscheidung
überhaupt vertretbar macht.

## Gegen das Auseinanderlaufen

Im Repo liegt ein **Testvektor**: ein vollständiges Paket mit festen Werten, erzeugt von
`Tools/testvektor_bauen.py` — **weder von der Swift- noch von der Kotlin-Seite**.

Das ist der Punkt. Käme er von einer der beiden, bestätigte der Test nur, dass diese Seite mit
sich selbst übereinstimmt; das ist der häufigste Weg, sich eine grüne Prüfung zu bauen, die nichts
bedeutet. So müssen beide gegen etwas Drittes bestehen.

Dieselbe Datei liegt in beiden Repos. Weicht eine Seite ab, wird der Build rot statt des Nutzers
im Feld ratlos.

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

**Mindestens iOS 17.** Damit fallen iPhone X, 8 und 8 Plus heraus — Geräte von 2017. Ab dem
iPhone XS von 2018 läuft die App. Die Alternative wäre iOS 16 gewesen, dann müssten Karte, Liste
und Leerzustand auf die alten Schnittstellen zurück (`Map(coordinateRegion:)` statt
`Map(position:)`, kein `ContentUnavailableView`, kein `.topBarLeading`). Die Zahl steht an zwei
Stellen und muss dort zusammenpassen: `Package.swift` und `project.yml`.

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

`Tests/PlakatKompassCoreTests/Vektoren/sync-vektor-1.prsync` ist ein vollständiges Sync-Paket mit festen Werten.

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
| Startseite, Erfassen, Liste, Karte, Abgleich, Team-Beitritt | steht |
| Allein loslegen, ohne Team | steht |
| Abnahmefristen: Statusautomatik und Erinnerung | steht |
| Amtlicher Export: Liste und Fotos als ZIP | steht |
| Flyer-Touren aufzeichnen und ansehen | steht |
| Sozialdaten aus dem Regionalatlas | steht |
| Gemeindegrenzen auf der Karte | steht |
| Team-Schlüssel erneuern, Geräte sperren | steht |
| App-Icon und Startbildschirm | steht, Icon hochgerechnet |
| Testvektoren und Tests auf beiden Seiten | steht |
| Auf einem Mac übersetzt, App gebaut, Tests grün | seit `add5eb3` |

Der letzte Punkt war lange der wunde: Der Swift-Code war gegen den Android-Quelltext geschrieben
und durch keinen Compiler gelaufen. Seit der CI auf `macos-15` läuft, ist das erledigt — `swift
build`, `swift test` und `xcodebuild` für den Simulator sind grün, und der Swift-Test liest den
Testvektor, den die Kotlin-Seite ebenfalls liest.

**Auf einem echten iPhone gelaufen ist die App noch nicht.** Der CI baut für den Simulator und
ohne Signierung; Kamera, Standort und der Teilen-Dialog sind damit übersetzt, aber nicht erprobt.

## Was das Gerät verlässt

Kurz: die Fotos und Standorte **nicht**. Es gibt keinen Server der Entwickler.

| Wohin | Was | Wann |
|---|---|---|
| Empfänger nach Wahl | verschlüsseltes Sync-Paket | nur wenn jemand „teilen" antippt |
| Stadtverwaltung | ZIP mit Liste und Fotos, unverschlüsselt | nur beim amtlichen Export |
| Regionalatlas (Statistische Ämter) | ungefähre Position, auf 3 Nachkommastellen gerundet | nur im Bereich Sozialdaten |
| Overpass (OpenStreetMap) | ungefähre Position, auf 2 Nachkommastellen gerundet | nur mit eingeschaltetem Grenzen-Schalter |

Die beiden Abfragen beantworten die Anfrage und behalten nichts, was der App zuzuordnen wäre.
Gerundet wird nicht aus Vorsicht allein, sondern weil sonst jedes Zittern der Ortung eine neue
Abfrage auslöst — 100 Meter ändern am Gebiet ohnehin nichts.

`App/PrivacyInfo.xcprivacy` sagt dasselbe maschinenlesbar. Apple verlangt die Datei seit Frühjahr
2024 beim Einreichen und prüft sie gegen den tatsächlichen Code: kein Tracking, nichts erhoben,
und als einzige begründungspflichtige Schnittstelle `UserDefaults` (hinter jedem `@AppStorage`).
Ein CI-Schritt prüft, dass sie im gebauten Bundle landet — fehlt sie, fiele das sonst erst beim
Einreichen auf.

**Warum das seit dem Funk-Abgleich nicht mehr am Quelltext zu beantworten ist:** Apple prüft am
fertigen Programm, und darin steckt nun auch alles, was Nearby Connections mitbringt — abseil,
BoringSSL, protobuf, ein C++-Kern. Deren Quellen liegen nicht in diesem Repo, und ein eigenes
Datenschutz-Manifest liefert Nearby nicht. Ein zweiter CI-Schritt durchsucht deshalb das
**gebaute Programm** mit `nm` und `otool` nach den begründungspflichtigen Symbolen und schlägt
fehl, sobald etwas auftaucht, das im Manifest nicht steht.

Zwei Dinge dazu, damit der Schritt nicht mehr verspricht, als er hält:

- Er sieht **nur direkte Aufrufe**. Was ein Systemframework für die App erledigt, steht nicht im
  Programm — `@AppStorage` etwa greift innerhalb von SwiftUI auf `UserDefaults` zu und taucht
  deshalb nicht auf, obwohl die App es benutzt. Für eigenen Swift-Code bleibt der Quelltext
  maßgeblich; der Symbolscan ist für die mitgebrachten C- und C++-Bibliotheken da, die libc
  direkt aufrufen.
- Er **prüft sich selbst** an `malloc` und sagt es laut, wenn er nichts sieht. Ohne das wäre ein
  leeres Ergebnis nicht von „nichts gefunden" zu unterscheiden, und die Aufgabe würde grün,
  gerade weil sie blind ist.

**Und genau das ist bisher der Fall.** Der Scan hat am gebauten Programm mehrfach nichts gesehen —
erst weil `nm -u` bei Xcodes *chained fixups* die Importe nicht findet, dann weil das
Kontrollsymbol schlecht gewählt war. Für Nearbys C++-Kern ist die Frage damit **nicht
abschließend geklärt**. Verbindlich ist ohnehin Apples eigene Prüfung beim Hochladen; kommt von
dort eine Meldung (ITMS-91053), stehen die passenden Begründungscodes in
`App/PrivacyInfo.xcprivacy` bereit. Ohne Entwicklerkonto ist hier nicht mehr zu holen, und ein
Manifest, das mehr behauptet, wäre schlechter als eines, das die Lücke benennt.

## Was Android kann und iOS nicht — und warum

Vier Dinge fehlen. Bei dreien ist das keine offene Aufgabe, sondern das Ergebnis.

**Funk-Abgleich ohne Netz.** Der Funk-Abgleich selbst gibt es inzwischen (siehe oben), aber nicht
in derselben Reichweite: Android verbindet sich auch ohne Netz über Bluetooth und Wi-Fi Direct,
zwischen Android und iPhone trägt nur das WLAN. Ebenfalls offen bleiben der Handywechsel über
Nearby und die „Teamaufnahme" mit rollendem QR-Code — beide sind eigene Abläufe über demselben
Transport, keine Folge der Plattform. **Ersatz für den netzlosen Fall:** das Sync-Paket als Datei
über den Teilen-Dialog. Das braucht Netz oder AirDrop, funktioniert dafür in beide Richtungen.

**Offline-Kartenkacheln.** Android nutzt osmdroid und legt die Kacheln selbst ab. MapKit gibt
seinen Kachelspeicher nicht heraus. Offlinekarten sind auf iOS seit 17 eine Systemfunktion —
sie in der App nachzubauen hieße, gegen die Plattform zu arbeiten.

**Handywechsel-Backup (`PRBACKUP2`).** Android braucht es, weil sein Auto-Backup den
verschlüsselten Gerätestand nicht mitnimmt. Auf iOS liegt alles unter „Application Support" und
wandert mit dem iCloud-Backup auf das neue Gerät. Wer kein iCloud-Backup nutzt, kommt über
Sync-Paket und Team-QR an seine Daten.

**Relay-Abgleich.** Der einzige Punkt auf dieser Liste, der wirklich noch aussteht. Der Server
existiert, die iOS-Anbindung nicht.

## App-Icon

Dieselbe Kompassrose wie auf Android, aus `mipmap-xxxhdpi/ic_launcher.png` des Android-Repos
umgerechnet mit `Tools/appicon_bauen.py`. Das Skript ist da, weil die Umrechnung nicht
offensichtlich ist: Android bringt seine abgerundeten Ecken als Grafik mit, iOS legt später
seine eigene Maske darüber, und blieben die weißen Ecken stehen, sähe man nach dem Maskieren
einen hellen Rand um die cremefarbene Fläche.

**Die Auflösung ist die Schwachstelle.** Die größte im Android-Repo vorhandene Fassung des
Kompass-Motivs misst 192 × 192; ein Vektor existiert nicht mehr, er wurde beim Wechsel vom
alten Motiv entfernt. Der App Store verlangt 1024 × 1024, also wird um gut das Fünffache
hochgerechnet, und das sieht man. Für Entwicklung und TestFlight reicht es, für eine
Veröffentlichung nicht. Sobald die Originaldatei auftaucht, gehört sie ins Skript — dann fällt
der Vergrößerungsschritt weg und der Rest bleibt.

Der Startbildschirm hat bewusst weder Logo noch Schriftzug: Apples Richtlinie will einen, der
wie die erste Seite der App aussieht, damit der Start kurz wirkt. Ein leerer `UILaunchScreen`
nimmt die Systemhintergrundfarbe und wechselt von allein zwischen hell und dunkel.

## Der amtliche Export

Ein ZIP mit `plakatliste.csv` und `fotos/plakat_001.jpg…`, gedacht für die Stadtverwaltung.
Gegenstück zu `core/OfficialExport.kt`.

Anders als ein Sync-Paket ist es **unverschlüsselt** und muss Android nicht Byte für Byte
entsprechen — es geht ans Rathaus, nie an ein Teamgerät. Interne Bemerkungen stehen nicht darin.

Drei Eigenheiten der CSV sind Absicht und sehen ohne Erklärung nach Fehlern aus:

- **BOM am Dateianfang**, sonst zeigt älteres Excel aus Umlauten Buchstabensalat.
- **`sep=;` als erste Zeile**, sonst zerlegt Excel Überschriften wie „Aktueller Status" an den
  Leerzeichen.
- **Zellen, die mit `=`, `+`, `-`, `@`, Tab oder CR beginnen, bekommen ein Apostroph davor.**
  Excel und LibreOffice würden sie sonst als Formel ausführen. Standortbeschreibung, Bemerkung
  und Kommune sind Freitext und können per Abgleich von einem fremden Gerät stammen — das ist der
  einzige Weg, auf dem aus dieser App heraus fremder Inhalt auf einem Verwaltungsrechner landet.
  Echte Zahlen bleiben ausgenommen, damit ein Längengrad `-12.34` in der Tabelle rechnen kann.

## Lizenz

Proprietär, alle Rechte vorbehalten, siehe [LICENSE](LICENSE).
