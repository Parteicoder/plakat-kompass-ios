# Plakat Kompass für iOS — Projektkontext

Dieses Dokument richtet sich an eine KI oder eine Person, die neu auf dieses Repository trifft und
schnell arbeitsfähig sein soll. Es beschreibt **wofür die App da ist**, **wie diese Fassung
gebaut ist**, **was fertig ist** und **wo die Fallen liegen**.

**Das `README.md` daneben ist kein Beiwerk.** Dort steht das Austauschformat `PRSYNC2` byteweise,
der Ablauf des Team-QR, die Reihenfolge beim Import samt Begründung und die Testvektoren. Wer am
Abgleich arbeitet, liest zuerst das README. Dieses Dokument wiederholt das nicht, sondern ordnet
ein.

Der Schwesterrepo `Parteicoder/plakat-radar-intern` enthält die Android-Fassung — die ältere,
größere und funktional führende — und ein eigenes `PROJEKTKONTEXT.md`.

Stand dieses Dokuments: 15. August 2026, Basis `main` bei Commit `18d3b63`.

---

## 1. Wozu die App da ist

Plakat Kompass ist die iOS-Fassung eines internen Werkzeugs für **Wahlkampfteams einer Partei**.
Der Zweck ist auf beiden Plattformen derselbe:

**Wo hängen unsere Plakate?** Erfassen mit Foto, Position, Art und Standorthinweis.

**Fristgerecht abnehmen.** Kommunen setzen Abnahmefristen, bei Überschreitung drohen Gebühren.
Jedes Plakat trägt eine Frist, die App erinnert und setzt überfällige Plakate automatisch auf
einen Status, der die Wahrheit sagt.

**Die Verwaltung will eine Liste.** ZIP mit CSV und Fotos.

**Welche Straße ist mit Flyern versorgt?** Aufzeichnung des gelaufenen Wegs.

Dazu **Sozialdaten**: amtliche Gebietswerte (Regionalatlas, Zensus) auf der Karte, damit ein Team
einschätzen kann, wo sich der Aufwand lohnt. Ausschließlich gebietsbezogen, **keine
Personendaten**.

### Der eigentliche Daseinsgrund dieser Fassung

Es gab viele Anfragen nach einer iOS-Version. Die harte Anforderung war nie „auch eine App für
iPhones", sondern: **Android und iOS müssen miteinander abgleichen können.** Ein Team, in dem drei
Leute Android und zwei ein iPhone haben, muss einen gemeinsamen Datenstand führen. Daran hängt
alles Weitere, und daran ist das Vorhaben fast gescheitert — siehe Abschnitt 5.

---

## 2. Aufbau

Kein Xcode-Projekt im Repo. Zwei Wege in denselben Quelltext:

```
Package.swift     Swift Package  → swift build / swift test  (auch auf Linux-CI nutzbar)
project.yml       XcodeGen       → xcodebuild für den Simulator
```

```
Sources/PlakatKompassCore/   2593 Z.  Domäne, JSON, Krypto, PRSYNC2, Merge, Regeln
App/                         2536 Z.  SwiftUI-Oberfläche
Tests/                       146 Tests in 12 Dateien
Tools/                                Testvektor-Erzeugung, App-Icon-Umrechnung
```

`PlakatKompassCore` ist die Swift-Entsprechung von `core/` und Teilen von `data/` im
Android-Repo. Die Dateien heißen absichtlich gleich (`SyncMerge`, `AccessPolicy`,
`RemovalDeadlinePolicy`, `OfficialExport`, `TeamInvite`, `SyncBundleCodec`, `TeamStateJson`), damit
man beim Abgleichen zweier Fassungen nicht suchen muss.

**Mindestziel iOS 17.** Das war eine bewusste Entscheidung des Nutzers: iOS 17 schließt das
iPhone X und 8 aus (2017), das iPhone XS (2018) und neuer laufen. Dafür stehen `MapCameraPosition`,
`Map(position:)`, `Annotation`, `MapPolyline`, `ContentUnavailableView` und `.topBarLeading` zur
Verfügung — ohne die wird der Kartenbildschirm deutlich umständlicher. Ein Rückbau auf iOS 16
wurde versucht und wieder verworfen.

