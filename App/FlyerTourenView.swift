import MapKit
import PlakatKompassCore
import SwiftUI

/// Die Flyer-Touren, die über den Abgleich hereinkommen.
///
/// **Bewusst nur ansehen, nicht aufzeichnen.** Der Kern trägt Touren längst mit: Sie stehen im
/// JSON eines Sync-Pakets, `SyncMerge` führt sie zusammen, und der lokale Stand speichert sie.
/// Ohne diese Ansicht liegen die Touren eines Android-Kollegen also auf dem iPhone, ohne dass
/// jemand sie zu sehen bekommt.
///
/// Das Aufzeichnen fehlt weiterhin, und zwar mit Absicht: Dafür braucht es auf iOS
/// Ortung im Hintergrund („Immer"), einen dauerhaften Hinweis in der Statusleiste und eine
/// Begründung im App-Store-Verfahren. Das ist eine Produktentscheidung über Akkulaufzeit und
/// Datenschutz, keine technische — und sie steht hier nicht an. Ansehen kostet nichts davon.
struct FlyerTourenView: View {
    @EnvironmentObject private var model: AppModel

    private var touren: [FlyerTour] {
        model.state.flyerTours.filter { !$0.points.isEmpty }
    }

    var body: some View {
        Group {
            if touren.isEmpty {
                ContentUnavailableView(
                    "Keine Touren",
                    systemImage: "figure.walk",
                    description: Text("""
                    Touren werden zurzeit nur auf Android aufgezeichnet. Sobald ein Paket von \
                    dort ankommt, stehen sie hier.
                    """)
                )
            } else {
                List(touren) { tour in
                    NavigationLink {
                        TourKarte(tour: tour)
                    } label: {
                        TourZeile(tour: tour)
                    }
                }
            }
        }
        .navigationTitle("Flyer-Touren")
        .navigationBarTitleDisplayMode(.inline)
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
