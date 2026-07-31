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
                    Text(plakat.status.beschriftung)
                        .font(.subheadline).foregroundStyle(plakat.status.farbe)
                    if let text = RemovalDeadlinePolicy.removalCountdownText(plakat.plannedRemovalAt) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle((plakat.plannedRemovalAt ?? .max) < Date.nowMillis ? .red : .secondary)
                    }
                }
            }

            Menu("Status ändern") {
                ForEach(PosterStatus.allCases, id: \.self) { status in
                    Button(status.beschriftung) { model.setzeStatus(plakat, status) }
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button("Löschen", role: .destructive) { model.loesche(plakat) }
        }
    }

}