### Oberfläche

`PlakatKompassApp` hält zwei Objekte auf App-Ebene und gibt sie als `environmentObject` weiter:

- `AppModel` — der Zustand
- `TourAufzeichnung` — der Ortungs-Aufzeichner

**Warum der Aufzeichner der App gehört und nicht dem Bildschirm:** Als `@StateObject` in
`FlyerTourenView` lebte er nur, solange die Ansicht auf dem Navigationsstapel lag. Wer nach dem
Start der Tour zurückging, gab den `CLLocationManager` frei, und die Aufzeichnung endete lautlos —
also genau im gedachten Ablauf: Tour starten, Telefon einstecken, Flyer verteilen. Auf einem Gerät
hätte das wie ein Problem mit der Ortung ausgesehen, nicht wie ein Fehler im Code.

Fünf Reiter: Start, Erfassen, Liste, Karte, Abgleich. Der Listen-Reiter trägt ein Abzeichen mit
der Zahl fälliger Abnahmen.

---

## 3. Was fertig ist

Vollständig, übersetzt, mit Tests und grüner CI:

| Bereich | Datei |
|---|---|
| Domäne, JSON, Merge, Tombstones | `Domain.swift`, `TeamStateJson.swift`, `SyncMerge.swift` |
| Krypto und `PRSYNC2` | `Crypto.swift`, `SyncBundleCodec.swift` |
| Team-QR, Beitritt und Geräteverwaltung (freigeben/sperren, Schlüssel erneuern) | `TeamInvite.swift`, `TeamView.swift`, `SyncView.swift` |
| Rechte und Rollen | `AccessPolicy.swift` |
| Abnahmefristen samt Statusautomatik | `RemovalDeadlinePolicy.swift` |
| Amtlicher Export | `OfficialExport.swift` |
| Sozialdaten, Regionalatlas (Gemeinde/Kreis) | `SocialData.swift`, `SozialdatenView.swift` |
| Sozialdaten, Zensus-Gitter (Umkreis 300 m) | `Epsg3035.swift`, `ZensusRaster.swift` |
| Flyerkarte auf der Hauptkarte | `FlyerZeichnung.swift`, `PosterMapView.swift` |
| Statusfilter, von Liste und Karte geteilt | `PosterFilter.swift` |
| Gemeindegrenzen | `CommuneBoundary.swift` |
| Flyer-Touren | `FlyerTourenView.swift`, `TourAufzeichnung.swift` |
| Erinnerungen | `Erinnerungen.swift` |
| Startseite, Erfassen, Liste, Karte, Abgleich | `StartView`, `CaptureView`, `PosterListView`, `PosterMapView`, `SyncView` |
| Funk-Abgleich mit Android | `NearbyAbgleich.swift`, `NearbyDienst.swift` |
| Kurzanleitung je Bereich | `Kurzanleitung.swift` |
| Handywechsel-Backup (`PRBACKUP2`) | `DeviceBackupCodec.swift`, `HandywechselNearby.swift` |
| Experten-Bildschirm mit Diagnose | `ExpertenView.swift` |
| Dauerhaftes Protokoll und Absturzberichte | `Protokoll.swift`, `Absturzberichte.swift` |
| Sozialdaten-Zwischenspeicher auf der Platte | `SozialdatenCache.swift`, `SozialCachePolitik.swift` |
| Darstellung hell/dunkel/automatisch | `Darstellung.swift` |
| Adresssuche auf der Karte | `PosterMapView.swift` |
| Fassungsanzeige aus dem Bundle (Lizenzseite, Protokoll-Startzeile) | `Helpers.swift` (`Fassung`), `EinstellungenView.swift`, `Protokoll.swift` |
| Standort-Knopf in der Liste, wie auf Android jede Zeile | `PosterListView.swift`, `Helpers.swift` (`Poster.hinlaufen()`) |
| Backup-Empfang auf dem Einrichtungsbildschirm, Team-QR und Support & Community auf der Startseite | `SyncView.swift` (`UmzugBeimEinrichten`), `StartView.swift` (`Teamaufnahme`, `UnterstuetzenUndGemeinschaft`) |
| Adresse von Hand beim Erfassen, wenn die Ortung nichts liefert | `AdresseAufloesen.swift`, `CaptureView.swift` |

