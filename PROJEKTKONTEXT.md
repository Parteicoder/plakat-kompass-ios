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

Stand dieses Dokuments: 30. Juli 2026, Basis `main` bei Commit `dafe28f`.

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
| Team-QR und Beitritt | `TeamInvite.swift`, `TeamView.swift` |
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

## 5. Was Android kann und diese Fassung nicht

Das README führt das aus. Kurz, und mit einer Berichtigung:

**Nearby Connections** — hier stand, es gebe die Schnittstelle auf iOS nicht und werde sie nie
geben. Das war schlicht falsch, und zwar in beiden Hälften: Google liefert Nearby Connections als
Swift-Paket, und der Abgleich zwischen Android und iOS ist ausdrücklich vorgesehen. Er ist in
`App/NearbyAbgleich.swift` gebaut. Was bleibt, ist eine kleinere Einschränkung als behauptet:
Zwischen den Plattformen trägt nur das WLAN, nicht Bluetooth oder Wi-Fi Direct — beide Geräte
müssen also im selben Netz sein, notfalls über den Hotspot eines der beiden. Für den netzlosen
Fall bleibt das Sync-Paket als Datei über den Teilen-Dialog.

**Offline-Kacheln** — MapKit gibt seinen Kachelspeicher nicht heraus. Offlinekarten sind auf iOS
seit 17 Systemfunktion.

**Handywechsel-Backup (`PRBACKUP2`)** — auf iOS unnötig, weil alles unter „Application Support"
liegt und mit dem iCloud-Backup mitwandert.

**Relay-Abgleich** — hier ist das README ungenau: Es liest sich so, als fehle nur die
iOS-Anbindung. Tatsächlich hat **auch Android keinen Relay-Client**;
`grep -rl "relay" app/src/main/java` im Android-Repo findet nichts. Das Backend-Repository
existiert, aber es ist an keine der beiden Apps angebunden. Wer das angeht, fängt auf beiden
Seiten bei null an.

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
