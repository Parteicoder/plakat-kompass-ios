import MapKit
import PlakatKompassCore
import SwiftUI

struct PosterMapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ausschnitt: MapCameraPosition = .automatic
    @State private var ausgewaehlt: Poster?
    @StateObject private var grenze = Gemeindegrenze()
    @AppStorage("grenzeZeigen") private var grenzeZeigen = false
    @State private var mitte: CLLocationCoordinate2D?
    @State private var flyerkarte = false
    @State private var filter: PosterFilter = .aktiv

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
                        MapPolyline(coordinates: linie.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.75), lineWidth: 3)
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
                        coordinate: CLLocationCoordinate2D(latitude: plakat.latitude, longitude: plakat.longitude)
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
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.inline)
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
                if flyerkarte && touren.isEmpty {
                    Text("Noch keine Flyer-Tour mit Wegpunkten. Unter „Start\u{201C} lässt sich eine aufzeichnen.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.horizontal, 24).padding(.bottom, 20)
                } else if !flyerkarte && sichtbare.isEmpty {
                    Text(model.state.posters.isEmpty
                         ? "Noch keine Plakate auf der Karte."
                         : "Kein Plakat passt zum Filter „\(filter.beschriftung)\u{201C}.")
                        .font(.footnote)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

private extension PosterMapView {
    /// Grob gerundet, weil eine Gemeinde größer ist als 100 Meter: Ohne das Runden löst jedes
    /// Verschieben der Karte eine neue Overpass-Abfrage aus.
    var grenzeSchluessel: String {
        guard grenzeZeigen, let punkt = mitte else { return "aus" }
        return String(format: "%.2f|%.2f", punkt.latitude, punkt.longitude)
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

        var anfrage = URLRequest(url: ziel)
        anfrage.timeoutInterval = 30
        anfrage.setValue("PlakatKompass/1.0 (iOS; Gemeindegrenzen)", forHTTPHeaderField: "User-Agent")
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")

        // Scheitert die Abfrage, bleibt die Karte einfach ohne Grenze. Eine Fehlermeldung waere
        // hier fehl am Platz - die Grenze ist eine Zugabe, keine Voraussetzung.
        guard let (daten, antwort) = try? await URLSession.shared.data(for: anfrage),
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
                   let bild = UIImage(contentsOfFile: model.photoURL(name).path) {
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
                    // Navigation ueberlassen wir Apple Maps - eine eigene Routenfuehrung
                    // waere Monate Arbeit fuer etwas, das jedes iPhone schon kann.
                    Button("Navigation starten") {
                        let ziel = MKMapItem(placemark: MKPlacemark(coordinate: .init(
                            latitude: plakat.latitude, longitude: plakat.longitude
                        )))
                        ziel.name = plakat.addressHint.isEmpty ? "Plakat" : plakat.addressHint
                        ziel.openInMaps(launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                        ])
                    }
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