**Auf einem echten iPhone ist nichts davon gelaufen.** Die CI baut für den Simulator und ohne
Signierung. Kamera, Standort, Hintergrundortung und der Teilen-Dialog sind übersetzt, aber nicht
erprobt. Die Hintergrundortung ist dabei das Riskanteste: iOS gibt dafür weder feste Takte noch
Garantien.

Für den **Funk-Abgleich** gilt das doppelt: Er lässt sich im Simulator gar nicht prüfen, weil dort
kein Funk vorhanden ist. Was hier grün wird, heißt nur „übersetzt". Der erste echte Beweis ist ein
iPhone und ein Android-Gerät im selben WLAN. Fällt dabei etwas aus, sind die beiden ersten
Verdächtigen die Berechtigung fürs lokale Netzwerk und die Frage, ob beide Geräte wirklich
im selben Netz hängen — nicht der Team-Schlüssel.

---

## 4. Wie Fristen und Merge funktionieren — die zwei Stellen mit Tücke

**Fristenregel.** `RemovalDeadlinePolicy` setzt ein überfälliges Plakat auf `DAMAGED`. Sie wird an
**drei** Stellen angewandt: beim Laden, beim Speichern und beim Erzeugen eines Snapshots. Die
dritte ist die, die man vergisst — und ohne sie verbreitet ein Gerät veraltete Status an die
Teamkollegen. Auf Android waren es ursprünglich fünf Anwendungspunkte; beim Portieren fehlte
einer, und der Fehler wäre erst im Team aufgefallen.

**Merge.** Jüngeres `updatedAt` gewinnt, bei Gleichstand ein deterministischer Tiebreak, damit
zwei Geräte nie unterschiedlich entscheiden. Tombstones schlagen Plakate dauerhaft. Flyer-Touren
werden vereinigt statt ersetzt, damit keine Wegpunkte verloren gehen.

**Ereignisverlauf gedeckelt.** Höchstens 1000 Einträge, nach `createdAt` absteigend sortiert —
deterministisch, damit zwei Geräte dieselben behalten. Ohne den Deckel wurde die Android-App über
eine Kampagne hinweg spürbar träge.

---

## 5. Stand des Ports: was noch offen ist

Der Abgleich Android ↔ iOS ist **funktionsweise durchgegangen**, in drei Durchläufen: die Dateien
des Kerns gegeneinander, dann die Funktionen über ihre Symbole, zuletzt die **Bildschirminhalte
Feld für Feld**. Der dritte Durchgang war der ergiebigste — er hat mehrere Lücken gefunden, die die
ersten beiden nicht zeigen konnten: die Adresse von Hand beim Erfassen, den Backup-Empfang auf
dem Einrichtungsbildschirm, Team-QR und Support & Community auf der Startseite, den
Standort-Knopf in der Liste. Alle vier sind inzwischen in Abschnitt 3 als fertig gelistet.

**Eine Warnung zur Methode, weil sie zweimal in die Irre geführt hat:** Nach Android-Namen zu
suchen findet Lücken, die es nicht gibt. `FirstCaptureHintStore` heisst auf iOS
`hatFotoAufgenommen`, `NearestPoster` liegt in `HomeStats.swift`, `EventHistoryPolicy` in
`RemovalDeadlinePolicy.swift`. Wer eine Lücke vermutet, sucht nach **Verhalten**, nicht nach
Bezeichnern.

### 5.1 Geht nicht — Plattformgrenze

**Offline-Kartencache.** Android zeichnet OSM-Kacheln selbst (osmdroid) und kann sie deshalb
vorhalten. MapKit gibt seinen Kachelspeicher nicht heraus. Kein Aufwandsproblem, sondern eine
Grenze der Schnittstelle. Offlinekarten sind auf iOS seit 17 Systemfunktion und stehen
ausserhalb der App zur Verfügung.

### 5.2 Geht nur teilweise

**Absturzprotokoll.** Android fängt mit `Thread.setDefaultUncaughtExceptionHandler` jeden Absturz
ab. Auf iOS gibt es dafür kein Gegenstück:

