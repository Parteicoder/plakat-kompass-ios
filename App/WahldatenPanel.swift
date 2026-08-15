import PlakatKompassCore
import SwiftUI

@MainActor
final class WahldatenAnzeige: ObservableObject {
  @Published private(set) var zustand: WahldatenUiState = .loading
  private let repository = WahldatenRepository()

  func lade(
    longitude: Double, latitude: Double, wahlart: Wahlart, erzwingen: Bool = false
  ) async {
    if !erzwingen,
      case .success(_, let ergebnis, let flaeche?) = zustand,
      ergebnis.wahl.art == wahlart,
      flaecheAn([flaeche], longitude: longitude, latitude: latitude) != nil
    {
      return
    }
    if case .success = zustand {
      // Vorige Werte bleiben beim Nachladen sichtbar; kein Ladeblitz beim Kartenschwenk.
    } else {
      zustand = .loading
    }
    let neu = await repository.load(longitude: longitude, latitude: latitude, wahlart: wahlart)
    guard !Task.isCancelled else { return }
    zustand = neu
  }
}

struct WahldatenPanel: View {
  let zustand: WahldatenUiState
  let wahlart: Wahlart
  let eingeklappt: Bool
  let onWahlart: (Wahlart) -> Void
  let onErneut: () -> Void
  let onEinklappen: () -> Void
  let onSchliessen: () -> Void

  @AppStorage("wahldatenAlleParteien")
  private var alleParteien = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(titel).font(.headline)
        Spacer()
        Button(action: onEinklappen) {
          Image(systemName: eingeklappt ? "chevron.up" : "chevron.down")
        }
        .accessibilityLabel(eingeklappt ? "Wahldaten ausklappen" : "Wahldaten einklappen")
        Button(action: onSchliessen) { Image(systemName: "xmark") }
          .accessibilityLabel("Wahldaten ausblenden")
      }

      if !eingeklappt {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(Wahlart.allCases, id: \.rawValue) { art in
              Button(art.label) { onWahlart(art) }
                .buttonStyle(.bordered)
                .tint(art == wahlart ? .accentColor : .secondary)
            }
          }
        }
        inhalt
      }
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
  }

  private var titel: String {
    guard eingeklappt, case .success(let gebiet, _, _) = zustand else {
      return "Wahldaten"
    }
    return "Wahldaten · \(gebiet)"
  }

  @ViewBuilder private var inhalt: some View {
    switch zustand {
    case .loading:
      HStack {
        ProgressView()
        Text("Lade Wahlergebnisse …")
      }
    case .empty:
      Text("Dieser Punkt liegt außerhalb der Bundestagswahlkreise.")
        .foregroundStyle(.secondary)
    case .error(let meldung):
      VStack(alignment: .leading, spacing: 8) {
        Text(meldung).foregroundStyle(.secondary)
        Button("Erneut versuchen", action: onErneut)
      }
    case .success(let gebiet, let ergebnis, _):
      VStack(alignment: .leading, spacing: 8) {
        Text(gebiet).font(.title3.bold())
        HStack {
          Text(ergebnis.wahl.titel).font(.subheadline.bold())
          Text(ergebnis.wahl.ebene.label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        if let beteiligung = ergebnis.beteiligung {
          HStack(alignment: .firstTextBaseline) {
            Text(prozent(beteiligung)).font(.title2.bold()).foregroundStyle(.green)
            Text("Wahlbeteiligung").font(.subheadline).foregroundStyle(.secondary)
          }
        }
        ScrollView {
          VStack(spacing: 6) {
            ForEach(
              alleParteien ? ergebnis.parteien : fasseKleineZusammen(ergebnis.parteien),
              id: \.partei
            ) { partei in
              HStack {
                Text(partei.partei)
                Spacer()
                Text(prozent(partei.prozent)).fontWeight(.medium)
              }
            }
          }
        }
        .frame(maxHeight: 220)
        Text("Quelle: \(ergebnis.quellenangabe)")
          .font(.caption2).foregroundStyle(.secondary)
        Text("Amtliche, gebietsbezogene Werte – keine Einzelpersonen.")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private func prozent(_ wert: Double) -> String {
    String(format: "%.1f %%", locale: Locale(identifier: "de_DE"), wert)
  }
}
