import Foundation
import PlakatKompassCore

/// Holt und ordnet Wahldaten für einen Kartenpunkt zu. Gegenstück zu `WahldatenRepository.kt`.
///
/// Die Zuordnung läuft in zwei Schritten, genau wie drüben: erst das **Gebiet** unter dem Punkt
/// bestimmen (lokale Geometrie für die Bundestagswahl, sonst Overpass), dann in der passenden
/// Ergebnisdatei nachschlagen. Das Zwischenergebnis der Gebietssuche wird hier nicht gehalten —
/// dafür sind `WahlkreisGrenzen`/`GebietsschluesselAbruf` schon selbst zwischengespeichert.
@MainActor
final class WahldatenRepository {

    static let bundestagswahl = WahlKennung(
        art: .bundestag, jahr: 2025, ebene: .wahlkreis, titel: "Bundestagswahl 2025",
        quelle: .plakatKompassJson(
            url: "https://daten.plakat-kompass.de/bundestagswahl-2025.json",
            cacheDatei: "plakat_kompass_bundestagswahl_2025.json"
        )
    )
    static let europawahl = WahlKennung(
        art: .europa, jahr: 2024, ebene: .kreis, titel: "Europawahl 2024",
        quelle: .plakatKompassJson(
            url: "https://daten.plakat-kompass.de/europawahl-2024.json",
            cacheDatei: "plakat_kompass_europawahl_2024.json"
        )
    )

    /// Nur Erfolge werden gehalten, keine Fehler — ein vorübergehender Netzausfall soll sich
    /// nicht als "kein Ergebnis" festsetzen. Schlüssel ist das Gebiet (Wahlart + amtlicher
    /// Schlüssel), nicht der Kartenausschnitt: Ein Schwenk innerhalb desselben Wahlkreises soll
    /// nicht neu parsen müssen.
    private var cache: [String: WahldatenUiState] = [:]

    func load(longitude: Double, latitude: Double, wahlart: Wahlart) async -> WahldatenUiState {
        switch await sucheGebiet(longitude: longitude, latitude: latitude, wahlart: wahlart) {
        case .fehler(let meldung):
            return .error(meldung)
        case .draussen:
            return .empty
        case .treffer(let wahl, let kandidaten):
            return await ergebnisFuer(wahl: wahl, kandidaten: kandidaten)
        }
    }

    // MARK: - Gebietssuche

    private struct Kandidat {
        let schluessel: String
        let name: String
        let ebene: WahlEbene
        let flaeche: Wahlflaeche?
    }

    private enum Gebietssuche {
        case treffer(wahl: WahlKennung, kandidaten: [Kandidat])
        case draussen
        case fehler(String)
    }

    private static let ohneGebietMeldung = "Zu diesem Punkt ließ sich das Gebiet nicht bestimmen."

    private func sucheGebiet(longitude: Double, latitude: Double, wahlart: Wahlart) async -> Gebietssuche {
        switch wahlart {
        case .bundestag:
            // Einzige Wahlart mit lokaler Geometrie - kein Netz nötig, kein Fehlerfall außer
            // "liegt draußen".
            guard let flaeche = flaecheAn(WahlkreisGrenzen.alle, longitude: longitude, latitude: latitude)
            else { return .draussen }
            return .treffer(
                wahl: Self.bundestagswahl,
                kandidaten: [Kandidat(schluessel: flaeche.kennung, name: flaeche.name, ebene: .wahlkreis, flaeche: flaeche)]
            )

        case .europa:
            guard let kreis = await GebietsschluesselAbruf.geteilt.kreis(latitude: latitude, longitude: longitude)
            else { return .fehler(Self.ohneGebietMeldung) }
            return .treffer(
                wahl: Self.europawahl,
                kandidaten: [Kandidat(schluessel: kreis.schluessel, name: kreis.name, ebene: .kreis, flaeche: nil)]
            )

        case .landtag:
            return await gemeindeGebunden(longitude: longitude, latitude: latitude, art: .landtag, titelPraefix: "Landtagswahl") {
                .landDatei(dateiname: Wahlquelle.LandDateiName.landtag, landkennzahl: $0)
            }

        case .kommunal:
            return await gemeindeGebunden(longitude: longitude, latitude: latitude, art: .kommunal, titelPraefix: "Gemeinderatswahl") {
                landkennzahl in
                // Hamburg veröffentlicht keinen eigenen Datensatz für die Bezirksversammlungswahl
                // - ersatzweise die Landtagsdatei, mit Hinweis in ergebnisFuer.
                let dateiname = landkennzahl == Land.hamburg
                    ? Wahlquelle.LandDateiName.landtag : Wahlquelle.LandDateiName.kommunal
                return .landDatei(dateiname: dateiname, landkennzahl: landkennzahl)
            }

        case .kreistag:
            guard let kreis = await GebietsschluesselAbruf.geteilt.kreis(latitude: latitude, longitude: longitude)
            else { return .fehler(Self.ohneGebietMeldung) }
            let landkennzahl = String(kreis.schluessel.prefix(2))
            guard !Land.stadtstaaten.contains(landkennzahl) else {
                let land = Land.bundeslaender[landkennzahl] ?? "Dieses Bundesland"
                return .fehler("\(land) ist ein Stadtstaat ohne Landkreise – keine Kreistagswahl.")
            }
            let wahl = WahlKennung(
                art: .kreistag, jahr: 0, ebene: .kreis, titel: "Kreistagswahl",
                quelle: .landDatei(dateiname: Wahlquelle.LandDateiName.kreistag, landkennzahl: landkennzahl)
            )
            return .treffer(
                wahl: wahl,
                kandidaten: [Kandidat(schluessel: kreis.schluessel, name: kreis.name, ebene: .kreis, flaeche: nil)]
            )
        }
    }

