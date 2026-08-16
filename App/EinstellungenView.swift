import AVFoundation
import CoreLocation
import PlakatKompassCore
import SwiftUI
import UIKit
import UserNotifications

/// Einstellungen. Gegenstück zum Bereich „Mehr" auf Android — auf das reduziert, was auf iOS
/// überhaupt in einer App einstellbar ist.
///
/// Vieles, was drüben hier steht, gehört auf iOS in die Systemeinstellungen: Berechtigungen für
/// Kamera, Ort und Meldungen lassen sich nicht in der App umschalten. Sie hier nachzubauen hieße,
/// Schalter zu zeigen, die nichts tun. Stattdessen führt ein Verweis dorthin.
struct EinstellungenView: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage(Kurzanleitung.schluessel) private var anleitungGesehen = ""

  @AppStorage(Darstellung.schluessel) private var darstellung = Darstellung.system.rawValue
  @AppStorage(SozialdatenCache.tageSchluessel) private var sozialCacheTage = SozialdatenCache
    .vorgabeTage
  @AppStorage("wahldatenCacheTage") private var wahldatenCacheTage =
    WahldatenEinstellungen.vorgabeTage
  @AppStorage("wahldatenAlleParteien") private var wahldatenAlleParteien = false
  @State private var wahldatenCacheBytes: Int64 = 0
  /// Die Zahl der Einträge ist kein @Published — der Cache ist absichtlich kein
  /// ObservableObject, sonst zeichnete jede Antwort im Hintergrund die Oberfläche neu.
  /// Beim Erscheinen einmal abfragen genügt.
  @State private var cacheEintraege = 0
  @AppStorage("pausenErinnerung") private var pausenErinnerung = false
  @AppStorage("abnahmeErinnerung") private var abnahmeErinnerung = true
  @AppStorage("pausenMinuten") private var pausenMinuten = Erinnerungen.pausenVorgabeMinuten
  @State private var meldungenErlaubt: UNAuthorizationStatus = .notDetermined
  @State private var neuerName = ""

  // Die Abschnitte stehen einzeln, nicht als ein grosses `body`.
  //
  // Nicht aus Ordnungsliebe: Bei allem in einem Ausdruck gibt Swifts Typprüfer auf --
  // "unable to type-check this expression in reasonable time". Die Meldung nennt nur die Zeile
  // mit `body` und sagt nicht, welcher Teil zu viel war. Kleine Abschnitte sind die Loesung
  // UND die Vorbeugung.
  var body: some View {
    List {
      darstellungAbschnitt
      pausenAbschnitt
      berechtigungenAbschnitt
      geraeteAbschnitt
      kurzanleitungAbschnitt
      sozialdatenAbschnitt
      wahldatenAbschnitt
      unterstuetzenAbschnitt
      Section {
        // Der Verlauf ist die einzige Stelle, an der nachvollziehbar wird, wer wann was
        // geaendert hat - wichtig, wenn im Team Unklarheit ueber ein Plakat entsteht.
        NavigationLink("Verlauf") { VerlaufView() }
        NavigationLink("Experten") { ExpertenView() }
        NavigationLink("Lizenzen und Dank") { LizenzenView() }
      }
    }
    .navigationTitle("Einstellungen")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      meldungenErlaubt = await UNUserNotificationCenter.current().notificationSettings()
        .authorizationStatus
    }
    // Das Feld startet mit dem aktuellen Namen, statt leer. Ein leeres Feld sähe aus, als
    // gäbe es keinen Namen — und lüde dazu ein, versehentlich einen leeren zu speichern.
    .onAppear {
      if neuerName.isEmpty { neuerName = model.state.deviceName }
      wahldatenCacheBytes = WahldatenRepository.cacheSizeBytes()
    }
    .onChange(of: pausenErinnerung) { _, an in
      Task {
        an ? await Erinnerungen.startePause(minuten: pausenMinuten) : Erinnerungen.beendePause()
      }
    }
    .onChange(of: pausenMinuten) { _, neu in
      guard pausenErinnerung else { return }
      Task { await Erinnerungen.startePause(minuten: neu) }
    }
    .onChange(of: abnahmeErinnerung) { _, _ in
      Task { await Erinnerungen.planeNeu(fuer: model.state) }
    }
  }

  /// Die Kurzanleitung noch einmal von vorn.
  ///
  /// Der Zähler ist nicht Zierrat: Ohne ihn ist nicht zu erkennen, ob der Knopf etwas getan
  /// hat — die Erklärungen erscheinen ja erst beim nächsten Öffnen eines Bereichs, also
  /// irgendwann später und woanders.
  @ViewBuilder private var kurzanleitungAbschnitt: some View {
    let gesehen = Kurzanleitung.anzahlGesehen(anleitungGesehen)
    Section {
      Button {
        anleitungGesehen = ""
        model.meldung = "Die Kurzanleitung erscheint wieder in jedem Bereich."
      } label: {
        Label("Kurzanleitung erneut zeigen", systemImage: "graduationcap")
      }
      .disabled(gesehen == 0)
    } header: {
      Text("Kurzanleitung")
    } footer: {
      Text(
        gesehen == 0
          ? "Noch kein Bereich erklärt — die Anleitung erscheint von selbst, sobald du einen öffnest."
          : "\(gesehen) von \(Kurzanleitung.bereiche.count) Bereichen gesehen. Danach erscheint "
            + "die Erklärung wieder, sobald du einen Bereich öffnest.")
    }
  }

  @ViewBuilder private var darstellungAbschnitt: some View {
    Section {
      Picker("Erscheinungsbild", selection: $darstellung) {
        ForEach(Darstellung.allCases) { fall in
          Text(fall.beschriftung).tag(fall.rawValue)
        }
      }
      .pickerStyle(.segmented)
    } header: {
      Text("Darstellung")
    } footer: {
      Text(
        """
        „Automatisch" folgt der Einstellung des iPhones. Hell und Dunkel gelten nur für \
        diese App — wer nachts plakatiert, kann sie dunkel stellen, ohne das ganze Telefon \
        umzustellen.
        """)
    }
  }

  @ViewBuilder private var sozialdatenAbschnitt: some View {
    Section {
      Stepper(value: $sozialCacheTage, in: SozialdatenCache.minTage...SozialdatenCache.maxTage) {
        Text(
          sozialCacheTage == 0
            ? "Nicht zwischenspeichern"
            : sozialCacheTage == 1 ? "1 Tag behalten" : "\(sozialCacheTage) Tage behalten")
      }
      Button(role: .destructive) {
        SozialdatenCache.geteilt.leeren()
        cacheEintraege = 0
      } label: {
        LabeledContent("Zwischenspeicher leeren") {
          Text(cacheEintraege == 1 ? "1 Antwort" : "\(cacheEintraege) Antworten")
        }
      }
      .disabled(cacheEintraege == 0)
    } header: {
      Text("Sozialdaten")
    } footer: {
      Text(
        """
        Die Zahlen aus Zensus und Regionalatlas ändern sich jährlich — eine Woche alte \
        Werte sind so gültig wie frisch geholte. Der Zwischenspeicher spart die Wartezeit \
        und schont einen Server, den die Statistischen Ämter kostenlos bereitstellen. \
        Auf **0 Tage** wird nichts behalten und jede Abfrage neu gestellt.
        """)
    }
    .onAppear { cacheEintraege = SozialdatenCache.geteilt.anzahl }
  }

  @ViewBuilder private var wahldatenAbschnitt: some View {
    Section {
      Stepper(
        value: $wahldatenCacheTage,
        in: WahldatenEinstellungen.minTage...WahldatenEinstellungen.maxTage
      ) {
        Text(
          wahldatenCacheTage == 0
            ? "Nicht zwischenspeichern"
            : wahldatenCacheTage == 1
              ? "1 Tag behalten" : "\(wahldatenCacheTage) Tage behalten")
      }
      Toggle("Alle Parteien einzeln anzeigen", isOn: $wahldatenAlleParteien)
      Button(role: .destructive) {
        WahldatenRepository.clearCache()
        wahldatenCacheBytes = 0
      } label: {
        LabeledContent("Zwischenspeicher leeren") {
          Text(ByteCountFormatter.string(fromByteCount: wahldatenCacheBytes, countStyle: .file))
        }
      }
      .disabled(wahldatenCacheBytes == 0)
    } header: {
      Text("Wahldaten")
    } footer: {
      Text(
        "Kleine Parteien werden sonst unter „Sonstige“ zusammengefasst. Die Ergebnisdateien sind amtlich und können mehrere hundert KB groß sein."
      )
    }
  }

  /// Ko-fi — Gegenstück zu `ModernKofiSupportCard.kt`.
  ///
  /// **Ein Link, kein Kaufvorgang.** Apple verlangt seine eigene Bezahlung nur für digitale
  /// Waren *innerhalb* der App; eine Spende an die Entwicklung über einen Browserlink ist
  /// ausdrücklich erlaubt. Deshalb `Link` und nicht StoreKit — und deshalb steht hier auch
  /// nichts von „freischalten" oder „Pro": Die App kann ohne Spende alles.
  @ViewBuilder private var unterstuetzenAbschnitt: some View {
    Section {
      Link(destination: URL(string: "https://ko-fi.com/parteicoder")!) {
        Label("Ko-fi öffnen", systemImage: "cup.and.saucer")
      }
    } header: {
      Text("Unterstützen")
    } footer: {
      Text(
        """
        Plakat Kompass ist freie Software und kostet nichts. Wer die Arbeit daran \
        unterstützen möchte, kann das über Ko-fi tun — an der App ändert sich dadurch \
        nichts, sie kann ohnehin alles.
        """)
    }
  }

  @ViewBuilder private var pausenAbschnitt: some View {
    Section {
      Toggle("An Abnahmefristen erinnern", isOn: $abnahmeErinnerung)
      Toggle("Ans Trinken erinnern", isOn: $pausenErinnerung)
      if pausenErinnerung {
        Stepper(value: $pausenMinuten, in: Erinnerungen.pausenSpanne, step: 15) {
          Text("Alle \(pausenMinuten) Minuten")
        }
      }
    } header: {
      Text("Erinnerungen")
    } footer: {
      Text(
        """
        Wer im Sommer vier Stunden mit Leiter und Kabelbindern unterwegs ist, vergisst das \
        Trinken. Beide Erinnerungen laufen, bis sie hier wieder ausgeschaltet werden.
        """)
    }
  }

  /// Kamera- und Ortungsstatus sind reine Systemwerte, synchron abrufbar — anders als der
  /// Meldungsstatus braucht es dafür kein `.task`.
  private var kameraStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
  private var ortStatus: CLAuthorizationStatus { CLLocationManager().authorizationStatus }

  @ViewBuilder private var berechtigungenAbschnitt: some View {
    Section {
      LabeledContent("Kamera") {
        Text(kameraText)
          .foregroundStyle(kameraStatus == .authorized ? Color.secondary : Color.orange)
      }
      LabeledContent("Ort") {
        Text(ortText)
          .foregroundStyle(
            ortStatus == .authorizedWhenInUse || ortStatus == .authorizedAlways
              ? Color.secondary : Color.orange)
      }
      LabeledContent("Meldungen") {
        Text(meldungenText)
          .foregroundStyle(meldungenErlaubt == .authorized ? Color.secondary : Color.orange)
      }
      Button("Systemeinstellungen öffnen") {
        if let ziel = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(ziel)
        }
      }
    } header: {
      Text("Berechtigungen")
    } footer: {
      Text(
        """
        Kamera, Ort und Meldungen verwaltet iOS. Die App kann sie nicht selbst umschalten — \
        hier geht es direkt zur richtigen Stelle.
        """)
    }
  }

  private var kameraText: String {
    switch kameraStatus {
    case .authorized: return "Erlaubt"
    case .denied, .restricted: return "Verweigert"
    case .notDetermined: return "Noch nicht gefragt"
    @unknown default: return "Unbekannt"
    }
  }

  private var ortText: String {
    switch ortStatus {
    case .authorizedAlways: return "Immer erlaubt"
    case .authorizedWhenInUse: return "Bei App-Nutzung"
    case .denied, .restricted: return "Verweigert"
    case .notDetermined: return "Noch nicht gefragt"
    @unknown default: return "Unbekannt"
    }
  }

  @ViewBuilder private var geraeteAbschnitt: some View {
    Section {
      // Änderbar, nicht nur anzeigbar. Wer beim Beitritt keinen Namen gesetzt hat — oder
      // aus einer älteren Fassung kommt, die gar nicht danach fragte — sitzt sonst
      // dauerhaft als „iPhone" in der Teamliste fest.
      TextField("Name", text: $neuerName)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .onSubmit { model.benenneGeraet(neuerName) }
      if neuerName.trimmingCharacters(in: .whitespacesAndNewlines) != model.state.deviceName {
        Button("Namen übernehmen") { model.benenneGeraet(neuerName) }
          .disabled(neuerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    } header: {
      Text("Dieses Gerät")
    } footer: {
      Text(
        """
        Der Name steht an jedem Plakat, das du erfasst, und in der Geräteliste des Teams. \
        Ein iPhone gibt seinen eigenen Namen nicht heraus — hier ist die einzige Stelle, an \
        der er gesetzt wird.
        """)
    }
    Section {
      LabeledContent("Rolle", value: model.state.role == .LEADER ? "Teamleitung" : "Mitglied")
      LabeledContent("Team", value: model.state.teamName ?? "—")
      LabeledContent("Plakate", value: "\(model.state.posters.count)")
      LabeledContent("Touren", value: "\(model.state.flyerTours.count)")
    }
  }

  private var meldungenText: String {
    switch meldungenErlaubt {
    case .authorized, .provisional, .ephemeral: return "erlaubt"
    case .denied: return "abgelehnt"
    default: return "noch nicht gefragt"
    }
  }
}

/// Wer wann was geändert hat.
private struct VerlaufView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List(model.state.events) { ereignis in
      VStack(alignment: .leading, spacing: 3) {
        Text(ereignis.action).font(.subheadline)
        Text("\(ereignis.actorName) · \(zeit(ereignis.createdAt))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Verlauf")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if model.state.events.isEmpty {
        Text("Noch nichts passiert.").foregroundStyle(.secondary)
      }
    }
  }

  private func zeit(_ millis: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateStyle = .short
    f.timeStyle = .short
    return f.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
  }
}

