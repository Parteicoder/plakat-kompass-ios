import MapKit
import PlakatKompassCore
import SwiftUI

struct PosterMapView: View {
  @EnvironmentObject private var model: AppModel
  @StateObject private var netzstatus = Netzstatus.geteilt
  @State private var ausschnitt: MapCameraPosition = .automatic
  @State private var ausgewaehlt: Poster?
  @StateObject private var grenze = Gemeindegrenze()
  @StateObject private var wahldaten = WahldatenAnzeige()
  @AppStorage("grenzeZeigen") private var grenzeZeigen = false
  @AppStorage("wahldatenZeigen") private var wahldatenZeigen = false
  @AppStorage("wahldatenWahlart") private var wahlartRoh = Wahlart.bundestag.rawValue
  @State private var wahldatenEingeklappt = false
  @State private var mitte: CLLocationCoordinate2D?
  @State private var flyerkarte = false
  // Eigene, von PosterFilter GETRENNTE Auswahl — mit voller Absicht, wie schon auf Android
  // (ModernMapStatusFilter dort ist ebenfalls ein zweites Enum, nicht PosterListFilter). Die
  // Karte will eine lückenlose, überschneidungsfreie Dreiteilung für die Chips mit Live-Zahl:
  // jedes Plakat zaehlt zu genau einem Chip. PosterFilter.aktiv dagegen ist bewusst weit
  // ("nicht entfernt") und überschneidet sich mit .probleme — richtig für Liste/Start, falsch
  // für einen Chip, dessen Zahlen sich zur Gesamtmenge aufaddieren sollen.
  @State private var kartenFilter: Set<KartenStatusFilter> = []
  @State private var suchtext = ""
  @State private var suchfehler: String?

  /// Auf der Flyerkarte gibt es keine Plakate — dort soll allein der gelaufene Weg zu sehen
  /// sein. Sonst liegen Marker über dem Balken und man sieht die Strasse nicht mehr.
  ///
  /// Keine Auswahl heißt „alles zeigen", genau wie bei den Chips auf Android.
  private var sichtbare: [Poster] {
    guard !flyerkarte else { return [] }
    guard !kartenFilter.isEmpty else { return model.state.posters }
    return model.state.posters.filter { plakat in kartenFilter.contains { $0.passt(plakat) } }
  }

  /// Touren mit mindestens einem Wegpunkt. Die eigene gerade gestartete ist am Anfang leer und
  /// hat dann nichts zu zeichnen.
  private var touren: [FlyerTour] {
    model.state.flyerTours.filter { !$0.points.isEmpty }
  }

