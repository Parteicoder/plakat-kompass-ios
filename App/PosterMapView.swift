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
    @State private var suchtext = ""
    @State private var suchfehler: String?

    /// Der Sozialdaten-Umkreis. Bleibt über Neustarts an, wie auf Android auch — wer damit
    /// arbeitet, arbeitet eine Weile damit.
    @AppStorage("sozialAufKarte") private var sozialZeigen = false
    /// Dieselbe Klasse wie im Sozialdaten-Bildschirm — eine zweite Fassung des Abrufs hier hiesse
    /// zwei, die mit der Zeit auseinanderlaufen.
    ///
    /// Es ist allerdings eine **eigene Instanz** und damit ein eigener Zwischenspeicher: Die
    /// beiden Bildschirme teilen ihn nicht. Das kostet beim Wechsel höchstens eine zusätzliche
    /// Abfrage und erspart ein gemeinsames Objekt, das die halbe App durchreichen müsste.
    @StateObject private var sozial = Sozialdatenabruf()
    /// Der Punkt, für den die angezeigten Zahlen tatsächlich gelten.
    ///
    /// Ausdrücklich **nicht** [mitte]: Der Kreis wandert sonst beim Schieben der Karte mit,
    /// während darin noch die Zahlen des alten Orts stehen. Ein Kreis, der behauptet, für den
    /// Bereich unter ihm zu gelten, obwohl er es nicht tut, ist schlimmer als kein Kreis.
    @State private var kreisMitte: CLLocationCoordinate2D?

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

    /// Sozialdaten nur auf der Plakatkarte, genau wie `socialActive` auf Android.
    ///
    /// Auf der Flyerkarte geht es um den gelaufenen Weg. Ein zweiter mintgrüner Kreis neben dem
    /// mintgrünen Startpunkt der Tour wäre dort vor allem eines: verwechselbar.
    private var sozialAktiv: Bool { sozialZeigen && !flyerkarte }

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
                // Der 300-Meter-Umkreis, für den die Zahlen unten gelten. Er erscheint erst NACH
                // einer Antwort und liegt dann genau auf dem abgefragten Punkt — nicht auf der
                // aktuellen Kartenmitte.
                if sozialAktiv, let punkt = kreisMitte {
                    MapCircle(center: punkt, radius: CLLocationDistance(ZensusRaster.radiusMeter))
                        .foregroundStyle(Self.mint.opacity(0.2))
                        .stroke(Self.mint.opacity(0.65), lineWidth: 3)
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
            .task(id: sozialSchluessel) { await holeSozialdaten() }
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
                    Toggle(isOn: $flyerkarte) {
                        Label("Flyerkarte", systemImage: "figure.walk")
                    }
                    .toggleStyle(.button)
                }
                // Auf der Flyerkarte gibt es keinen Umkreis - siehe sozialAktiv.
                if !flyerkarte {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: $sozialZeigen) {
                            Label("Sozialdaten", systemImage: "person.3")
                        }
                        .toggleStyle(.button)
                    }
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
                // Hinweis und Sozialdaten uebereinander, statt dass eines das andere verdraengt:
                // Warum die Karte leer ist und was im Umkreis wohnt, sind zwei verschiedene
                // Auskuenfte, und beide koennen gleichzeitig gebraucht werden.
                VStack(spacing: 8) {
                    if flyerkarte && touren.isEmpty {
                        Text("Noch keine Flyer-Tour mit Wegpunkten. Unter „Start\u{201C} lässt sich eine aufzeichnen.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.horizontal, 24)
                    } else if !flyerkarte && sichtbare.isEmpty {
                        Text(model.state.posters.isEmpty
                             ? "Noch keine Plakate auf der Karte."
                             : "Kein Plakat passt zum Filter „\(filter.beschriftung)\u{201C}.")
                            .font(.footnote)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                    }
                    if sozialAktiv {
                        Sozialkarte(zustand: sozial.zustand)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

private extension PosterMapView {
    /// Springt an die eingetippte Adresse.
    ///
    /// Der Ausschnitt ist bewusst eng (600 m): Wer eine Adresse sucht, will die Strasse sehen und
    /// nicht die Stadt. Findet der Geocoder nichts, sagt die App das - stiller Stillstand waere
    /// hier das Schlimmste, weil man nicht weiss, ob die Suche laeuft oder nichts fand.
    @MainActor func springeZurAdresse() {
        let anfrage = suchtext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anfrage.isEmpty else { return }
        Task {
            guard let treffer = try? await CLGeocoder().geocodeAddressString(anfrage),
                  let ort = treffer.first?.location?.coordinate
            else {
                suchfehler = "Zu „\(anfrage)\u{201C} wurde nichts gefunden."
                return
            }
            ausschnitt = .region(MKCoordinateRegion(
                center: ort,
                latitudinalMeters: 600,
                longitudinalMeters: 600
            ))
        }
    }

    /// Grob gerundet, weil eine Gemeinde größer ist als 100 Meter: Ohne das Runden löst jedes
    /// Verschieben der Karte eine neue Overpass-Abfrage aus.
    var grenzeSchluessel: String {
        guard grenzeZeigen, let punkt = mitte else { return "aus" }
        return String(format: "%.2f|%.2f", punkt.latitude, punkt.longitude)
    }

    /// Drei Nachkommastellen, also gut hundert Meter — dieselbe Rundung wie im
    /// Sozialdaten-Bildschirm, und in derselben Größenordnung wie Androids Schwelle von 80 m.
    ///
    /// Feiner wäre sinnlos: Die Abfrage liest die Rasterzellen im Umkreis, und zwei Punkte in
    /// derselben Zellnachbarschaft ergeben dieselbe URL — die zweite Anfrage beantwortet dann
    /// ohnehin der Zwischenspeicher von [Sozialdatenabruf]. Deshalb braucht es hier keine
    /// Entfernungsrechnung, nur eine Rundung.
    var sozialSchluessel: String {
        guard sozialAktiv, let punkt = mitte else { return "aus" }
        return String(format: "%.3f|%.3f", punkt.latitude, punkt.longitude)
    }

    /// Holt die Rasterwerte für die Kartenmitte.
    ///
    /// Der Kreis wird **erst nach** einer Antwort gesetzt und dabei auf den abgefragten Punkt —
    /// nicht auf die inzwischen vielleicht verschobene Kartenmitte. Bis dahin steht er auf `nil`,
    /// die Karte zeigt also lieber keinen Kreis als einen, der am falschen Ort das Falsche
    /// behauptet.
    @MainActor func holeSozialdaten() async {
        guard sozialAktiv, let punkt = mitte else {
            kreisMitte = nil
            return
        }
        kreisMitte = nil
        await sozial.holeRaster(latitude: punkt.latitude, longitude: punkt.longitude)
        if case .werte = sozial.zustand { kreisMitte = punkt }
    }
}

/// Die Rasterwerte zur Kartenmitte, als Karte über der Karte.
///
/// Die Höhe ist gedeckelt und der Inhalt rollt: Das Gitter liefert zehn Kennzahlen, und zehn
/// Zeilen verdecken auf einem iPhone die halbe Karte. Wer Sozialdaten einblendet, will sie
/// **neben** der Karte sehen, nicht statt ihrer.
private struct Sozialkarte: View {
    let zustand: Sozialdatenabruf.Zustand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch zustand {
            case .ruhe:
                Text("Karte bewegen, dann werden die Werte geholt.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .laedt:
                // Fünfzehn Sekunden ohne ein Lebenszeichen sehen aus wie ein Fehler. Die Dauer
                // steht deshalb dabei, statt dass man sie erlebt.
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Umkreis wird gelesen — das dauert rund fünfzehn Sekunden.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case .leer:
                Text("Für diesen Umkreis liegen keine Rasterwerte vor.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .fehler(let text):
                Text(text).font(.footnote).foregroundStyle(.orange)
            case .wert(let wert):
                // Kommt hier nicht vor: Die Karte fragt ausschliesslich das Raster ab, und das
                // liefert immer alle Kennzahlen. Der Fall gehoert trotzdem behandelt, sonst
                // waere das switch nicht vollstaendig.
                Zeile(wert: wert)
            case .werte(let werte):
                Text("Umkreis \(ZensusRaster.radiusMeter) m")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(werte, id: \.indicator.id) { Zeile(wert: $0) }
                    }
                }
                .frame(maxHeight: 150)
                // Ohne Namensnennung darf der Zensus nicht verwendet werden (DL-DE/BY-2.0).
                Text(ZensusRaster.quellenangabe)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private struct Zeile: View {
        let wert: SocialValue

        var body: some View {
            HStack {
                Text(wert.indicator.label).font(.footnote)
                Spacer(minLength: 12)
                Text(wert.formatted).font(.footnote.weight(.semibold))
            }
        }
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