/// Lizenzen und Dank.
///
/// Zwei Pflichten aus den Daten: Die Gemeindegrenzen stammen aus OpenStreetMap und stehen unter
/// der ODbL, die Namensnennung verlangt. Die Sozialdaten sind amtlich und stehen unter einer
/// Lizenz mit Namensnennung.
///
/// Die Karte selbst braucht hier nichts: Sie läuft über MapKit, und Apple setzt seinen Hinweis
/// samt „Rechtliche Hinweise" von sich aus in die Karte. Das ist der Unterschied zur
/// Android-Fassung, die OSM-Kacheln über osmdroid zeichnet und den Hinweis selbst setzen muss.
///
/// **Hier stand lange nur ZIPFoundation.** Das war falsch, seit der Funk-Abgleich dazukam: Google
/// Nearby Connections trägt ihn vollständig, steht unter Apache 2.0 — und zieht sechs weitere
/// Fremdbibliotheken in die fertige App, die alle Namensnennung verlangen. Die Pflicht dazu kommt
/// aus der Apache-2.0-Lizenz der Bibliothek selbst, unabhängig von der eigenen Lizenz der App —
/// fehlende Namensnennung ist deshalb kein Schönheitsfehler, sondern ein Lizenzverstoss.
///
/// Jeder Eintrag unten ist an der festgenagelten Revision nachgesehen worden, keiner aus dem
/// Gedächtnis: `Package.swift` und `.gitmodules` von `google/nearby` nennen die Abhängigkeiten,
/// die Lizenz stammt jeweils aus der LICENSE-Datei des Projekts selbst.
private struct LizenzenView: View {
  var body: some View {
    List {
      Section {
        LabeledContent("Fassung", value: Fassung.anzeige)
        Text(
          """
          Plakat Kompass ist urheberrechtlich geschützt. Alle Rechte vorbehalten. Die \
          verwendeten Bestandteile Dritter stehen unter ihren eigenen Lizenzen und sind \
          unten aufgeführt.
          """)
      } header: {
        Text("Diese App")
      } footer: {
        // Die Nummer bleibt auch ohne AGPL-Bezug nützlich: Ohne sie weiss der Empfänger
        // eines Fehlerberichts nicht, welche Fassung gemeint ist.
        Text(
          "Die Nummer gehört in jeden Fehlerbericht: Ohne sie lässt sich nicht sagen, ob ein Fehler noch besteht oder längst behoben ist."
        )
      }
      Section("Gemeindegrenzen") {
        Text(
          """
          © OpenStreetMap-Mitwirkende, abgefragt über die Overpass-Schnittstelle. Die Daten \
          stehen unter der Open Database License (ODbL) 1.0.
          """)
      }
      Section("Sozialdaten") {
        Text(
          """
          Regionalatlas Deutschland und Zensus 2022, Statistische Ämter des Bundes und der \
          Länder. Datenlizenz Deutschland – Namensnennung – Version 2.0 (dl-de/by-2-0).
          """)
      }
      Section("Karte") {
        Text("Apple MapKit. Den Kartenhinweis setzt iOS selbst in die Karte.")
      }
      Section {
        Bibliothek("ZIPFoundation", "Thomas Zoechling", "MIT-Lizenz")
        Bibliothek("Nearby Connections", "Google", "Apache-Lizenz 2.0")
      } header: {
        Text("Verwendete Bibliotheken")
      }

      Section {
        Bibliothek("Abseil", "Google", "Apache-Lizenz 2.0")
        Bibliothek("BoringSSL", "Google", "Apache-Lizenz 2.0")
        Bibliothek("Protocol Buffers", "Google", "BSD-Lizenz, 3 Klauseln")
        Bibliothek("UKey2", "Google", "Apache-Lizenz 2.0")
        Bibliothek("JSON for Modern C++", "Niels Lohmann", "MIT-Lizenz")
        Bibliothek("MurmurHash3", "Austin Appleby", "gemeinfrei")
      } header: {
        Text("Mittelbar, über Nearby Connections")
      } footer: {
        Text(
          """
          Diese sechs stehen hier nicht, weil die App sie selbst benutzt, sondern weil \
          Nearby Connections sie mitbringt und sie damit im fertigen Programm landen. \
          Genannt werden müssen sie deshalb genauso.
          """)
      }
      Section("Dank") {
        Text("Malte Steinbach")
      }
    }
    .navigationTitle("Lizenzen und Dank")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Eine Zeile der Lizenzliste. Der Name gross, Urheber und Lizenz klein darunter — bei acht
/// Einträgen ist ein Fliesstext aus Halbsätzen nicht mehr lesbar.
private struct Bibliothek: View {
  let name: String
  let urheber: String
  let lizenz: String

  init(_ name: String, _ urheber: String, _ lizenz: String) {
    self.name = name
    self.urheber = urheber
    self.lizenz = lizenz
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(name)
      Text("\(urheber) · \(lizenz)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
