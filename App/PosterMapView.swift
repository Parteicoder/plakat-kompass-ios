import MapKit
import PlakatKompassCore
import SwiftUI

struct PosterMapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ausschnitt: MapCameraPosition = .automatic
    @State private var ausgewaehlt: Poster?

    private var sichtbare: [Poster] {
        model.state.posters.filter { $0.status != .REMOVED }
    }

    var body: some View {
        NavigationStack {
            Map(position: $ausschnitt) {
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