- `NSSetUncaughtExceptionHandler` fängt nur Objective-C-Ausnahmen — ist gebaut.
- Swift-Laufzeitfehler (`fatalError`, Index über das Ende, `nil` beim Auspacken) lösen keine
  Ausnahme aus, sondern ein `SIGTRAP`. Ein Signal-Handler dafür dürfte weder Swift noch
  Objective-C noch `malloc` benutzen; Apple rät ausdrücklich davon ab, und selbst ausgereifte
  Fremdpakete verdecken damit gelegentlich den echten Absturz. **Bewusst nicht gebaut.**
- Stattdessen **MetricKit** (`Absturzberichte.swift`): liefert Grund und Aufrufliste, Swift-Traps
  eingeschlossen — das ist *mehr* als Android hat. Aber **nur auf echten Geräten**, praktisch
  erst über TestFlight. Im Simulator kommt nichts an, der CI kann es nicht prüfen.
- Die Marke in `Protokoll.swift` deckt die Lücke halb: Sie merkt überall, **dass** der vorige
  Lauf nicht geordnet endete — nur nicht, warum.

### 5.3 Kein Unterschied zu Android — beide haben es nicht

**Relay-Abgleich.** Das README liest sich, als fehle nur die iOS-Anbindung. Tatsächlich hat
**auch Android keinen Relay-Client**; `grep -rl "relay" app/src/main/java` findet nichts. Das
Backend-Repository existiert, ist aber an keine der beiden Apps angebunden. Wer das angeht,
fängt auf beiden Seiten bei null an.

### 5.4 Nicht offen, sondern ungeprüft — und das ist der wichtigere Punkt

Diese Dinge sind **gebaut und übersetzt**, aber nie in ihrer eigentlichen Funktion gelaufen. Der
CI baut für den Simulator, und der hat weder Kamera noch Funkgegenüber:

| | erster echter Beweis wäre |
|---|---|
| Funk-Abgleich mit Android | iPhone und Android-Gerät im selben WLAN, Abgleich in beide Richtungen mit Foto |
| Handywechsel | zwei iPhones, auf dem alten „umziehen", auf dem neuen „übernehmen" |
| Kamera und Foto-Verkleinerung | ein Gerät |
| Adresse von Hand beim Erfassen | ein Gerät mit Netz, Anfrage zu einer echten deutschen Adresse |
| Hintergrundortung der Flyer-Touren | ein Gerät, Telefon in der Tasche, eine echte Runde |
| MetricKit-Absturzberichte | ein Gerät über TestFlight |

Fällt beim Funk-Abgleich etwas aus, sind die beiden ersten Verdächtigen die Berechtigung fürs
lokale Netzwerk und die Frage, ob beide Geräte wirklich im selben Netz hängen — **nicht** der
Team-Schlüssel. Der Hinweis nach 25 Sekunden Stille in `NearbyAbgleich` sagt genau das.

**Berichtigung an dieser Stelle:** Hier stand früher, der Handywechsel sei „auf iOS unnötig, weil
alles mit dem iCloud-Backup mitwandert". Das stimmt für den Regelfall und war trotzdem die
falsche Entscheidung — es setzt voraus, dass iCloud-Backup an ist, genug Platz hat und das alte
Gerät noch läuft. Der Umzug ist inzwischen gebaut und ist geräteseitig unabhängig von Apple.

### 5.5 Baugleich, aber mit anderen Zahlen als Android

Zwei Stellen lösen dasselbe Problem wie Android, mit einem eigenen, nicht abgeschriebenen Wert —
das ist keine Lücke, aber wer Verhalten zwischen den Plattformen vergleicht, sollte es kennen.

**Flyer-Tour-Aufzeichnung.** Android verlangt eine Positionsgenauigkeit besser als 25 m und einen
Mindestabstand von `max(20 m, Genauigkeit × 1.5)` zwischen zwei Wegpunkten, abgefragt alle 8
Sekunden über einen Vordergrunddienst. iOS hat keinen Dienst, den es am Leben halten könnte —
`CLLocationManager` liefert im Hintergrund, solange „Immer" erlaubt ist, und der Takt bestimmt
das System. Der Ausreißer-Filter lässt hier bis 100 m Ungenauigkeit durch (Android: 25 m) und der
Mindestabstand steht fest bei 20 m, ohne Genauigkeits-Skalierung (`TourAufzeichnung.swift`,
`mindestabstandMeter`/`nimmAuf`). Die maximale Dauer von 5 Stunden ist dagegen identisch
übernommen. Ob die lockereren Werte im Feld zu unruhigeren Strecken führen als auf Android, ist
ungeprüft — siehe 5.4, echte Hintergrundortung wurde noch auf keinem Gerät erprobt.

