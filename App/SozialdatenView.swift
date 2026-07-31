import CoreLocation
import UIKit
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
    @AppStorage("sozialQuelle") private var quelle = Quelle.regionalatlas.rawValue

    /// Woher die Zahlen kommen.
    ///
    /// Der Unterschied ist nicht Geschmack, sondern Auflösung: Der Regionalatlas kennt Gemeinden
    /// und Kreise — für die Frage, ob sich ein Wahlkreis lohnt. Das Zensus-Gitter kennt den
    /// Umkreis von 300 Metern, in dem man gerade steht — für die Frage, welche Straße.
    enum Quelle: String, CaseIterable, Identifiable {
        case regionalatlas, zensus
        var id: String { rawValue }
        var beschriftung: String {
            switch self {
            case .regionalatlas: return "Gemeinde/Kreis"
            case .zensus: return "Umkreis 300 m"
            }
        }
    }

    private var gewaehlteQuelle: Quelle { Quelle(rawValue: quelle) ?? .regionalatlas }
    private var indikator: SocialIndicator { .mitId(gewaehlteKennung) }

    var body: some View {
        List {
            Section {
                Picker("Quelle", selection: $quelle) {
                    ForEach(Quelle.allCases) { q in
                        Text(q.beschriftung).tag(q.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Gebiet")
            } footer: {
                Text(gewaehlteQuelle == .zensus
                     ? "Werte für den Umkreis von 300 Metern. Die Abfrage dauert rund fünfzehn Sekunden — sie liest 49 Rasterzellen einzeln."
                     : "Werte für die Gemeinde oder den Kreis. Gröber, dafür schnell und mit mehr Kennzahlen.")
            }

            // Beim Raster gibt es keine Auswahl: Eine Abfrage liefert ohnehin alle Kennzahlen.
            if gewaehlteQuelle == .regionalatlas {
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
            }

            Section {
                if standort.abgelehnt {
                    // Ohne diese Abfrage stand hier für immer "Warte auf den Standort ..." - auf
                    // etwas, das nie kommt. Ein Bildschirm, der auf ein Ereignis wartet, das die
                    // Berechtigung ausschliesst, ist schlimmer als eine Fehlermeldung: Man haelt
                    // die App fuer langsam statt fuer gesperrt.
                    OrtungAbgelehnt(
                        text: "Ohne Standort lassen sich keine Sozialdaten zum Gebiet abrufen."
                    )
                } else {
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
                    case .werte(let werte):
                        ForEach(werte, id: \.indicator.id) { wert in
                            LabeledContent(wert.indicator.label, value: wert.formatted)
                        }
                    }
                }
            } header: {
                Text("Ergebnis")
            } footer: {
                Text("""
                Quelle: \(gewaehlteQuelle == .zensus ? ZensusRaster.quellenangabe : RegionalAtlas.quellenangabe). \
                Alle Werte sind gebietsbezogen und aggregiert — es werden keine personenbezogenen \
                Daten erhoben oder gespeichert.
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
        // Beim Raster ist die Kennzahl egal - eine Abfrage liefert alle. Sie trotzdem in den
        // Schluessel zu nehmen hiesse, bei jedem Wechsel fuenfzehn Sekunden neu zu warten.
        let kennung = gewaehlteQuelle == .zensus ? "raster" : gewaehlteKennung
        return String(
            format: "%@|%@|%.3f|%.3f",
            quelle, kennung, ort.coordinate.latitude, ort.coordinate.longitude
        )
    }

    private func hole() async {
        guard let ort = standort.position else { return }
        if gewaehlteQuelle == .zensus {
            await abruf.holeRaster(
                latitude: ort.coordinate.latitude,
                longitude: ort.coordinate.longitude
            )
        } else {
            await abruf.hole(
                indikator: indikator,
                latitude: ort.coordinate.latitude,
                longitude: ort.coordinate.longitude
            )
        }
    }
}

/// Der Hinweis, wenn die Ortung abgelehnt ist — samt dem Weg, es zu ändern.
///
/// Eine Meldung ohne Ausweg ist eine Sackgasse mit Text. Der Knopf führt genau dorthin, wo die
/// Berechtigung liegt.
struct OrtungAbgelehnt: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ortung ist abgelehnt", systemImage: "location.slash")
                .foregroundStyle(.orange)
                .font(.headline)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Einstellungen öffnen") {
                if let ziel = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(ziel)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
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
        /// Das Raster liefert alle Kennzahlen aus EINER Abfrage. Sie einzeln zu holen hiesse,
        /// fuer jede Zahl fuenfzehn Sekunden zu warten.
        case werte([SocialValue])
        case fehler(String)
    }

    @Published private(set) var zustand: Zustand = .ruhe

    /// Antworten für eine Viertelstunde behalten. Die Zahlen ändern sich jährlich; jede Abfrage
    /// neu zu stellen wäre unhöflich gegenüber einem Server, den die Statistischen Ämter
    /// kostenlos bereitstellen.
    private var zwischenspeicher: [String: (text: String, bis: Date)] = [:]
    private static let haltbarkeit: TimeInterval = 15 * 60

    /// Das Zensus-Gitter: eine Abfrage ueber 49 Zellen, alle Kennzahlen auf einmal.
    func holeRaster(latitude: Double, longitude: Double) async {
        zustand = .laedt
        do {
            let roh = try await lade(
                ZensusRaster.baueUrl(longitude: longitude, latitude: latitude),
                zeitgrenze: 25
            )
            let werte = ZensusRaster.auswerten(roh)
            zustand = werte.isEmpty ? .leer : .werte(werte)
        } catch is CancellationError {
            return
        } catch {
            zustand = .fehler("Die Rasterdaten sind gerade nicht erreichbar. Ohne Netz geht es nicht.")
        }
    }

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

    /// `zeitgrenze` ist ein Parameter, weil die beiden Quellen sich stark unterscheiden: Der
    /// Regionalatlas antwortet in Sekunden, die Rasterabfrage ueber 49 Zellen braucht rund
    /// fuenfzehn. Mit zwoelf Sekunden fuer beide waere das Raster nie durchgekommen.
    private func lade(_ url: String, zeitgrenze: TimeInterval = 12) async throws -> String {
        if let vorhanden = zwischenspeicher[url], vorhanden.bis > Date() {
            return vorhanden.text
        }
        guard let ziel = URL(string: url) else { throw URLError(.badURL) }

        var anfrage = URLRequest(url: ziel)
        anfrage.timeoutInterval = zeitgrenze
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