    /// Gemeinsamer Kern für Landtags- und Kommunalwahl: beide hängen an der Gemeinde unter dem
    /// Punkt, unterscheiden sich nur im Titel-Präfix und darin, welche `Wahlquelle` aus der
    /// Landeskennzahl folgt.
    private func gemeindeGebunden(
        longitude: Double, latitude: Double, art: Wahlart, titelPraefix: String,
        quelle: (String) -> Wahlquelle
    ) async -> Gebietssuche {
        guard let gemeinde = await GebietsschluesselAbruf.geteilt.gemeinde(latitude: latitude, longitude: longitude)
        else { return .fehler(Self.ohneGebietMeldung) }
        let landkennzahl = String(gemeinde.schluessel.prefix(2))
        guard let land = Land.bundeslaender[landkennzahl] else {
            return .fehler("Zu diesem Punkt ließ sich kein Bundesland bestimmen.")
        }
        let wahl = WahlKennung(
            art: art, jahr: 0, ebene: .gemeinde, titel: "\(titelPraefix) \(land)", quelle: quelle(landkennzahl)
        )
        return .treffer(
            wahl: wahl,
            kandidaten: [Kandidat(schluessel: gemeinde.schluessel, name: gemeinde.name, ebene: .gemeinde, flaeche: nil)]
        )
    }

    // MARK: - Ergebnisdatei

    private func ergebnisFuer(wahl: WahlKennung, kandidaten: [Kandidat]) async -> WahldatenUiState {
        let cacheSchluessel = "\(wahl.art.rawValue):\(kandidaten.first?.schluessel ?? "")"
        if let vorhanden = cache[cacheSchluessel] { return vorhanden }

        guard let bytes = await ErgebnisdateiAbruf.lade(wahl.quelle) else {
            return .error("Die amtliche Ergebnisdatei ist gerade nicht erreichbar (\(wahl.titel)).")
        }

        for kandidat in kandidaten {
            guard let ergebnis = parseLandtagJson(
                bytes: bytes, gebietsschluessel: kandidat.schluessel, wahl: wahl.mit(ebene: kandidat.ebene)
            ) else { continue }

            let zustand = WahldatenUiState.success(
                gebietsname: kandidat.name, ergebnis: mitHamburgHinweisFallsNoetig(ergebnis, wahl: wahl),
                flaeche: kandidat.flaeche
            )
            cache[cacheSchluessel] = zustand
            return zustand
        }

        let erster = kandidaten.first
        return .error(
            "Zu \(erster?.ebene.label ?? "Gebiet") \(erster?.schluessel ?? "") (\(erster?.name ?? "")) "
                + "steht in der amtlichen Datei kein Ergebnis."
        )
    }

    /// Hamburgs Kommunalwahl-Ergebnis ist in Wirklichkeit die Bürgerschaftswahl (siehe
    /// `sucheGebiet`/`.kommunal`) — das muss in der Quellenangabe stehen, sonst sieht es nach
    /// einem echten Bezirksversammlungswahl-Ergebnis aus.
    private func mitHamburgHinweisFallsNoetig(_ ergebnis: Wahlergebnis, wahl: WahlKennung) -> Wahlergebnis {
        guard wahl.art == .kommunal, case .landDatei(let dateiname, _) = wahl.quelle,
              dateiname == Wahlquelle.LandDateiName.landtag
        else { return ergebnis }

        return Wahlergebnis(
            wahl: ergebnis.wahl, beteiligung: ergebnis.beteiligung, parteien: ergebnis.parteien,
            quellenangabe: ergebnis.quellenangabe
                + " — Hamburg hat noch keine eigene Bezirksversammlungswahl-Datenquelle, ersatzweise die Bürgerschaftswahl."
        )
    }

    // MARK: - Zwischenspeicher (für die Einstellungsseite)

    /// Jede denkbare Ergebnisdatei — auch die, die noch nie geladen wurden (zählen dann als
    /// 0 Byte). Gegenstück zu `WahldatenRepository.alleQuellen()`.
    static func alleQuellen() -> [Wahlquelle] {
        var quellen: [Wahlquelle] = [bundestagswahl.quelle, europawahl.quelle]
        for land in Land.bundeslaender.keys.sorted() {
            quellen.append(.landDatei(dateiname: Wahlquelle.LandDateiName.landtag, landkennzahl: land))
            if land != Land.hamburg {
                quellen.append(.landDatei(dateiname: Wahlquelle.LandDateiName.kommunal, landkennzahl: land))
            }
            if !Land.stadtstaaten.contains(land) {
                quellen.append(.landDatei(dateiname: Wahlquelle.LandDateiName.kreistag, landkennzahl: land))
            }
        }
        return quellen
    }

    static func cacheSizeBytes() -> Int64 {
        ErgebnisdateiCache.groesseBytes(alleQuellen().map(\.cacheDatei))
    }

    static func clearCache() {
        ErgebnisdateiCache.leeren(alleQuellen().map(\.cacheDatei))
    }
}