**Sozialdaten-Bewegungsschwelle.** Android bricht eine laufende Zensus-Abfrage erst ab, wenn sich
der Mittelpunkt um `SOCIAL_CENTER_MIN_MOVE_METERS = 80` Meter bewegt hat — ohne diese Schwelle
brach jede Mikrobewegung der Karte die 15-Sekunden-Abfrage ab und im Panel standen dauerhaft
veraltete Werte (Android-`PROJEKTKONTEXT.md`, Abschnitt 5). iOS löst dasselbe Problem anders, nicht
schlechter: Die Koordinate im Abfrageschlüssel wird auf drei Nachkommastellen gerundet
(`SozialdatenView.swift`, `aufrufSchluessel` — bei diesem Breitengrad rund 100 m), und SwiftUIs
`.task(id:)` bricht die alte Abfrage beim Schlüsselwechsel automatisch ab. Kein eigener Debounce
nötig, aber auch keine baugleiche Zahl.

### 5.6 Wahldaten — im Aufbau, in vier Teilen

Auf Android ein eigenständiges Feature (`feature/wahldaten/`, ~1450 Zeilen): amtliche
Wahlergebnisse — Bundestags-, Landtags-, Kreistags- und Kommunalwahl, von der Bundeswahlleiterin
bzw. den Landeswahlleitungen — für den Wahlkreis unter der Kartenmitte, mit Wahlbeteiligung und
Parteianteilen als eigener Chip im Kartenbildschirm (`WahldatenPanel.kt`,
`ModernPosterMapScreen.kt`), im selben Stil wie die Sozialdaten. Bis vor Kurzem existierte davon
auf iOS **nichts** — keine Datei, kein Screen, kein Menüpunkt. Anders als die übrigen Lücken in
diesem Abschnitt war das kein übersehener Rest und keine Plattformgrenze, sondern ein eigener
Port, der jetzt läuft.

**Design-Entscheidung, bewusst getroffen statt der naheliegenden Abkürzung:** iOS hat auf der
Karte selbst gar kein Sozialdaten-Panel — `SozialdatenView` ist dort ein eigener
Vollbildschirm, an den aktuellen GPS-Standort gebunden, nicht an die Kartenmitte. Die kleinere,
billigere Option wäre gewesen, Wahldaten als dritte Quelle in genau diesen Screen zu hängen. Die
Entscheidung fiel stattdessen für echte Verhaltensgleichheit mit Android: ein Panel direkt auf
`PosterMapView`, live bei Kartenbewegung aktualisiert — man kann damit einen Wahlkreis
nachschlagen, ohne dort zu stehen, genau wie drüben. Mehr Bauaufwand, aber keine stille
Funktionsminderung gegenüber Android.

**Vier Teile, je ein eigener PR** (Reihenfolge nach Testbarkeit — erst, was ganz ohne Netzwerk und
Oberfläche prüfbar ist, zuletzt die Oberfläche, die laut Abschnitt 9 ohnehin nur lesend geprüft
werden kann):

1. **Kern** — Modelle, Geometrie (Ray-Casting, Zero-Padding-Fix für Wahlkreis-Kennungen), der
   gemeinsame Ergebnisdatei-Parser, Kleinparteien-Bündelung, die 299 Bundeswahlkreis-Umrisse als
   Package-Ressource, dazu 35 Tests. `WahldatenModels.swift`, `WahldatenGeometrie.swift`,
   `LandtagJsonParser.swift`, `WahldatenParser.swift`, `WahlkreisGrenzen.swift`.
