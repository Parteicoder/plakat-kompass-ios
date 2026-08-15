import PlakatKompassCore
import SwiftUI

struct PosterListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: PosterFilter = .aktiv

    private var gefiltert: [Poster] {
        model.state.posters.gefiltert(nach: filter, jetzt: Date.nowMillis)
    }

    var body: some View {
        NavigationStack {
            Group {
                if gefiltert.isEmpty {
                    ContentUnavailableView(
                        "Keine Plakate",
                        systemImage: "tray",
                        description: Text("Unter „Erfassen“ kommt das erste hinzu.")
                    )
                } else {
                    List {
                        ForEach(gefiltert) { plakat in
                            PosterZeile(plakat: plakat)
                        }
                    }
                }
            }
            .navigationTitle("Plakate")
            // Von einer angetippten Kachel auf der Startseite angefordert. `onChange` statt
            // `onAppear`, weil TabView diese Ansicht am Leben hält — ein zweiter Tap auf eine
            // Kachel, während „Liste" schon offen ist, würde sonst nichts auslösen.
            .onChange(of: model.listenFilterAnfrage) { _, angefordert in
                guard let angefordert else { return }
                filter = angefordert
                model.listenFilterAnfrage = nil
            }
            .onAppear {
                if let angefordert = model.listenFilterAnfrage {
                    filter = angefordert
                    model.listenFilterAnfrage = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Filter", selection: $filter) {
                        ForEach(PosterFilter.allCases, id: \.self) { Text($0.beschriftung).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FlyerTourenView()
                    } label: {
                        Label("Flyer-Touren", systemImage: "figure.walk")
                    }
                }
            }
        }
    }
}

private struct PosterZeile: View {
    @EnvironmentObject private var model: AppModel
    let plakat: Poster

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let name = plakat.localPhotoFileName,
                   let bild = UIImage(contentsOfFile: model.photoURL(name).path) {
                    Image(uiImage: bild)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(plakat.addressHint.isEmpty ? plakat.type.beschriftung : plakat.addressHint)
                        .font(.headline)
                    // Nur wenn die Adresse schon oben steht - sonst stünde die Art zweimal da.
                    // Drüben ist sie die Unterzeile: „Rödgener Straße 16" sagt, wo man suchen
                    // muss, „Laternenmast" sagt, wonach.
                    if !plakat.addressHint.isEmpty {
                        Text(plakat.type.beschriftung)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(plakat.status.beschriftung)
                        .font(.subheadline).foregroundStyle(plakat.status.farbe)
                    if let text = RemovalDeadlinePolicy.removalCountdownText(plakat.plannedRemovalAt) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle((plakat.plannedRemovalAt ?? .max) < Date.nowMillis ? .red : .secondary)
                    }
                }
            }

            // Notizen inline in der Zeile, wie auf Android (ModernPosterCard.ModernPosterNotes) -
            // wer im Team unterwegs ist, will nicht erst jedes Plakat öffnen, um zu sehen, ob
            // schon ein Vermerk dransteht.
            Notizzeile(titel: "Verwaltung", text: plakat.officialNote)
            Notizzeile(titel: "Intern", text: plakat.internalNote)

            HStack {
                Menu("Status ändern") {
                    ForEach(PosterStatus.allCases, id: \.self) { status in
                        Button(status.beschriftung) { model.setzeStatus(plakat, status) }
                    }
                }
                Spacer()
                // Drüben heißt dieser Knopf „Standort" und steht auf jeder Karte in der Liste.
                // Auf iOS führte der einzige Weg dorthin über die Karte: Reiter wechseln, den
                // richtigen Punkt unter womöglich zwanzig finden, antippen, dann navigieren.
                // Wer die Liste abarbeitet, will von der Zeile aus loslaufen.
                Button { plakat.hinlaufen() } label: {
                    Label("Standort", systemImage: "location.fill")
                }
                .accessibilityLabel("Weg zu diesem Plakat")
            }
            .font(.footnote)
            // Ohne das löst in einer List jeder Tipper irgendwo in der Zeile beide Knöpfe aus.
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button("Löschen", role: .destructive) { model.loesche(plakat) }
        }
    }

}

/// Eine einzelne Notiz-Zeile, nur sichtbar wenn nicht leer. Gegenstück zu `ModernPosterNoteLine`.
private struct Notizzeile: View {
    let titel: String
    let text: String

    var body: some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            (Text("\(titel) ").fontWeight(.bold) + Text(text).foregroundStyle(.secondary))
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
