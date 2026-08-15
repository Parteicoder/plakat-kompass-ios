import MapKit
import PlakatKompassCore
import SwiftUI

struct PosterMapView: View {
  @EnvironmentObject private var model: AppModel
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
  @State private var filter: PosterFilter = .aktiv
  @State private var suchtext = ""
  @State private var suchfehler: String?

  /// Auf der Flyerkarte gibt es keine Plakate — dort soll allein der gelaufene Weg zu sehen
  /// sein. Sonst liegen Marker über dem Balken und man sieht die Strasse nicht mehr.
  ///
  /// Derselbe Filter wie in der Liste, aus PosterFilter: Wer dort „Überfällig" gewählt hat und
  /// zur Karte wechselt, erwartet dieselbe Auswahl und nicht eine zweite Bedeutung desselben
  /// Wortes.
  private var sichtbare: [Poster] {
    guard !flyerkarte else { return [] }
    return model.state.posters.gefiltert(nach: filter, jetzt: Date.nowMillis)
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
        // Auf der Flyerkarte gibt es nichts zu filtern - dort liegen keine Plakate.
        if !flyerkarte {
          ToolbarItem(placement: .topBarLeading) {
            Picker("Filter", selection: $filter) {
              ForEach(PosterFilter.allCases, id: \.self) { Text($0.beschriftung).tag($0) }
            }
            .pickerStyle(.menu)
          }
        }
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
        if grenzeZeigen, let name = grenze.grenze?.name {
          Text(name)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 8)
        }
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
              : "Kein Plakat passt zum Filter „\(filter.beschriftung)\u{201C}."
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
    guard let ziel = URL(string: CommuneBoundaryQuery.url(latitude: latitude, longitude: longitude))
    else { return }

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
    else { return }

    let gefunden = CommuneBoundaryQuery.parse(String(decoding: daten, as: UTF8.self))
    zwischenspeicher[schluessel] = gefunden
    grenze = gefunden
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