2. **Netzwerk und Repository** — `URLSession`-Abruf der Ergebnisdatei mit Festplatten-Cache,
   Overpass-Abfrage für Kreis-/Gemeindeschlüssel (mit einem neuen, app-weiten Ratenbegrenzer —
   `Gemeindegrenze` in `PosterMapView.swift` ist bislang der einzige Overpass-Aufrufer und läuft
   ungebremst), Dispatch je Wahlart samt Hamburg-Kommunal-Fallback auf Landtag.
3. **Oberfläche** — Toolbar-Toggle auf `PosterMapView` neben dem bestehenden
   „Gemeindegrenze"-Toggle, Panel mit Wahlart-Chip-Reihe, Beteiligung, Parteiliste, Einstellungen
   für Cache-Dauer und „alle Parteien anzeigen", Quellenangabe unter „Lizenzen und Dank".
4. **Verifikation** — `swift test`, `xcodebuild` für den Simulator, die sechs bekannten
   Koordinaten aus dem Android-Test als schnellste Prüfung der portierten Geometrie.

Wer hier weiterarbeitet, portiert am besten von `WahldatenRepository.kt`, `WahldatenModels.kt`
und `WahldatenGeometrie.kt` aus — dieselbe Struktur, die auch `SocialData.swift`/
`SozialdatenView.swift` schon als Vorlage diente, plus `Gemeindegrenze` in `PosterMapView.swift`
als Vorbild für ein kartenbewegungs-getriebenes Panel.

---

## 6. Prüfen

```bash
swift build && swift test          # Kern, ohne Xcode
xcodegen generate                  # erzeugt das Xcode-Projekt aus project.yml
xcodebuild -scheme PlakatKompass -destination 'generic/platform=iOS Simulator' build
```

146 Tests. Darunter:

- **Testvektoren**, die dieselben Dateien lesen wie die Kotlin-Tests. Erzeugt werden sie von
  `Tools/testvektor_bauen.py` — bewusst in Python, damit weder Kotlin noch Swift sich selbst
  bestätigt.
- **`SyncBundleAbwehrTests`** — was ein bösartiges Paket versucht: Pfade mit `..`, absolute Pfade,
  Zip-Bomben, falsche Teamzugehörigkeit.

Die CI läuft auf `macos-15` (GitHub-Hardware, kein selbst gehosteter Runner) und prüft zusätzlich,
dass `PrivacyInfo.xcprivacy` und die richtigen `Info.plist`-Schlüssel **im gebauten Bundle**
landen — nicht bloß im Quellbaum.

---

## 7. Fallen, die schon einmal Zeit gekostet haben

**Ein iPhone verrät seinen Namen nicht.** `UIDevice.current.name` liefert seit iOS 16 ohne
Sonderberechtigung nur noch das Modell — also „iPhone", für jedes Gerät dasselbe. Der Gerätename
wurde daraufhin nur im Weg „allein loslegen" gesetzt; wer per QR beitrat oder ein Team gründete,
hieß dauerhaft „iPhone": in der Geräteliste, im Verlauf jedes Plakats, in der Spalte „erfasst von"
des amtlichen Exports und im Endpunktnamen des Funk-Abgleichs. Bei drei iPhones im Team konnte die
Teamleitung nicht mehr erkennen, welches Gerät sie freigibt oder sperrt. Der Kern konnte den Namen
die ganze Zeit übernehmen (`beigetreten(mit:eigenerName:)`) — die Oberfläche gab ihn nur nie mit.
Auf Android fällt das nicht auf, weil dort `Build.MODEL` und der Nutzername verfügbar sind. Der
Name wird jetzt im Einstieg abgefragt und ist unter „Einstellungen" änderbar.

**XcodeGen überschreibt die `Info.plist`.** Ein `info:`-Block in `project.yml` *erzeugt* die Datei
am angegebenen Pfad und überschreibt eine eingecheckte. Das ist wochenlang unbemerkt geblieben:
Der Build war grün, aber im Bundle landeten nur zwei Schlüssel. Die App wäre beim ersten Foto
abgestürzt (keine Verwendungsbeschreibung) und der Android-iOS-Abgleich wäre tot gewesen (kein
`CFBundleDocumentTypes`). Richtig ist `INFOPLIST_FILE` plus `GENERATE_INFOPLIST_FILE: NO`, und die
Datei aus `sources` ausschließen. Ein CI-Schritt prüft das Ergebnis jetzt im gebauten Bundle.

