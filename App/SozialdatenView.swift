import CoreLocation
import PlakatKompassCore
import SwiftUI

/// Sozialdaten zum Gebiet unter dem eigenen Standort.
///
/// Wozu das gut ist: Wer entscheidet, wo Plakate hängen, will wissen, mit wem er es zu tun hat —
/// wie alt die Leute sind, wie die Arbeitsmarktlage aussieht. Alle Werte sind **gebietsbezogen
/// und aggregiert** aus der amtlichen Regionalstatistik; personenbezogene Daten entstehen dabei
/// nicht und werden nicht gespeichert.
struct SozialdatenView: View {
    @StateObject private var standort = Standort()
    @StateObject private var abruf = Sozialdatenabruf()
    @AppStorage("sozialIndikator") private var gewaehlteKennung = SocialIndicator.standard.id

    private var indikator: SocialIndicator { .mitId(gewaehlteKennung) }

    var body: some View {
        List {
            Section {
                Picker("Kennzahl", selection: $gewaehlteKennung) {
                    ForEach(SocialIndicator.alle) { i in
                        Text(i.label).tag(i.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Kennzahl")
            }

            Section {
                switch abruf.zustand {
                case .ruhe:
                    Text("Warte auf den Standort …").foregroundStyle(.secondary)
                case .laedt:
                    HStack { ProgressView(); Text("Wird abgerufen …").foregroundStyle(.secondary) }
                case .leer:
                    Text("Für diesen Bereich liegen keine Werte vor.").foregroundStyle(.secondary)
                case .fehler(let text):
                    Text(text).foregroundStyle(.orange)
                case .wert(let wert):
                    Ergebnis(wert: wert)
                }
            } header: {
                Text("Ergebnis")
            } footer: {
                Text("""
                Quelle: \(RegionalAtlas.quellenangabe). Alle Werte sind gebietsbezogen und \
                aggregiert — es werden keine personenbezogenen Daten erhoben oder gespeichert.
                """)
            }
        }
        .navigationTitle("Sozialdaten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { standort.starte() }
        .onDisappear { standort.stoppe() }
        .task(id: aufrufSchluessel) { await hole() }
    }

    /// Wechselt der Standort oder die Kennzahl, läuft die Abfrage neu. Die Koordinate wird auf
    /// drei Nachkommastellen gerundet — sonst löst jedes Zittern der Ortung eine neue Abfrage
    /// aus, und rund 100 Meter ändern am Gebiet ohnehin nichts.
    private var aufrufSchluessel: String {
        guard let ort = standort.position else { return "kein-ort" }
        return String(
            format: "%@|%.3f|%.3f",
            gewaehlteKennung, ort.coordinate.latitude, ort.coordinate.longitude
        )
    }

    private func hole() async {
        guard let ort = standort.position else { return }
        await abruf.hole(
            indikator: indikator,
            latitude: ort.coordinate.latitude,
            longitude: ort.coordinate.longitude
        )
    }
}

private struct Ergebnis: View {
    let wert: SocialValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wert.formatted)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(wert.indicator.label)
                .font(.headline)
            // Die Ebene gehoert dazu: Eine Arbeitslosenquote gibt es nur je Kreis. Sie als Wert
            // "fuer diese Gemeinde" auszugeben waere eine Genauigkeit, die die Zahl nicht hat.
            Text("\(wert.regionName) · \(wert.level.beschriftung)\(wert.year.map { " · \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Der Abruf. Getrennt von der Ansicht, damit die Ansicht nichts von `URLSession` weiß.
@MainActor
final class Sozialdatenabruf: ObservableObject {

    enum Zustand {
        case ruhe, laedt, leer
        case wert(SocialValue)
        case fehler(String)
    }

    @Published private(set) var zustand: Zustand = .ruhe

    /// Antworten für eine Viertelstunde behalten. Die Zahlen ändern sich jährlich; jede Abfrage
    /// neu zu stellen wäre unhöflich gegenüber einem Server, den die Statistischen Ämter
    /// kostenlos bereitstellen.
    private var zwischenspeicher: [String: (text: String, bis: Date)] = [:]
    private static let haltbarkeit: TimeInterval = 15 * 60

    func hole(indikator: SocialIndicator, latitude: Double, longitude: Double) async {
        zustand = .laedt

        // Erst die Gemeinde, dann der Kreis. Viele Kennzahlen gibt es nur gröber — dann steht
        // beim Ergebnis eben „Kreis", statt dass gar nichts kommt.
        let ebenen: [RegionLevel] = indikator.availableAtGemeinde ? [.GEMEINDE, .KREIS] : [.KREIS]

        for ebene in ebenen {
            do {
                let roh = try await lade(
                    RegionalAtlas.buildUrl(
                        indicator: indikator, level: ebene, longitude: longitude, latitude: latitude
                    )
                )
                if let wert = RegionalAtlas.parseResponse(roh, indicator: indikator, level: ebene) {
                    zustand = .wert(wert)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                zustand = .fehler("Die Sozialdaten sind gerade nicht erreichbar. Ohne Netz geht es nicht.")
                return
            }
        }
        zustand = .leer
    }

    private func lade(_ url: String) async throws -> String {
        if let vorhanden = zwischenspeicher[url], vorhanden.bis > Date() {
            return vorhanden.text
        }
        guard let ziel = URL(string: url) else { throw URLError(.badURL) }

        var anfrage = URLRequest(url: ziel)
        anfrage.timeoutInterval = 12
        // Manche behoerdlichen ArcGIS-Server weisen Anfragen ohne User-Agent ab.
        anfrage.setValue("PlakatKompass/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")

        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        guard let http = antwort as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let text = String(decoding: daten, as: UTF8.self)
        zwischenspeicher[url] = (text, Date().addingTimeInterval(Self.haltbarkeit))
        return text
    }
}
