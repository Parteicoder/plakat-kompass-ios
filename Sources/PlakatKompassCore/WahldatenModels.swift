import Foundation

/// Amtliche Wahlergebnisse für den Wahlkreis/Kreis/Gemeinde unter der Kartenmitte. Gegenstück zu
/// `feature/wahldaten/WahldatenModels.kt` auf Android.
///
/// Fünf Wahlarten, aber nie mehrere gleichzeitig sichtbar: eine ist ausgewählt, die Kartenmitte
/// entscheidet nur, WELCHE Instanz dieser Wahlart gilt (welches Bundesland, welcher Wahlkreis) —
/// nicht, welche Wahlart angezeigt wird.
public enum Wahlart: String, CaseIterable, Sendable, Equatable {
    case bundestag, europa, landtag, kreistag, kommunal

    public var label: String {
        switch self {
        case .bundestag: return "Bundestagswahl"
        case .europa: return "Europawahl"
        case .landtag: return "Landtagswahl"
        case .kreistag: return "Kreistagswahl"
        case .kommunal: return "Gemeinderatswahl"
        }
    }
}

/// Verwaltungsebene, auf der ein Ergebnis vorliegt.
public enum WahlEbene: String, Sendable, Equatable {
    case wahlkreis, kreis, gemeinde

    public var label: String {
        switch self {
        case .wahlkreis: return "Wahlkreis"
        case .kreis: return "Kreis"
        case .gemeinde: return "Gemeinde"
        }
    }
}

/// Deutsche Verwaltungsgeografie, so weit dieses Feature sie braucht — die 16 zweistelligen
/// Landeskennzahlen (erste zwei Ziffern des amtlichen Gemeindeschlüssels) und die drei
/// Stadtstaaten, die keine Landkreise haben und deshalb keine Kreistagswahl kennen.
public enum Land {
    public static let bundeslaender: [String: String] = [
        "01": "Schleswig-Holstein", "02": "Hamburg", "03": "Niedersachsen", "04": "Bremen",
        "05": "Nordrhein-Westfalen", "06": "Hessen", "07": "Rheinland-Pfalz",
        "08": "Baden-Württemberg", "09": "Bayern", "10": "Saarland", "11": "Berlin",
        "12": "Brandenburg", "13": "Mecklenburg-Vorpommern", "14": "Sachsen",
        "15": "Sachsen-Anhalt", "16": "Thüringen"
    ]

    public static let stadtstaaten: Set<String> = ["02", "04", "11"]

    /// Hamburg veröffentlicht keinen eigenen Datensatz für die Bezirksversammlungswahl — er ist
    /// deckungsgleich mit der Bürgerschaftswahl. Der Fallback steht in `WahldatenRepository`.
    public static let hamburg = "02"
}

/// Woher die Ergebnisdatei kommt. Gegenstück zur `Wahlquelle`-`sealed interface` auf Android,
/// dort mit den drei ehemals eigenständigen Landtag-/Kreistag-/Kommunal-Fällen zu `LandDatei`
/// vereinheitlicht (siehe `Wahlquelle.LandDatei` dort) — hier von Anfang an ein Fall.
public enum Wahlquelle: Sendable, Equatable {
    /// Eine Datei je Bundesland, `dateiname` unterscheidet Landtag/Kreistag/Kommunal.
    case landDatei(dateiname: String, landkennzahl: String)
    /// Eine feste, bundesweite Datei (Bundestags- und Europawahl).
    case plakatKompassJson(url: String, cacheDatei: String)

    public var url: String {
        switch self {
        case .landDatei(let dateiname, let landkennzahl):
            return "https://daten.plakat-kompass.de/\(landkennzahl)/\(dateiname).json"
        case .plakatKompassJson(let url, _):
            return url
        }
    }

    public var cacheDatei: String {
        switch self {
        case .landDatei(let dateiname, let landkennzahl):
            return "\(dateiname)_\(landkennzahl).json"
        case .plakatKompassJson(_, let cacheDatei):
            return cacheDatei
        }
    }

    /// Die drei `dateiname`-Werte für `.landDatei`, benannt statt als Zeichenkettenliteral
    /// verstreut — ein Tippfehler darin wäre sonst erst beim leeren Ergebnis aufgefallen.
    public enum LandDateiName {
        public static let landtag = "landtag"
        public static let kreistag = "kreistag"
        public static let kommunal = "kommunal"
    }
}

/// Welche Wahl gemeint ist — Art, Jahr, Ebene, Anzeigetitel, Quelle. Für `.landDatei`-Quellen ist
/// `jahr` beim Bau noch `0`; das echte Jahr steht erst nach dem Parsen der Antwort fest (siehe
/// `parseLandtagJson`).
public struct WahlKennung: Sendable, Equatable {
    public let art: Wahlart
    public let jahr: Int
    public let ebene: WahlEbene
    public let titel: String
    public let quelle: Wahlquelle