  /// Mintgrün wie der Sozialdaten-Kreis der Android-Fassung, damit die Flyerkarte auf beiden
  /// Geräten gleich aussieht.
  private static let mint = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)

  var body: some View {
    NavigationStack {
      Map(position: $ausschnitt) {
        if grenzeZeigen, let umriss = grenze.grenze {
          ForEach(Array(umriss.lines.enumerated()), id: \.offset) { _, linie in
            MapPolyline(
              coordinates: linie.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
              }
            )
            .stroke(Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.75), lineWidth: 3)
          }
        }
        if wahldatenAktiv,
          case .success(_, _, let flaeche?) = wahldaten.zustand
        {
          ForEach(Array(flaeche.ringe.enumerated()), id: \.offset) { _, ring in
            let punkte = stride(from: 0, to: ring.count - 1, by: 2).map {
              CLLocationCoordinate2D(latitude: ring[$0 + 1], longitude: ring[$0])
            }
            MapPolyline(coordinates: punkte)
              .stroke(.purple.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
          }
        }
        if flyerkarte {
          ForEach(touren) { tour in
            let punkte = tour.points.map {
              CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            let formen = FlyerZeichnung.formenAnzahl(punkte: punkte.count)
            if formen >= 1, let start = punkte.first {
              // Der Startkreis kommt ab dem ERSTEN Punkt. Siehe FlyerZeichnung:
              // Ohne ihn sieht eine frisch gestartete Tour aus wie ein Fehler.
              MapCircle(center: start, radius: FlyerZeichnung.startKreisRadius)
                .foregroundStyle(Self.mint.opacity(FlyerZeichnung.deckkraft))
            }
            if formen >= 2 {
              MapPolyline(coordinates: punkte)
                .stroke(
                  Self.mint.opacity(FlyerZeichnung.deckkraft),
                  style: StrokeStyle(
                    lineWidth: FlyerZeichnung.balkenBreite,
                    lineCap: .round,
                    lineJoin: .round
                  )
                )
            }
          }
        }
        ForEach(sichtbare) { plakat in
          Annotation(
            plakat.addressHint.isEmpty ? plakat.status.beschriftung : plakat.addressHint,
            coordinate: CLLocationCoordinate2D(
              latitude: plakat.latitude, longitude: plakat.longitude)
          ) {
            Button {
              ausgewaehlt = plakat
            } label: {
              Circle()
                .fill(plakat.status.farbe)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .shadow(radius: 2)
            }
          }
        }
        UserAnnotation()
      }
      .mapControls {
        MapUserLocationButton()
        MapCompass()
      }
      .onMapCameraChange(frequency: .onEnd) { kontext in
        mitte = kontext.region.center
      }
      .task(id: grenzeSchluessel) {
        guard grenzeZeigen, let punkt = mitte else { return }
        await grenze.hole(latitude: punkt.latitude, longitude: punkt.longitude)
      }
      .task(id: wahldatenSchluessel) {
        guard wahldatenAktiv, let punkt = mitte else { return }
        await wahldaten.lade(
          longitude: punkt.longitude, latitude: punkt.latitude, wahlart: wahlart
        )
      }
      .navigationTitle("Karte")
      .navigationBarTitleDisplayMode(.inline)
      // Adresssuche ueber CLGeocoder - Apple kann das, eine eigene Suche waere Aufwand
      // ohne Zweck. .searchable liefert das Feld samt Tastaturverhalten von selbst.
      .searchable(text: $suchtext, prompt: "Adresse suchen")
      .onSubmit(of: .search) { springeZurAdresse() }
      .alert("Adresse nicht gefunden", isPresented: .constant(suchfehler != nil)) {
        Button("OK") { suchfehler = nil }
      } message: {
        Text(suchfehler ?? "")
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Toggle(isOn: $wahldatenZeigen) {
            Label("Wahldaten", systemImage: "chart.bar")
          }
          .toggleStyle(.button)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Toggle(isOn: $flyerkarte) {
            Label("Flyerkarte", systemImage: "figure.walk")
          }
          .toggleStyle(.button)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Toggle(isOn: $grenzeZeigen) {
            Label("Gemeindegrenze", systemImage: "map")
          }
          .toggleStyle(.button)
        }
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          // Auf der Flyerkarte gibt es nichts zu filtern - dort liegen keine Plakate.
          if !flyerkarte {
            StatusfilterChips(posters: model.state.posters, ausgewaehlt: $kartenFilter)
          }
          if grenzeZeigen, let name = grenze.grenze?.name {
            Text(name)
              .font(.footnote.weight(.medium))
              .padding(.horizontal, 12).padding(.vertical, 6)
              .background(.thinMaterial, in: Capsule())
          }
          // Ohne Internet kommen keine neuen Kartenkacheln - die Karte bliebe grau oder zeigte
          // nur, was schon im Zwischenspeicher liegt, und sähe aus wie ein Fehler der App statt
          // eines fehlenden Netzes. Ein Satz erspart die Fehlersuche an der falschen Stelle.
          if !netzstatus.verfuegbar {
            Text("Kein Internet: Es werden nur bereits geladene Kartenteile angezeigt.")
              .font(.footnote.weight(.medium))
              .padding(.horizontal, 12).padding(.vertical, 6)
              .background(.thinMaterial, in: Capsule())
              .foregroundStyle(.orange)
          }
        }
        .padding(.top, 8)
      }
      .sheet(item: $ausgewaehlt) { plakat in
        PlakatDetail(plakat: plakat)
          .presentationDetents([.medium])
      }
      .overlay(alignment: .bottom) {
        if wahldatenAktiv {
          WahldatenPanel(
            zustand: wahldaten.zustand,
            wahlart: wahlart,
            eingeklappt: wahldatenEingeklappt,
            onWahlart: {
              wahlartRoh = $0.rawValue
              wahldatenEingeklappt = false
            },
            onErneut: {
              guard let punkt = mitte else { return }
              Task {
                await wahldaten.lade(
                  longitude: punkt.longitude, latitude: punkt.latitude,
                  wahlart: wahlart, erzwingen: true
                )
              }
            },
            onEinklappen: { wahldatenEingeklappt.toggle() },
            onSchliessen: { wahldatenZeigen = false }
          )
          .padding(.horizontal, 12).padding(.bottom, 8)
        } else if flyerkarte && touren.isEmpty {
          Text(
            "Noch keine Flyer-Tour mit Wegpunkten. Unter „Start\u{201C} lässt sich eine aufzeichnen."
          )
          .font(.footnote)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 14).padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.horizontal, 24).padding(.bottom, 20)
        } else if !flyerkarte && sichtbare.isEmpty {
          Text(
            model.state.posters.isEmpty
              ? "Noch keine Plakate auf der Karte."
              : "Kein Plakat passt zu den gewählten Chips."
          )
          .font(.footnote)
          .padding(.horizontal, 14).padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.bottom, 20)
        }
      }
    }
  }
}