**Der SwiftUI-Typprüfer gibt auf.** „unable to type-check this expression in reasonable time" ist
kein Fehler im Code, sondern ein zu großer `body`. Abhilfe: in `@ViewBuilder`-Eigenschaften
zerlegen. `Stepper` in der Beschriftungs-Closure-Form schreiben.

**`@StateObject` stirbt mit seiner Ansicht.** Was einen Bildschirm überleben muss, gehört auf
App-Ebene. Siehe Abschnitt 2.

**Pfadprüfung beim Entpacken.** Android fängt `..` erst eine Stufe später über eine
Kanonisierung des Zielpfads ab. Swift hat diese zweite Stufe nicht, deshalb schließt
`isSafeFileName` `.` und `..` ausdrücklich aus. Über dem erlaubten Zeichensatz
`[a-zA-Z0-9._-]` — kein Schrägstrich darin — ist das vollständig.

**Ein Formular nach einem Fehler zu leeren ist grausam.** `speichere()` leerte Foto und Felder in
jedem Fall. Wer beim Speichern einen Fehler bekam, stand mit einer Meldung da und **ohne Foto**,
mitten auf der Straße. Geleert wird jetzt nur bei Erfolg — und Art und Abnahmefrist bleiben auch
dann stehen, weil das nächste Plakat meistens dasselbe an der nächsten Laterne ist.

**Ein Kommentar, der dem Code widerspricht, ist schlimmer als keiner.** Der `onDisappear`-Fehler
oben war nur zu finden, weil ein Kommentar behauptete, die Aufzeichnung laufe weiter. Sie tat es
nicht.

---

## 8. Wie in diesem Repo gearbeitet wird

**Sprache.** Bezeichner in `App/` sind überwiegend deutsch (`TourAufzeichnung`, `merkeWegpunkt`,
`istEingerichtet`), in `PlakatKompassCore` an den Android-Namen orientiert, damit sich die beiden
Fassungen vergleichen lassen. Kommentare und Commit-Nachrichten deutsch, und sie erklären das
*Warum*.

**Zielbranch ist `main`.** PRs werden als Draft geöffnet; **der Nutzer merged selbst**.

**Lizenz: AGPL-3.0.** Gleich wie im Android-Repo. Die Nennung fremder Bestandteile steht unter
„Einstellungen" → „Lizenzen und Dank". Auf der Karte ist keine eigene Namensnennung nötig:
MapKit setzt seinen Hinweis selbst. Overpass (OpenStreetMap, ODbL) und die Sozialdaten
(Datenlizenz Deutschland – Namensnennung 2.0) müssen dagegen genannt werden — beides wird
abgefragt, auch wenn die Karte von Apple kommt.

**Die `ponytail`-Skill gilt hier ebenso.** Einfachste tragfähige Lösung: erst prüfen, ob es die
Sache überhaupt braucht, dann was schon im Code liegt, dann Standardbibliothek, dann
Plattformfunktion, dann vorhandene Abhängigkeit, erst zuletzt neuer Code. Deshalb gibt es genau
**eine** Abhängigkeit: ZIPFoundation (MIT).

---

## 9. Wenn du hier etwas ändern sollst

1. **Lies das README**, bevor du am Abgleich arbeitest. Das Format ist dort byteweise beschrieben.
2. **Ändere `PRSYNC2` nur in beiden Repos gleichzeitig**, sonst können Android und iOS einander
   nicht mehr lesen. Die Testvektoren fangen den Bruch — aber nur, wenn du sie laufen lässt.
3. **Beim Portieren einer Android-Änderung: such nach *allen* Aufrufstellen**, nicht nach der
   einen im Ticket. Der Fristen-Fehler oben entstand genau so.
4. **Die Oberfläche hat keine Tests** und wird von der CI nur übersetzt. Was dort passiert, musst
   du lesend prüfen — beide bisher gefundenen Oberflächenfehler lagen dort.
5. **Hinterlasse für nicht-triviale Logik genau eine laufende Prüfung.** Ein Test, der eine
   Konstante gegen ihr eigenes Literal prüft, ist keiner.