    public init(art: Wahlart, jahr: Int, ebene: WahlEbene, titel: String, quelle: Wahlquelle) {
        self.art = art
        self.jahr = jahr
        self.ebene = ebene
        self.titel = titel
        self.quelle = quelle
    }

    /// `jahr == 0` heißt bei `.landDatei`-Quellen "noch nicht geparst", nicht "sehr alt" — vor dem
    /// ersten `parseLandtagJson`-Aufruf gilt eine Wahl deshalb als weder archiviert noch aktuell.
    public func istArchiv(aktuellesJahr: Int) -> Bool { jahr != 0 && jahr < aktuellesJahr }

    /// Mit anderer Ebene — der Kandidat kennt seine tatsächliche Ebene erst nach der
    /// Gebietssuche, davor steht nur die Wahlart fest.
    public func mit(ebene: WahlEbene) -> WahlKennung {
        WahlKennung(art: art, jahr: jahr, ebene: ebene, titel: titel, quelle: quelle)
    }
}

public struct Parteiergebnis: Sendable, Equatable {
    public let partei: String
    public let prozent: Double

    public init(partei: String, prozent: Double) {
        self.partei = partei
        self.prozent = prozent
    }
}

public struct Wahlergebnis: Sendable, Equatable {
    public let wahl: WahlKennung
    public let beteiligung: Double?
    public let parteien: [Parteiergebnis]
    public let quellenangabe: String

    public init(wahl: WahlKennung, beteiligung: Double?, parteien: [Parteiergebnis], quellenangabe: String) {
        self.wahl = wahl
        self.beteiligung = beteiligung
        self.parteien = parteien
        self.quellenangabe = quellenangabe
    }
}

/// Zustand der Wahldaten-Abfrage. `empty` heißt hier ausschließlich: der Punkt liegt außerhalb
/// aller 299 Bundestagswahlkreise — der einzige Fall mit lokaler Geometrie statt Netzabfrage.
/// Jeder andere Fehlschlag (kein Bundesland bestimmbar, Stadtstaat ohne Kreistag, Netzfehler) ist
/// `error` mit einer sprechenden Meldung.
public enum WahldatenUiState: Sendable, Equatable {
    case loading
    case success(gebietsname: String, ergebnis: Wahlergebnis, flaeche: Wahlflaeche?)
    case empty
    case error(String)
}

/// Fasst Parteien unter zwei Prozent für die Anzeige zusammen. Die Rohdaten bleiben vollständig,
/// damit der Schalter „Alle Parteien“ ohne neuen Netzabruf wirkt.
public func fasseKleineZusammen(
    _ parteien: [Parteiergebnis], schwelle: Double = 2.0
) -> [Parteiergebnis] {
    let sonstigeName = "Sonstige"
    let grosse = parteien.filter {
        $0.prozent >= schwelle && $0.partei.caseInsensitiveCompare(sonstigeName) != .orderedSame
    }
    let kleine = parteien.filter {
        $0.prozent < schwelle || $0.partei.caseInsensitiveCompare(sonstigeName) == .orderedSame
    }
    guard !kleine.isEmpty else { return parteien }

    let sortiert = grosse.sorted {
        $0.partei.localizedCaseInsensitiveCompare($1.partei) == .orderedAscending
    }
    return sortiert + [Parteiergebnis(
        partei: sonstigeName, prozent: kleine.reduce(0) { $0 + $1.prozent }
    )]
}

/// Geteilte JSON-Zahl-Konvertierung für `LandtagJsonParser.swift` und `WahldatenGeometrie.swift` —
/// beide lasen bislang denselben Code je einmal für sich, siehe `CommuneBoundary.kommazahl` für
/// den ursprünglichen Grund (Apples Foundation und swift-corelibs-foundation bilden eine
/// JSON-Zahl auf unterschiedliche konkrete Typen ab).
///
/// `Bool` wird ausdrücklich zuerst ausgeschlossen: `JSONSerialization` liefert ein JSON `true`
/// unter Apples Foundation als `__NSCFBoolean`, eine private `NSNumber`-Unterklasse, die sonst
/// unbemerkt als `1.0` durchginge (`roh as? Double` würde sonst erfolgreich sein).
func zahlAusJson(_ roh: Any) -> Double? {
    if let zahl = roh as? NSNumber, CFGetTypeID(zahl) == CFBooleanGetTypeID() { return nil }
    if let zahl = roh as? Double { return zahl.isFinite ? zahl : nil }
    if let zahl = roh as? Int { return Double(zahl) }
    if let zahl = roh as? NSNumber { return zahl.doubleValue.isFinite ? zahl.doubleValue : nil }
    if let text = roh as? String, let zahl = Double(text), zahl.isFinite { return zahl }
    return nil
}

/// `Int(Double)` ohne Absturz: `Int.init(Double)` trapt bei einem endlichen, aber
/// bereichsüberschreitenden Wert (z. B. `1e20`) statt `nil` zu liefern.
func intAusJson(_ zahl: Double) -> Int? { Int(exactly: zahl) }
