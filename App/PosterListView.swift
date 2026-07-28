import PlakatKompassCore
import SwiftUI

struct PosterListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: Filter = .aktiv

    enum Filter: String, CaseIterable {
        case aktiv = "Aktiv"
        case ueberfaellig = "Überfällig"
        case probleme = "Probleme"
        case alle = "Alle"
    }

    private var gefiltert: [Poster] {
        let jetzt = Date.nowMillis
        switch filter {
        case .aktiv: return model.state.posters.filter { $0.status != .REMOVED }
        case .ueberfaellig:
            return model.state.posters.filter {
                $0.status != .REMOVED && ($0.plannedRemovalAt ?? .max) < jetzt
            }
        case .probleme: return model.state.posters.filter { $0.status == .DAMAGED || $0.status == .MISSING }
        case .alle: return model.state.posters
        }
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
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
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
                    if let frist = plakat.plannedRemovalAt {
                        Text(fristText(frist))
                            .font(.caption)
                            .foregroundStyle(frist < Date.nowMillis ? .red : .secondary)
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

    private func fristText(_ frist: Int64) -> String {
        let tage = Int((Double(frist - Date.nowMillis) / 86_400_000).rounded(.up))
        if tage < 0 { return "Abnahme seit \(-tage) Tagen überfällig" }
        if tage == 0 { return "Abnahme heute fällig" }
        return "Abnahme in \(tage) Tagen"
    }
}
