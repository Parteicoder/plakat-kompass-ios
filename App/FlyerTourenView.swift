import MapKit
import PlakatKompassCore
import SwiftUI

/// Flyer-Touren: aufzeichnen, ansehen, verwalten.
struct FlyerTourenView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var aufzeichnung = TourAufzeichnung()
    @State private var neuerName = ""
    @State private var loeschKandidat: FlyerTour?

    /// Touren ohne Wegpunkte sind für die Liste uninteressant — außer der eigenen laufenden,
    /// die am Anfang naturgemäß leer ist.
    private var touren: [FlyerTour] {
        model.state.flyerTours.filter { !$0.points.isEmpty || $0.id == model.offeneTour?.id }
    }

    var body: some View {
        List {
            Section {
                if let offen = model.offeneTour {
                    LaufendeTour(tour: offen, aufzeichnung: aufzeichnung)
                } else {
                    TextField("Name der Tour", text: $neuerName)
                    Button {
                        starte()
                    } label: {
                        Label("Tour starten", systemImage: "record.circle")
                    }
                    .disabled(!model.istEingerichtet)
                }
            } header: {
                Text("Aufzeichnen")
            } footer: {
                if model.offeneTour == nil {
                    Text("""
                    Der zurückgelegte Weg wird aufgezeichnet, damit das Team sieht, welche Straßen \
                    schon versorgt sind. Ein Wegpunkt alle 20 Meter, höchstens fünf Stunden am Stück.
                    """)
                }
            }

            if touren.isEmpty {
                Section {
                    Text("Noch keine Touren. Auch die von Android-Geräten erscheinen hier, sobald ein Paket ankommt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Touren") {
                    ForEach(touren) { tour in
                        NavigationLink {
                            TourKarte(tour: tour)
                        } label: {
                            TourZeile(tour: tour)
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) { loeschKandidat = tour }
                        }
                    }
                }
            }
        }
        .navigationTitle("Flyer-Touren")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Tour löschen?",
            isPresented: .init(get: { loeschKandidat != nil }, set: { if !$0 { loeschKandidat = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let tour = loeschKandidat {
                    if tour.id == model.offeneTour?.id { aufzeichnung.stoppe() }
                    model.loescheTour(tour)
                }
                loeschKandidat = nil
            }
            Button("Abbrechen", role: .cancel) { loeschKandidat = nil }
        } message: {
            Text("Der aufgezeichnete Weg geht dabei verloren. Andere Geräte behalten ihre Fassung, bis sie ebenfalls löschen.")
        }
        .onDisappear {
            // Die Aufzeichnung laeuft bewusst WEITER, wenn man den Bildschirm verlaesst -
            // man verteilt Flyer und schaut dabei nicht auf die App. Gestoppt wird nur ueber
            // "Beenden" oder wenn die Tour geloescht wird.
        }
    }

    private func starte() {
        guard let tour = model.starteTour(name: neuerName) else { return }
        neuerName = ""
        aufzeichnung.starte(tourId: tour.id) { breite, laenge in
            model.merkeWegpunkt(tourId: tour.id, latitude: breite, longitude: laenge)
        }
    }
}