extension PosterMapView {
  /// Springt an die eingetippte Adresse.
  ///
  /// Der Ausschnitt ist bewusst eng (600 m): Wer eine Adresse sucht, will die Strasse sehen und
  /// nicht die Stadt. Findet der Geocoder nichts, sagt die App das - stiller Stillstand waere
  /// hier das Schlimmste, weil man nicht weiss, ob die Suche laeuft oder nichts fand.
  @MainActor fileprivate func springeZurAdresse() {
    let anfrage = suchtext.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !anfrage.isEmpty else { return }
    Task {
      guard let treffer = try? await CLGeocoder().geocodeAddressString(anfrage),
        let ort = treffer.first?.location?.coordinate
      else {
        suchfehler = "Zu „\(anfrage)\u{201C} wurde nichts gefunden."
        return
      }
      ausschnitt = .region(
        MKCoordinateRegion(
          center: ort,
          latitudinalMeters: 600,
          longitudinalMeters: 600
        ))
    }
  }

  /// Grob gerundet, weil eine Gemeinde größer ist als 100 Meter: Ohne das Runden löst jedes
  /// Verschieben der Karte eine neue Overpass-Abfrage aus.
  fileprivate var grenzeSchluessel: String {
    guard grenzeZeigen, let punkt = mitte else { return "aus" }
    return String(format: "%.2f|%.2f", punkt.latitude, punkt.longitude)
  }

  fileprivate var wahlart: Wahlart { Wahlart(rawValue: wahlartRoh) ?? .bundestag }
  fileprivate var wahldatenAktiv: Bool { wahldatenZeigen && !flyerkarte }

  fileprivate var wahldatenSchluessel: String {
    guard wahldatenAktiv, let punkt = mitte else { return "aus" }
    return String(format: "%@|%.2f|%.2f", wahlart.rawValue, punkt.latitude, punkt.longitude)
  }
}

/// Holt den Grenzverlauf von Overpass.
///
/// Overpass ist ein von Freiwilligen betriebener Dienst ohne Schlüssel und ohne Rechnung. Deshalb
/// wird gerundet zwischengespeichert und nur auf Wunsch abgefragt — nicht bei jedem Öffnen der
/// Karte.
@MainActor
final class Gemeindegrenze: ObservableObject {
  @Published private(set) var grenze: CommuneBoundary?

  private var zwischenspeicher: [String: CommuneBoundary?] = [:]

  func hole(latitude: Double, longitude: Double) async {
    let schluessel = String(format: "%.2f,%.2f", latitude, longitude)
    if let vorhanden = zwischenspeicher[schluessel] {
      grenze = vorhanden
      return
    }

    // Erst Gemeinde/Kreis (Ebene 6/8) versuchen; kommt dort nichts zurueck, das Bundesland
    // (Ebene 4). Berlin, Hamburg und Bremen sind Stadtstaaten - ein Land fuer sich, ohne eigene,
    // von der Landesgrenze getrennte Gemeindegrenze. Ohne diesen zweiten Versuch bliebe die Karte
    // dort ohne Umriss. Gegenstueck zu CommuneBoundaryClient.fetch() auf Android.
    var gefunden = await frage(ebenen: CommuneBoundaryQuery.ebenenGemeinde, latitude: latitude, longitude: longitude)
    if gefunden == nil {
      gefunden = await frage(ebenen: CommuneBoundaryQuery.ebenenBundesland, latitude: latitude, longitude: longitude)
    }

    zwischenspeicher[schluessel] = gefunden
    grenze = gefunden
  }

  /// Ein einzelner Overpass-Abruf fuer eine `admin_level`-Ebene. `nil` bei jedem Fehlschlag -
  /// fehlender URL, HTTP-Fehler oder einer Antwort ohne passende Verwaltungsebene -, damit
  /// `hole()` unabhaengig vom Grund auf die naechste Ebene ausweichen kann.
  private func frage(ebenen: String, latitude: Double, longitude: Double) async -> CommuneBoundary? {
    guard
      let ziel = URL(string: CommuneBoundaryQuery.url(latitude: latitude, longitude: longitude, ebenen: ebenen))
    else { return nil }

    let anfrage: URLRequest = {
      var anfrage = URLRequest(url: ziel)
      anfrage.timeoutInterval = 30
      anfrage.setValue("PlakatKompass/1.0 (iOS; Gemeindegrenzen)", forHTTPHeaderField: "User-Agent")
      anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
      return anfrage
    }()

    // Scheitert die Abfrage, bleibt die Karte einfach ohne Grenze. Eine Fehlermeldung waere
    // hier fehl am Platz - die Grenze ist eine Zugabe, keine Voraussetzung.
    //
    // Ueber OverpassSchlange: seit die Wahldaten-Gebietssuche denselben Dienst aufruft, gibt
    // es zwei unabhaengige Aufrufer - ohne die gemeinsame Warteschlange koennten sie sich bei
    // einem Kartenschwenk gegenseitig in eine Drosselung laufen lassen.
    guard
      let (daten, antwort) = await OverpassSchlange.geteilt.nacheinander({
        try? await URLSession.shared.data(for: anfrage)
      }),
      let http = antwort as? HTTPURLResponse, (200...299).contains(http.statusCode)
    else { return nil }

    return CommuneBoundaryQuery.parse(String(decoding: daten, as: UTF8.self))
  }
}

