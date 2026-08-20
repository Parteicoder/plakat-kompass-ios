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
                    // Genutzte Quelle statt gewählter: Bei einem Rückfall (siehe Sozialdatenabruf)
                    // zeigen wir Zensus- oder Regionalatlas-Werte, obwohl der Schalter oben etwas
                    // anderes sagt — Hinweis und Quellenangabe müssen dem folgen, sonst wirkt es
                    // wie ein Fehler der App.
                    let quelleGenutzt = abruf.genutzteQuelle ?? gewaehlteQuelle
                    switch abruf.zustand {
                    case .ruhe:
                        Text("Warte auf den Standort …").foregroundStyle(.secondary)
                    case .laedt:
                        HStack { ProgressView(); Text("Wird abgerufen …").foregroundStyle(.secondary) }
                    case .leer:
                        Text("Für diesen Bereich liegen keine Werte vor.").foregroundStyle(.secondary)
                    case .fehler(let text):
                        Text(text).foregroundStyle(.orange)
                    case .werte(let werte):
                        if quelleGenutzt != gewaehlteQuelle {
                            FallbackHinweis(genutzt: quelleGenutzt)
                        }
                        if quelleGenutzt == .zensus {
                            ForEach(werte, id: \.indicator.id) { wert in
                                LabeledContent(wert.indicator.label, value: wert.formatted)
                            }
                        } else if let treffer = werte.first(where: { $0.indicator.id == gewaehlteKennung }) {
                            Ergebnis(wert: treffer)
                        } else {
                            Text("Für diese Kennzahl liegt kein Wert vor.").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Ergebnis")
            } footer: {
                Text("""
                Quelle: \((abruf.genutzteQuelle ?? gewaehlteQuelle) == .zensus ? ZensusRaster.quellenangabe : RegionalAtlas.quellenangabe). \
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

    /// Wechselt der Standort oder die Quelle, läuft die Abfrage neu. Die Koordinate wird auf drei
    /// Nachkommastellen gerundet — sonst löst jedes Zittern der Ortung eine neue Abfrage aus, und
    /// rund 100 Meter ändern am Gebiet ohnehin nichts.
    ///
    /// Die Kennzahl steht bewusst NICHT mehr im Schlüssel: Der Regionalatlas-Abruf holt seit der
    /// Umstellung auf `regionalatlasAlle` ohnehin alle Kennzahlen auf einmal, ein Wechsel der
    /// Auswahl blättert nur noch im schon vorliegenden Ergebnis um, ohne erneut zu laden.
    private var aufrufSchluessel: String {
        guard let ort = standort.position else { return "kein-ort" }
        return String(format: "%@|%.3f|%.3f", quelle, ort.coordinate.latitude, ort.coordinate.longitude)
    }

    private func hole() async {
        guard let ort = standort.position else { return }
        await abruf.lade(
            bevorzugt: gewaehlteQuelle,
            latitude: ort.coordinate.latitude,
            longitude: ort.coordinate.longitude
        )
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

/// Erklärt in einem Satz, warum gerade etwas anderes zu sehen ist als angetippt.
///
/// Das 100-m-Raster des Zensus hat echte Lücken: auf dem Land, in Gewerbegebieten und überall
/// dort, wo Werte aus Datenschutzgründen unterdrückt sind. Ohne diesen Hinweis wirkt es wie ein
/// Fehler der App, wenn die Werte beim Quellenwechsel plötzlich aus der anderen Quelle kommen.
/// Vorbild: `FallbackHinweis` in Android, `SocialDataPanel.kt`.
private struct FallbackHinweis: View {
    let genutzt: SozialdatenView.Quelle

    var body: some View {
        Text(
            genutzt == .regionalatlas
                ? "Für diesen Punkt liegen keine Zensus-Werte vor. Angezeigt werden Werte aus dem Regionalatlas für das umgebende Gebiet."
                : "Für diesen Punkt liegen keine Regionalatlas-Werte vor. Angezeigt werden Werte aus dem Zensus 2022 für den näheren Umkreis."
        )
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.5)))
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
        /// Trägt sowohl das Zensus-Raster (eine Abfrage liefert alle Kennzahlen auf einmal) als
        /// auch den Regionalatlas (seit dem parallelen Vorladen ebenfalls alle zehn Kennzahlen
        /// auf einmal) — welche der beiden gemeint ist, sagt `genutzteQuelle`.
        case werte([SocialValue])
        case fehler(String)
    }

    @Published private(set) var zustand: Zustand = .ruhe

    /// Welche Quelle tatsächlich in `zustand` steckt. Weicht von der Auswahl der Nutzerin ab,
    /// wenn ein Rückfall lief (siehe `lade(bevorzugt:...)`) — die Anzeige braucht das, um den
    /// Fallback-Hinweis und die Quellenangabe korrekt zu zeigen.
    @Published private(set) var genutzteQuelle: SozialdatenView.Quelle?

    /// **Hier stand ein Wörterbuch im Arbeitsspeicher mit einer Viertelstunde Haltbarkeit.**
    /// Es war bei jedem App-Start weg — wer die App zwischendurch schliesst, holte dieselben
    /// Zahlen wieder neu, über eine Rasterabfrage von rund fünfzehn Sekunden, und belastete
    /// dabei einen Server, den die Statistischen Ämter kostenlos bereitstellen.
    ///
    /// Jetzt liegt der Zwischenspeicher auf der Platte und hält voreingestellt sieben Tage.
    /// Das ist grosszügig und trotzdem richtig: Zensus- und Regionalatlas-Zahlen ändern sich
    /// jährlich; eine Woche alte Werte sind exakt so gültig wie frisch geholte.
    private let zwischenspeicher = SozialdatenCache.geteilt

    /// Lädt die bevorzugte Quelle; liefert sie nichts (weder Wert noch Netzfehler — reines
    /// „hier gibt es dazu nichts"), wird einmal die andere Quelle versucht, bevor „leer" gilt.
    /// Vorbild: `loadSocialData` in Android, `ModernPosterMapScreen.kt`.
    ///
    /// Vorige Werte bleiben beim Nachladen sichtbar (Issue #141 in Android, hier nachgezogen):
    /// Nur der allererste Aufruf für einen Standort zeigt den Ladezustand, ein Quellen- oder
    /// Standortwechsel während bereits Werte da sind lädt still im Hintergrund. Anders als in
    /// Android bewusst OHNE stillen Wiederholungsversuch bei Netzfehlern und ohne Prüfung, ob
    /// der Standort noch „in der Nähe" des letzten Erfolgs liegt — beides sind reale Verfeinerungen
    /// dort, aber für den ersten Nachzug hier nicht nötig, um den Blitz-Effekt zu beheben.
    func lade(bevorzugt: SozialdatenView.Quelle, latitude: Double, longitude: Double) async {
        if case .werte = zustand {
            // bleibt sichtbar, siehe Dok oben
        } else {
            zustand = .laedt
        }

        let erste = await ladeQuelle(bevorzugt, latitude: latitude, longitude: longitude)
        guard !Task.isCancelled else { return }
        if !erste.werte.isEmpty {
            genutzteQuelle = bevorzugt
            zustand = .werte(erste.werte)
            return
        }

        let andere: Quellenergebnis = bevorzugt == .zensus
            ? await regionalatlasAlle(latitude: latitude, longitude: longitude)
            : await zensusRaster(latitude: latitude, longitude: longitude)
        guard !Task.isCancelled else { return }
        if !andere.werte.isEmpty {
            genutzteQuelle = bevorzugt == .zensus ? .regionalatlas : .zensus
            zustand = .werte(andere.werte)
            return
        }

        genutzteQuelle = nil
        if erste.netzfehler || andere.netzfehler {
            zustand = .fehler("Die Sozialdaten sind gerade nicht erreichbar. Ohne Netz geht es nicht.")
        } else {
            zustand = .leer
        }
    }

    private struct Quellenergebnis {
        var werte: [SocialValue] = []
        var netzfehler = false
    }

    private func ladeQuelle(
        _ quelle: SozialdatenView.Quelle, latitude: Double, longitude: Double
    ) async -> Quellenergebnis {
        quelle == .zensus
            ? await zensusRaster(latitude: latitude, longitude: longitude)
            : await regionalatlasAlle(latitude: latitude, longitude: longitude)
    }

    /// Das Zensus-Gitter: eine Abfrage ueber 49 Zellen, alle Kennzahlen auf einmal.
    private func zensusRaster(latitude: Double, longitude: Double) async -> Quellenergebnis {
        do {
            let roh = try await lade(
                ZensusRaster.baueUrl(longitude: longitude, latitude: latitude),
                zeitgrenze: 25
            )
            return Quellenergebnis(werte: ZensusRaster.auswerten(roh))
        } catch is CancellationError {
            return Quellenergebnis()
        } catch {
            return Quellenergebnis(netzfehler: true)
        }
    }

    /// Alle zehn Regionalatlas-Kennzahlen parallel, statt nacheinander bei jedem Wechsel der
    /// Auswahl im Kennzahl-Picker neu zu laden. Ein Netzfehler bei einer einzelnen Kennzahl lässt
    /// die übrigen neun nicht scheitern — nur wenn KEINE einzige einen Wert liefert, zählt das
    /// Ergebnis als Fehlschlag. Vorbild: `SocialDataRepository.fetchFresh` in Android, dort mit
    /// `async {}.awaitAll()`.
    private func regionalatlasAlle(latitude: Double, longitude: Double) async -> Quellenergebnis {
        await withTaskGroup(of: (SocialValue?, Bool).self) { gruppe in
            for indikator in SocialIndicator.alle {
                gruppe.addTask {
                    // Erst die Gemeinde, dann der Kreis. Viele Kennzahlen gibt es nur gröber —
                    // dann steht beim Ergebnis eben „Kreis", statt dass gar nichts kommt.
                    let ebenen: [RegionLevel] =
                        indikator.availableAtGemeinde ? [.GEMEINDE, .KREIS] : [.KREIS]
                    var netzfehler = false
                    for ebene in ebenen {
                        do {
                            let roh = try await self.lade(
                                RegionalAtlas.buildUrl(
                                    indicator: indikator, level: ebene,
                                    longitude: longitude, latitude: latitude
                                )
                            )
                            if let wert = RegionalAtlas.parseResponse(roh, indicator: indikator, level: ebene) {
                                return (wert, false)
                            }
                        } catch is CancellationError {
                            return (nil, false)
                        } catch {
                            netzfehler = true
                        }
                    }
                    return (nil, netzfehler)
                }
            }
            var ergebnis = Quellenergebnis()
            for await (wert, netzfehler) in gruppe {
                if let wert { ergebnis.werte.append(wert) }
                if netzfehler { ergebnis.netzfehler = true }
            }
            return ergebnis
        }
    }

    /// `zeitgrenze` ist ein Parameter, weil die beiden Quellen sich stark unterscheiden: Der
    /// Regionalatlas antwortet in Sekunden, die Rasterabfrage ueber 49 Zellen braucht rund
    /// fuenfzehn. Mit zwoelf Sekunden fuer beide waere das Raster nie durchgekommen.
    private func lade(_ url: String, zeitgrenze: TimeInterval = 12) async throws -> String {
        if let vorhanden = zwischenspeicher.hole(url) { return vorhanden }
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
        zwischenspeicher.merke(url, text)
        return text
    }
}