private struct LaufendeTour: View {
    @EnvironmentObject private var model: AppModel
    let tour: FlyerTour
    @ObservedObject var aufzeichnung: TourAufzeichnung

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: tour.status == .ACTIVE ? "record.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(tour.status == .ACTIVE ? .red : .orange)
                Text(tour.name).font(.headline)
                Spacer()
                Text("\(tour.points.count) Punkte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if aufzeichnung.nurImVordergrund && tour.status == .ACTIVE {
                // Lieber sagen als still weniger tun: Ohne "Immer" bricht die Aufzeichnung ab,
                // sobald das Telefon in die Tasche wandert - also genau beim Verteilen.
                Text("Ohne die Berechtigung „Immer“ zeichnet die App nur auf, solange sie offen ist. Zu ändern unter Einstellungen › Plakat Kompass › Ort.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if tour.status == .ACTIVE {
                    Button("Pause") {
                        model.setzeTourStatus(tour, .PAUSED)
                        aufzeichnung.stoppe()
                    }
                } else {
                    Button("Fortsetzen") {
                        model.setzeTourStatus(tour, .ACTIVE)
                        aufzeichnung.starte(tourId: tour.id) { breite, laenge in
                            model.merkeWegpunkt(tourId: tour.id, latitude: breite, longitude: laenge)
                        }
                    }
                }
                Spacer()
                Button("Beenden", role: .destructive) {
                    aufzeichnung.stoppe()
                    model.setzeTourStatus(tour, .FINISHED)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct TourZeile: View {
    let tour: FlyerTour

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tour.name.isEmpty ? "Tour ohne Namen" : tour.name)
                .font(.headline)
            Text("\(tour.createdByName) · \(tour.status.beschriftung)")
                .font(.subheadline)
                .foregroundStyle(tour.status == .ACTIVE ? Color.green : Color.secondary)
            Text("\(laenge(tour)) · \(tour.points.count) Punkte")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Luftlinie zwischen aufeinanderfolgenden Punkten, aufsummiert.
    ///
    /// Das ist nicht die gelaufene Strecke — die Punkte liegen nicht dicht genug, und um Ecken
    /// herum schneidet die Summe ab. Als Anhaltspunkt, wie groß eine Tour war, reicht es, und
    /// eine echte Wegberechnung wäre hier Aufwand ohne Zweck.
    private func laenge(_ tour: FlyerTour) -> String {
        let meter = zip(tour.points, tour.points.dropFirst()).reduce(0.0) { summe, paar in
            summe + CLLocation(latitude: paar.0.latitude, longitude: paar.0.longitude)
                .distance(from: CLLocation(latitude: paar.1.latitude, longitude: paar.1.longitude))
        }
        return meter < 1000
            ? "\(Int(meter.rounded())) m"
            : String(format: "%.1f km", meter / 1000)
    }
}

private struct TourKarte: View {
    let tour: FlyerTour

    private var punkte: [CLLocationCoordinate2D] {
        tour.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Map(initialPosition: .region(ausschnitt)) {
            MapPolyline(coordinates: punkte)
                .stroke(Color(red: 0.39, green: 0.40, blue: 0.95), lineWidth: 4)
            if let start = punkte.first {
                Marker("Start", systemImage: "flag", coordinate: start)
                    .tint(.green)
            }
            if let ende = punkte.last, punkte.count > 1 {
                Marker("Ende", systemImage: "flag.checkered", coordinate: ende)
                    .tint(.red)
            }
        }
        .navigationTitle(tour.name.isEmpty ? "Tour" : tour.name)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Ausschnitt so, dass die ganze Tour hineinpasst, mit etwas Luft am Rand.
    private var ausschnitt: MKCoordinateRegion {
        let breiten = tour.points.map(\.latitude)
        let laengen = tour.points.map(\.longitude)
        guard let minB = breiten.min(), let maxB = breiten.max(),
              let minL = laengen.min(), let maxL = laengen.max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 52.5119, longitude: 13.4116),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minB + maxB) / 2, longitude: (minL + maxL) / 2),
            // Der Mindestwert fängt die Tour ab, die auf einem Fleck steht: Ohne ihn wäre die
            // Spanne null und die Karte zeigte gar nichts.
            span: MKCoordinateSpan(
                latitudeDelta: max((maxB - minB) * 1.4, 0.004),
                longitudeDelta: max((maxL - minL) * 1.4, 0.004)
            )
        )
    }
}

extension FlyerTourStatus {
    var beschriftung: String {
        switch self {
        case .ACTIVE: return "läuft"
        case .PAUSED: return "pausiert"
        case .FINISHED: return "beendet"
        }
    }
}
