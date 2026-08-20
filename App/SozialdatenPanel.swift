import PlakatKompassCore
import SwiftUI

/// Sozialdaten am Kartenmittelpunkt. Gegenstück zu `SocialDataPanel.kt` auf der Android-Karte.
///
/// Wahldaten sind auf iOS schon ein eigenes Panel — hier bewusst nicht als dritter Chip
/// hineingezogen, sonst gäbe es zwei Wege zu derselben Zahl.
struct SozialdatenPanel: View {
    let zustand: Sozialdatenabruf.Zustand
    let gewaehlteQuelle: SozialdatenView.Quelle
    let genutzteQuelle: SozialdatenView.Quelle?
    let gewaehlteKennung: String
    let eingeklappt: Bool
    let onQuelle: (SozialdatenView.Quelle) -> Void
    let onKennung: (String) -> Void
    let onEinklappen: () -> Void
    let onSchliessen: () -> Void

    private var quelleFuerAnzeige: SozialdatenView.Quelle {
        genutzteQuelle ?? gewaehlteQuelle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titel).font(.headline)
                Spacer()
                Button(action: onEinklappen) {
                    Image(systemName: eingeklappt ? "chevron.up" : "chevron.down")
                }
                .accessibilityLabel(eingeklappt ? "Sozialdaten ausklappen" : "Sozialdaten einklappen")
                Button(action: onSchliessen) { Image(systemName: "xmark") }
                    .accessibilityLabel("Sozialdaten ausblenden")
            }

            if !eingeklappt {
                Picker("Quelle", selection: Binding(
                    get: { gewaehlteQuelle },
                    set: { onQuelle($0) }
                )) {
                    ForEach(SozialdatenView.Quelle.allCases) { quelle in
                        Text(quelle.beschriftung).tag(quelle)
                    }
                }
                .pickerStyle(.segmented)

                if quelleFuerAnzeige == .regionalatlas {
                    Picker("Kennzahl", selection: Binding(
                        get: { gewaehlteKennung },
                        set: { onKennung($0) }
                    )) {
                        ForEach(SocialIndicator.alle) { indikator in
                            Text(indikator.label).tag(indikator.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                inhalt
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var titel: String {
        guard eingeklappt, case .werte(let werte) = zustand, let erster = werte.first else {
            return "Sozialdaten"
        }
        return "Sozialdaten · \(erster.regionName)"
    }

    @ViewBuilder private var inhalt: some View {
        switch zustand {
        case .ruhe, .laedt:
            HStack {
                ProgressView()
                Text("Lade Sozialdaten …")
            }
        case .leer:
            Text("Für diesen Punkt liegen keine Werte vor.")
                .foregroundStyle(.secondary)
        case .fehler(let text):
            Text(text).foregroundStyle(.orange)
        case .werte(let werte):
            if let genutzt = genutzteQuelle, genutzt != gewaehlteQuelle {
                FallbackHinweis(genutzt: genutzt)
            }
            if quelleFuerAnzeige == .zensus {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(werte, id: \.indicator.id) { wert in
                            LabeledContent(wert.indicator.label, value: wert.formatted)
                        }
                    }
                }
                .frame(maxHeight: 180)
            } else if let treffer = werte.first(where: { $0.indicator.id == gewaehlteKennung }) {
                Ergebnis(wert: treffer, kompakt: true)
            } else {
                Text("Für diese Kennzahl liegt kein Wert vor.")
                    .foregroundStyle(.secondary)
            }
            Text("""
            Quelle: \(quelleFuerAnzeige == .zensus ? ZensusRaster.quellenangabe : RegionalAtlas.quellenangabe). \
            Gebietsbezogen, keine Personendaten.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
