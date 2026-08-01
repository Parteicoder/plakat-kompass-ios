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
                    BswKopfkarte(
                        teamName: model.state.teamName ?? "Lokales Plakat-Team",
                        rolle: model.state.role == .LEADER ? "Teamleitung" : "Mitglied",
                        plakate: model.state.posters.count,
                        ueberfaellig: model.faelligeAbnahmen
                    )

                    if model.faelligeAbnahmen > 0 {
                        Faelliges(anzahl: model.faelligeAbnahmen)
                    }

                    Zahlenreihe(zahlen: zahlen)

                    // Nur fuer die Teamleitung, genau wie auf Android (AccessPolicy.canShowQr).
                    // Wer keinen QR ausgeben darf, soll den Schalter gar nicht erst sehen.
                    if AccessPolicy.canShowQr(model.state) {
                        Teamaufnahme(nearby: model.nearby)
                    }

                    if let treffer = naechstes {
                        NaechstesPlakat(treffer: treffer)
                    } else if standort.abgelehnt && !model.state.posters.isEmpty {
                        // Sonst fehlt die Karte "naechstes Plakat" einfach, ohne dass jemand
                        // erfaehrt warum - und man sucht den Fehler bei den Plakaten.
                        OrtungAbgelehnt(
                            text: "Ohne Standort lässt sich das nächste Plakat nicht bestimmen."
                        )
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
            // Der warme Grundton aus AppColors.kt. Kein Verlauf: Unter einer List waere er
            // ohnehin verdeckt, und einer, den man nur hier sieht, faellt als Unstimmigkeit auf
            // statt als Wiedererkennung.
            .background(Farben.flaeche)
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

/// Der einzige Hinweis, der auffallen muss. Alles andere auf dieser Seite ist Information,
/// das hier ist eine Frist.
/// „Teamaufnahme" auf der Startseite — Gegenstück zu `ModernTeamQrCard.kt`.
///
/// **Der Schalter tut zwei Dinge, und das zweite ist der eigentliche Punkt:** Er zeigt den
/// Team-QR *und* startet den Funk-Abgleich. Auf Android hängt beides an
/// `setTeamJoinWindowActive`, und das hat einen handfesten Grund — der QR allein genügt nicht.
/// Wer ihn scannt, hat den Team-Schlüssel, aber ohne laufenden Funk gibt es keinen Rückkanal:
/// Das neue Gerät kann sich nicht melden, und die Teamleitung sieht es nicht in ihrer Liste.
///
/// Genau das war auf iOS die Lücke. `TeamQrView` lag unter „Abgleich" und zeigte brav einen
/// rollenden Code — den Funk musste man daneben von Hand einschalten und daran denken. Wer es
/// vergaß, hielt einen gültigen QR hin, der nichts bewirkte.
private struct Teamaufnahme: View {
    @ObservedObject var nearby: NearbyAbgleich

    @State private var aufnahmeLaeuft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Team-QR").font(.headline)
                Spacer()
                Toggle("Teamaufnahme", isOn: Binding(
                    get: { aufnahmeLaeuft },
                    set: { an in
                        aufnahmeLaeuft = an
                        an ? nearby.start() : nearby.stop()
                    }
                ))
                .labelsHidden()
            }

            Text(aufnahmeLaeuft ? "Teamaufnahme aktiv" : "Teamaufnahme starten")
                .font(.subheadline)
                .foregroundStyle(aufnahmeLaeuft ? .primary : .secondary)

            if aufnahmeLaeuft {
                TeamQrView()
            } else {
                Text("""
                Schaltet den Funk ein und zeigt den QR-Code. Beides zusammen — ohne Funk hat das \
                neue Gerät zwar den Code, aber keinen Weg zurück.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        // Der Funk endet, sobald die App in den Hintergrund geht (siehe PlakatKompassApp).
        // Ohne diese Zeile behauptete der Schalter danach weiter „aktiv", und die Teamleitung
        // hielte einen QR hin, der ins Leere zeigt.
        .onChange(of: nearby.laeuft) { _, laeuft in
            if !laeuft { aufnahmeLaeuft = false }
        }
    }
}

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
        .background(Farben.rot, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Zahlenreihe: View {
    let zahlen: HomeStats

    var body: some View {
        // Zwei mal zwei statt vier nebeneinander: Auf einem iPhone SE wären vier Kacheln so
        // schmal, dass dreistellige Zahlen umbrechen.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Kachel(wert: zahlen.aktiv, titel: "Aktiv", farbe: Farben.blau)
                Kachel(wert: zahlen.kontrolliert, titel: "OK", farbe: Farben.gruen)
            }
            GridRow {
                Kachel(wert: zahlen.probleme, titel: "Probleme", farbe: Farben.rot)
                Kachel(wert: zahlen.entfernt, titel: "Entfernt", farbe: Farben.grau)
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