/// Die drei Karten-Chips. Gegenstück zu `ModernMapStatusFilter.kt` — bewusst ein eigenes Enum statt
/// `PosterFilter`, siehe die Erklärung an `kartenFilter` in `PosterMapView`. Dieselbe Dreiteilung
/// steht schon in `PosterStatus.farbe`, hier nur um Titel und eine Mitgliedsprüfung ergänzt.
private enum KartenStatusFilter: CaseIterable, Hashable {
  case aktiv, ok, probleme

  var titel: String {
    switch self {
    case .aktiv: return "Aktiv"
    case .ok: return "OK"
    case .probleme: return "Probleme"
    }
  }

  var farbe: Color {
    switch self {
    case .aktiv: return Farben.blau
    case .ok: return Farben.gruen
    case .probleme: return Farben.rot
    }
  }

  func passt(_ plakat: Poster) -> Bool {
    switch self {
    case .aktiv: return plakat.status == .HANGING || plakat.status == .REPLACED
    case .ok: return plakat.status == .CHECKED
    case .probleme: return plakat.status == .DAMAGED || plakat.status == .MISSING
    }
  }
}

/// Kompakte, halbdurchsichtige Chip-Reihe mit Live-Zahl je Status. Gegenstück zu `Statusfilter` +
/// `StatusFilterChip` aus `ModernMapOverlay.kt`. Mehrfachauswahl: keine Auswahl zeigt alles,
/// jeder angetippte Chip schränkt weiter ein.
private struct StatusfilterChips: View {
  let posters: [Poster]
  @Binding var ausgewaehlt: Set<KartenStatusFilter>

  var body: some View {
    HStack(spacing: 8) {
      ForEach(KartenStatusFilter.allCases, id: \.self) { chip in
        let gewaehlt = ausgewaehlt.contains(chip)
        let anzahl = posters.filter { chip.passt($0) }.count
        Button {
          if gewaehlt { ausgewaehlt.remove(chip) } else { ausgewaehlt.insert(chip) }
        } label: {
          HStack(spacing: 6) {
            Circle().fill(chip.farbe).frame(width: 8, height: 8)
            Text("\(chip.titel): \(anzahl)")
              .font(.subheadline.weight(gewaehlt ? .bold : .medium))
          }
          .padding(.horizontal, 12).padding(.vertical, 7)
          .background(
            gewaehlt ? chip.farbe.opacity(0.16) : Color(.systemBackground).opacity(0.8),
            in: Capsule()
          )
          .overlay(Capsule().strokeBorder(gewaehlt ? chip.farbe : Color.secondary.opacity(0.3)))
          .foregroundStyle(gewaehlt ? chip.farbe : .primary)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct PlakatDetail: View {
  @EnvironmentObject private var model: AppModel
  let plakat: Poster

  var body: some View {
    NavigationStack {
      List {
        if let name = plakat.localPhotoFileName,
          let bild = UIImage(contentsOfFile: model.photoURL(name).path)
        {
          Image(uiImage: bild)
            .resizable().scaledToFit()
            .frame(maxHeight: 220)
            .listRowInsets(EdgeInsets())
        }
        LabeledContent("Art", value: plakat.type.beschriftung)
        LabeledContent("Status", value: plakat.status.beschriftung)
        if !plakat.addressHint.isEmpty {
          LabeledContent("Standort", value: plakat.addressHint)
        }
        LabeledContent("Erfasst von", value: plakat.createdByName)
        if !plakat.officialNote.isEmpty {
          LabeledContent("Für die Verwaltung", value: plakat.officialNote)
        }

        Section {
          Button("Navigation starten") { plakat.hinlaufen() }
        }

        Section("Status ändern") {
          ForEach(PosterStatus.allCases, id: \.self) { status in
            Button(status.beschriftung) { model.setzeStatus(plakat, status) }
              .foregroundStyle(status == plakat.status ? Color.secondary : status.farbe)
          }
        }
      }
      .navigationTitle(plakat.addressHint.isEmpty ? "Plakat" : plakat.addressHint)
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
