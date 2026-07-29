import CoreLocation
import MapKit
import PlakatKompassCore
import SwiftUI

/// Die Startseite. Gegenstück zu `ModernHomeScreen` auf Android.
///
/// Sie kann nichts, was die anderen Bereiche nicht auch können — und ist trotzdem der wichtigste
/// Bildschirm: Wer die App im Stehen aufmacht, mit einer Hand, will in zwei Sekunden wissen, ob
/// etwas ansteht und wo das nächste Plakat ist. Dafür durch drei Reiter zu suchen ist eine
/// Zumutung.
struct StartView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var standort = Standort()

    private var zahlen: HomeStats { HomeStats(posters: model.state.posters) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Kopf(teamName: model.state.teamName, geraet: model.state.deviceName)

                    if model.faelligeAbnahmen > 0 {
                        Faelliges(anzahl: model.faelligeAbnahmen)
                    }

                    Zahlenreihe(zahlen: zahlen)

                    if let treffer = naechstes {
                        NaechstesPlakat(treffer: treffer)
                    } else if model.state.posters.isEmpty {
                        Text("Noch keine Plakate erfasst. Der Anfang steht unter „Erfassen“.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Plakat Kompass")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        EinstellungenView()
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SozialdatenView()
                    } label: {
                        Label("Sozialdaten", systemImage: "chart.bar")
                    }
                }
            }
            .onAppear { standort.starte() }
            .onDisappear { standort.stoppe() }
        }
    }

    private var naechstes: NearestPoster.Treffer? {
        guard let hier = standort.position else { return nil }
        return NearestPoster.find(
            model.state.posters,
            latitude: hier.coordinate.latitude,
            longitude: hier.coordinate.longitude
        )
    }
}

private struct Kopf: View {
    let teamName: String?
    let geraet: String

    var body: some View {
        VStack(spacing: 4) {
            Text(teamName ?? "Lokales Plakat-Team")
                .font(.title2.weight(.semibold))
            Text(geraet)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Der einzige Hinweis, der auffallen muss. Alles andere auf dieser Seite ist Information,
/// das hier ist eine Frist.
private struct Faelliges: View {
    let anzahl: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(anzahl == 1 ? "1 Plakat abnehmen" : "\(anzahl) Plakate abnehmen")
                    .font(.headline)
                Text("Die Abnahmefrist ist erreicht.")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color(red: 0.86, green: 0.15, blue: 0.15), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Zahlenreihe: View {
    let zahlen: HomeStats

    var body: some View {
        // Zwei mal zwei statt vier nebeneinander: Auf einem iPhone SE wären vier Kacheln so
        // schmal, dass dreistellige Zahlen umbrechen.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Kachel(wert: zahlen.aktiv, titel: "Aktiv", farbe: Color(red: 0.39, green: 0.40, blue: 0.95))
                Kachel(wert: zahlen.kontrolliert, titel: "OK", farbe: Color(red: 0.06, green: 0.73, blue: 0.51))
            }
            GridRow {
                Kachel(wert: zahlen.probleme, titel: "Probleme", farbe: Color(red: 0.86, green: 0.15, blue: 0.15))
                Kachel(wert: zahlen.entfernt, titel: "Entfernt", farbe: Color(red: 0.39, green: 0.45, blue: 0.55))
            }
        }
    }
}

private struct Kachel: View {
    let wert: Int
    let titel: String
    let farbe: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(wert)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(farbe)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(titel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titel): \(wert)")
    }
}

private struct NaechstesPlakat: View {
    @EnvironmentObject private var model: AppModel
    let treffer: NearestPoster.Treffer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In deiner Nähe")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                if let name = treffer.poster.localPhotoFileName,
                   let bild = UIImage(contentsOfFile: model.photoURL(name).path) {
                    Image(uiImage: bild)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(treffer.poster.addressHint.isEmpty
                         ? treffer.poster.type.beschriftung
                         : treffer.poster.addressHint)
                        .font(.headline)
                    Text("\(NearestPoster.distanceText(treffer.entfernungMeter)) · \(treffer.poster.status.beschriftung)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Die Navigation überlassen wir Apple Maps - wie in der Detailansicht auch.
            Button {
                let ziel = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                    latitude: treffer.poster.latitude, longitude: treffer.poster.longitude
                )))
                ziel.name = treffer.poster.addressHint.isEmpty ? "Plakat" : treffer.poster.addressHint
                ziel.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                ])
            } label: {
                Label("Hinlaufen", systemImage: "figure.walk")
                    .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

