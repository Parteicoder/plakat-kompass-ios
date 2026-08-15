import Foundation

/// Liest die einheitliche Ergebnisdatei-Struktur, die alle `Wahlquelle`n teilen — je Bundesland
/// eine Landtags-/Kreistags-/Kommunalwahl-Datei, dazu die bundesweite Bundestags- und
/// Europawahl-Datei, alle vier vom selben Aufbau. Gegenstück zu
/// `feature/wahldaten/LandtagJsonParser.kt`.
///
/// Erwartete Form:
/// ```json
/// {
///   "land": "08", "titel": "Landtagswahl Baden-Württemberg 2026", "jahr": 2026,
///   "quelle": "GERDA – German Election Database",
///   "lizenz": "Creative Commons Namensnennung 4.0 International (CC BY 4.0)",
///   "gebiete": {
///     "08111000": { "name": "Stuttgart, Landeshauptstadt", "beteiligung": 70.8,
///                    "parteien": { "GRÜNE": 40.9, "CDU": 24.4 } }
///   }
/// }
/// ```
public func parseLandtagJson(bytes: Data, gebietsschluessel: String, wahl: WahlKennung) -> Wahlergebnis? {
    let text = alsJsonText(bytes)
    guard let daten = text.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
          let gebiete = root["gebiete"] as? [String: Any],
          let gebiet = gebiete[gebietsschluessel] as? [String: Any]
    else { return nil }

    let parteienRoh = gebiet["parteien"] as? [String: Any] ?? [:]
    var parteienWerte: [String: Double] = [:]
    for (partei, wert) in parteienRoh {
        // 0,0-%-Einträge verwerfen: eine Partei, die nicht angetreten ist oder auf null gerundet
        // wurde, soll nicht als Zeile mit "0,0 %" auftauchen.
        guard let prozent = zahlAusJson(wert), prozent > 0 else { continue }
        parteienWerte[partei] = prozent
    }

    // Werte außerhalb [0,100] (z. B. der Sachsen->100-%-Briefwahl-Artefakt) auf nil setzen statt
    // eine falsche Zahl anzuzeigen — die Parteiwerte bleiben davon unberührt.
    let beteiligung: Double? = (gebiet["beteiligung"]).flatMap(zahlAusJson).flatMap {
        (0...100).contains($0) ? $0 : nil
    }

    // Nur wenn WEDER Parteien noch Beteiligung etwas Brauchbares liefern, ist das Gebiet leer.
    // Eine kleine Gemeinde, in der jede Partei auf 0,0 % rundet, hat trotzdem eine echte
    // Beteiligung — die darf nicht mit verworfen werden, nur weil parteienWerte leer ist.
    guard !parteienWerte.isEmpty || beteiligung != nil else { return nil }

    let titel = (root["titel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? wahl.titel
    let jahr = root["jahr"].flatMap(zahlAusJson).flatMap(intAusJson) ?? wahl.jahr
    let neueWahl = WahlKennung(art: wahl.art, jahr: jahr, ebene: wahl.ebene, titel: titel, quelle: wahl.quelle)

    return Wahlergebnis(
        wahl: neueWahl,
        beteiligung: beteiligung,
        parteien: sortiereParteien(parteienWerte),
        quellenangabe: quellenangabe(root)
    )
}

/// Nur ein Formcheck ("sieht das nach JSON aus"), keine vollständige Validierung — eine
/// HTML-Fehlerseite soll nicht erst beim Parsen aus Versehen als gültige, leere Antwort
/// durchgehen. `public`, weil der spätere Netzwerk-Abruf (App-seitig, anderes Modul) die
/// Antwort damit vor dem Zwischenspeichern prüft.
public func sindLandtagJsonBytes(_ bytes: Data) -> Bool {
    alsJsonText(bytes).hasPrefix("{")
}

/// BOM zuerst entfernen, dann führende Leerzeichen trimmen — die Reihenfolge zählt: ein BOM vor
/// führenden Leerzeichen bliebe sonst als sichtbares Zeichen stehen.
private func alsJsonText(_ bytes: Data) -> String {
    var text = String(decoding: bytes, as: UTF8.self)
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    while let erstes = text.first, erstes.isWhitespace { text.removeFirst() }
    return text
}

private func quellenangabe(_ root: [String: Any]) -> String {
    let quelle = (root["quelle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Quelle nicht angegeben"
    if let lizenz = root["lizenz"] as? String, !lizenz.isEmpty {
        return "\(quelle) (\(lizenz))"
    }
    return quelle
}
