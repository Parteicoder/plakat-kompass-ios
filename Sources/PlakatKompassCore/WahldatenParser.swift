import Foundation

/// Anzeige-Aufbereitung der Parteiergebnisse — reine Darstellungslogik, getrennt vom Parsen
/// selbst, damit "alle Parteien anzeigen" umschalten keinen erneuten Abruf braucht. Gegenstück zu
/// `feature/wahldaten/WahldatenParser.kt`.

public let sammelpostenSonstige = "Sonstige"
public let schwelleSonstige = 2.0

/// Fasst Parteien unter `schwelle` Prozent zu einem "Sonstige"-Posten zusammen. Eine bereits
/// vorhandene "Sonstige"-Zeile aus der Quelle wird in die Summe eingerechnet statt verdoppelt.
/// Ohne etwas zum Zusammenfassen bleibt die Liste unverändert — kein leerer Bucket-Eintrag.
public func fasseKleineZusammen(_ parteien: [Parteiergebnis], schwelle: Double = schwelleSonstige) -> [Parteiergebnis] {
    var gross: [Parteiergebnis] = []
    var klein: [Parteiergebnis] = []
    for partei in parteien {
        let istSonstige = partei.partei.caseInsensitiveCompare(sammelpostenSonstige) == .orderedSame
        if partei.prozent >= schwelle && !istSonstige {
            gross.append(partei)
        } else {
            klein.append(partei)
        }
    }
    guard !klein.isEmpty else { return parteien }

    var werte: [String: Double] = [:]
    for partei in gross { werte[partei.partei] = partei.prozent }
    werte[sammelpostenSonstige] = (werte[sammelpostenSonstige] ?? 0) + klein.reduce(0) { $0 + $1.prozent }
    return sortiereParteien(werte)
}

/// Alphabetisch, ohne Rücksicht auf Groß-/Kleinschreibung — nie nach Stimmenanteil, damit die
/// Anzeige keine Partei bevorzugt. "Sonstige" steht immer zuletzt, unabhängig vom Alphabet.
public func sortiereParteien(_ werte: [String: Double]) -> [Parteiergebnis] {
    werte
        .map { Parteiergebnis(partei: $0.key, prozent: $0.value) }
        .sorted { a, b in
            let aIstSonstige = a.partei.caseInsensitiveCompare(sammelpostenSonstige) == .orderedSame
            let bIstSonstige = b.partei.caseInsensitiveCompare(sammelpostenSonstige) == .orderedSame
            if aIstSonstige { return false }
            if bIstSonstige { return true }
            return a.partei.caseInsensitiveCompare(b.partei) == .orderedAscending
        }
}
