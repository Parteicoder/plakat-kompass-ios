import MapKit
import PlakatKompassCore
import SwiftUI

/// Die Karte mit allen Plakaten.
///
/// **Bewusst die ältere Karten-Schnittstelle.** `Map(position:)`, `MapCameraPosition`,
/// `Annotation` und `MapUserLocationButton` gibt es erst ab iOS 17. Das Projekt steht auf iOS 16,
/// weil sonst alle iPhones vor dem XS herausfielen — und das sind genau die Geräte, die
/// Freiwillige oft noch benutzen. Der Preis ist diese Datei: `Map(coordinateRegion:)` ist ab
/// iOS 17 als veraltet markiert, funktioniert dort aber weiterhin.
///
/// Wer das Ziel später auf iOS 17 hebt, kann diese Datei auf die neue Schnittstelle umstellen und
/// wird dabei kürzer.
struct PosterMapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ausschnitt = MKCoordinateRegion(
        // Berlin als Rückfall, solange kein Plakat erfasst ist.
        center: CLLocationCoordinate2D(latitude: 52.5119, longitude: 13.4116),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var ausgewaehlt: Poster?
    @State private var schonZentriert = false

    private var sichtbare: [Poster] {
        model.state.posters.filter { $0.status != .REMOVED }
    }

    var body: some View {
        NavigationStack {
            Map(
                coordinateRegion: $ausschnitt,
                showsUserLocation: true,
                annotationItems: sichtbare
            ) { plakat in
                MapAnnotation(
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
                    .accessibilityLabel(
                        plakat.addressHint.isEmpty ? plakat.status.beschriftung : plakat.addressHint
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $ausgewaehlt) { plakat in
                PlakatDetail(plakat: plakat)
                    .presentationDetents([.medium])
            }
            .overlay(alignment: .bottom) {
                if sichtbare.isEmpty {
                    Text("Noch keine Plakate auf der Karte.")
                        .font(.footnote)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
            .onAppear(perform: zentriereEinmal)
        }
    }

    /// Beim ersten Öffnen auf die eigenen Plakate springen, danach nie wieder — sonst würde die
    /// Karte bei jeder Rückkehr zurückspringen, während man noch schiebt.
    private func zentriereEinmal() {
        guard !schonZentriert, let erstes = sichtbare.first else { return }
        schonZentriert = true
        ausschnitt = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: erstes.latitude, longitude: erstes.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
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
