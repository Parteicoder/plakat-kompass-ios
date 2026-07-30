import Foundation

/// Wie ein Rasterwert aus den Zellen im Umkreis zusammengefasst wird.
public enum ZensusAggregat: Sendable {
    /// Summe eines Zählfelds über alle Zellen, etwa Einwohner im Umkreis.
    case summe

    /// Σ Zähler / Σ Nenner × 100 — nur wenn beides **Stückzahlen** sind. Felder, die der Dienst
    /// schon als Prozentwert liefert, gehören zu `gewichteterMittelwert`; sie zu summieren ergäbe
    /// Unsinn.
    case verhaeltnis

    /// Einwohnergewichteter Mittelwert. Ohne die Gewichtung zählte eine Zelle mit drei Bewohnern
    /// so viel wie eine mit dreihundert.
    case gewichteterMittelwert
}

/// Eine Kennzahl des Zensus-2022-Gitters.
///
/// Hier stehen nur **Feldnamen und Rechenregeln** — keine Statistikwerte. Die Zahlen kommen live
/// vom öffentlichen Dienst.
public struct ZensusKennzahl: Sendable {
    public let id: String
    public let label: String
    public let kategorie: String
    public let einheit: SocialUnit
    public let aggregat: ZensusAggregat
    /// Feldname(n) im Layer, klein geschrieben verglichen.
    public let wertFelder: [String]
    /// Nennerfeld, nur bei `verhaeltnis`.
    public let nennerFelder: [String]
    public let plausibelMin: Double
    public let plausibelMax: Double

    /// Als `SocialIndicator`, damit `SocialValue` und die Anzeige unverändert bleiben.
    ///
    /// `tableCode` und `attributeCode` sind leer: Die gehören zum Regionalatlas und haben beim
    /// Raster keine Entsprechung. Das ist bewusst der kleinere Preis — die Alternative wäre, den
    /// Indikator zu einem Protokoll zu machen und damit jede vorhandene Stelle anzufassen, die
    /// heute funktioniert und geprüft ist.
    public var alsIndikator: SocialIndicator {
        SocialIndicator(
            id: id, label: label, category: kategorie,
            tableCode: "", attributeCode: "", unit: einheit,
            availableAtGemeinde: false,
            plausibleMin: plausibelMin, plausibleMax: plausibelMax
        )
    }
}

/// Das amtliche Zensus-2022-Gitter über den öffentlichen ArcGIS-Dienst, ohne Schlüssel.
///
/// Gegenstück zu `feature/socialdata/zensus/` auf Android. Warum über Zellkennungen und nicht
/// räumlich: Räumliche Punkt- und Rechteckabfragen beantwortet dieser Layer mit 400 oder mit
/// Zeitüberschreitungen. Die attributbasierte Abfrage trägt.
public enum ZensusRaster {

    public static let endpunkt =
        "https://services2.arcgis.com/jUpNdisbWqRpMo35/arcgis/rest/services/Zensus2022_grid_final/FeatureServer/0/query"

    public static let quellenangabe = "Zensus 2022 – Statistische Ämter des Bundes und der Länder"

    public static let jahr = 2022

    /// Umkreis der Abfrage in Metern.
    ///
    /// 300 m bei 100-m-Zellen sind drei Zellen in jede Richtung, also 49 Stück. Auf diese Zahl ist
    /// die Laufzeit abgestimmt — die Abfrage braucht damit rund fünfzehn Sekunden. Größer heißt
    /// quadratisch mehr Zellen und irgendwann eine Zeitüberschreitung; kleiner heißt, dass die
    /// Werte an einer Straßenecke schon wieder andere sind als ein Haus weiter.
    public static let radiusMeter = 300

    /// Wie viele Zellen ein Umkreis umfasst. Steht hier, damit die Beziehung zwischen Radius und
    /// Zellenzahl an einer Stelle nachlesbar und prüfbar ist.
    public static func zellenAnzahl(radiusMeter: Int = radiusMeter) -> Int {
        let schritte = max(1, (radiusMeter + 99) / 100)
        return (2 * schritte + 1) * (2 * schritte + 1)
    }

    /// Angefragte Felder — nicht `*`, das spart Antwortgröße. Schreibweise wie im Layer.
    public static let ausgabeFelder = [
        "id", "ags", "Einwohner", "AnteilAuslaender", "Durchschnittsalter",
        "Unter18", "a65undaelter", "DurchschnHHGroesse", "durchschnFlaechejeBew",
        "durchschnMieteQM", "Eigentuemerquote", "Leerstandsquote"
    ].joined(separator: ",")

    /// Einwohnerfeld — das Gewicht für den gewichteten Mittelwert.
    static let einwohnerFelder = ["einwohner"]

    public static let kennzahlen: [ZensusKennzahl] = [
        ZensusKennzahl(
            id: "DURCHSCHNITTSALTER_RASTER", label: "Durchschnittsalter", kategorie: "Alter",
            einheit: .years, aggregat: .gewichteterMittelwert,
            wertFelder: ["durchschnittsalter"], nennerFelder: [],
            plausibelMin: 15, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "AUSLAENDERANTEIL_RASTER", label: "Ausländeranteil", kategorie: "Migration",
            // Der Dienst liefert hier bereits Prozent, nicht die Stückzahl — deshalb Mittelwert
            // und nicht Verhältnis.
            einheit: .percent, aggregat: .gewichteterMittelwert,
            wertFelder: ["anteilauslaender"], nennerFelder: [],
            plausibelMin: 0, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "ANTEIL_UNTER_18", label: "Unter 18 Jahre", kategorie: "Alter",
            // Aus den Stückzahlen gerechnet: genauer als der Mittelwert eines fertigen
            // Prozentfelds, weil kleine Zellen sonst dasselbe Gewicht bekämen wie große.
            einheit: .percent, aggregat: .verhaeltnis,
            wertFelder: ["unter18"], nennerFelder: einwohnerFelder,
            plausibelMin: 0, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "ANTEIL_UEBER_65", label: "Ab 65 Jahre", kategorie: "Alter",
            einheit: .percent, aggregat: .verhaeltnis,
            wertFelder: ["a65undaelter"], nennerFelder: einwohnerFelder,
            plausibelMin: 0, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "HAUSHALTSGROESSE", label: "Haushaltsgröße", kategorie: "Wohnen",
            einheit: .personen, aggregat: .gewichteterMittelwert,
            wertFelder: ["durchschnhhgroesse"], nennerFelder: [],
            plausibelMin: 1, plausibelMax: 10
        ),
        ZensusKennzahl(
            id: "WOHNFLAECHE_PERSON", label: "Wohnfläche je Person", kategorie: "Wohnen",
            einheit: .quadratmeter, aggregat: .gewichteterMittelwert,
            wertFelder: ["durchschnflaechejebew"], nennerFelder: [],
            plausibelMin: 5, plausibelMax: 200
        ),
        ZensusKennzahl(
            id: "MIETE_QM", label: "Nettokaltmiete je m²", kategorie: "Wohnen",
            einheit: .euroProQm, aggregat: .gewichteterMittelwert,
            wertFelder: ["durchschnmieteqm"], nennerFelder: [],
            plausibelMin: 1, plausibelMax: 50
        ),
        ZensusKennzahl(
            id: "LEERSTANDSQUOTE", label: "Leerstand", kategorie: "Wohnen",
            einheit: .percent, aggregat: .gewichteterMittelwert,
            wertFelder: ["leerstandsquote"], nennerFelder: [],
            plausibelMin: 0, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "EIGENTUEMERQUOTE", label: "Eigentümerquote", kategorie: "Wohnen",
            einheit: .percent, aggregat: .gewichteterMittelwert,
            wertFelder: ["eigentuemerquote"], nennerFelder: [],
            plausibelMin: 0, plausibelMax: 100
        ),
        ZensusKennzahl(
            id: "EINWOHNER", label: "Einwohner im Umkreis", kategorie: "Bevölkerung",
            einheit: .anzahl, aggregat: .summe,
            wertFelder: einwohnerFelder, nennerFelder: [],
            plausibelMin: 0, plausibelMax: 10_000_000
        )
    ]

    /// Baut die Abfrage-Adresse für die Zellen um einen Kartenpunkt.
    public static func baueUrl(
        longitude: Double,
        latitude: Double,
        radiusMeter: Int = radiusMeter
    ) -> String {
        let zellen = Epsg3035.zellenUm(
            longitude: longitude, latitude: latitude, radiusMeter: radiusMeter
        )
        let where_ = "id IN (\(zellen.map { "'\($0)'" }.joined(separator: ",")))"
        let parameter: [(String, String)] = [
            ("where", where_),
            ("outFields", ausgabeFelder),
            ("returnGeometry", "false"),
            ("resultRecordCount", String(min(zellen.count, 200))),
            ("f", "json")
        ]
        let abfrage = parameter
            .map { "\($0.0)=\(kodiert($0.1))" }
            .joined(separator: "&")
        return "\(endpunkt)?\(abfrage)"
    }

    /// Wertet die Antwort des Dienstes aus. Rein — kein Netz, keine Uhr, kein Zustand.
    public static func auswerten(_ rohJson: String) -> [SocialValue] {
        guard let daten = rohJson.data(using: .utf8),
              let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              wurzel["error"] == nil,
              let merkmale = wurzel["features"] as? [[String: Any]],
              !merkmale.isEmpty
        else { return [] }

        // Feldnamen klein, damit die Schreibweise des Dienstes egal ist.
        let zellen: [[String: Any]] = merkmale.compactMap { merkmal in
            guard let werte = merkmal["attributes"] as? [String: Any] else { return nil }
            var klein: [String: Any] = [:]
            for (schluessel, wert) in werte { klein[schluessel.lowercased()] = wert }
            return klein
        }
        guard !zellen.isEmpty else { return [] }

        // Das Gitter kennt keine Ortsnamen, nur Codes. Ein neutraler Titel ist ehrlicher als ein
        // roher Code, den niemand lesen kann.
        let gebiet = "Kartenausschnitt"

        return kennzahlen.compactMap { kennzahl in
            guard let roh = rechne(zellen: zellen, kennzahl: kennzahl),
                  roh >= kennzahl.plausibelMin, roh <= kennzahl.plausibelMax
            else { return nil }
            return SocialValue(
                indicator: kennzahl.alsIndikator,
                value: roh,
                year: jahr,
                level: .RASTER,
                regionName: gebiet
            )
        }
    }

    static func rechne(zellen: [[String: Any]], kennzahl: ZensusKennzahl) -> Double? {
        switch kennzahl.aggregat {
        case .summe:
            var summe = 0.0
            var gefunden = false
            for zelle in zellen {
                guard let w = zellenWert(zelle, kennzahl.wertFelder), w >= 0 else { continue }
                summe += w
                gefunden = true
            }
            return gefunden ? summe : nil

        case .verhaeltnis:
            var zaehler = 0.0
            var nenner = 0.0
            for zelle in zellen {
                if let z = zellenWert(zelle, kennzahl.wertFelder), z >= 0 { zaehler += z }
                if let n = zellenWert(zelle, kennzahl.nennerFelder), n >= 0 { nenner += n }
            }
            return nenner > 0 ? zaehler / nenner * 100.0 : nil

        case .gewichteterMittelwert:
            var gewichtet = 0.0
            var gewichtSumme = 0.0
            var schlicht = 0.0
            var schlichtAnzahl = 0
            for zelle in zellen {
                guard let w = zellenWert(zelle, kennzahl.wertFelder), w >= 0 else { continue }
                schlicht += w
                schlichtAnzahl += 1
                if let g = zellenWert(zelle, einwohnerFelder), g > 0 {
                    gewichtet += w * g
                    gewichtSumme += g
                }
            }
            if gewichtSumme > 0 { return gewichtet / gewichtSumme }
            // Kein Einwohnerfeld dabei: lieber der schlichte Mittelwert als gar nichts.
            if schlichtAnzahl > 0 { return schlicht / Double(schlichtAnzahl) }
            return nil
        }
    }

    static func zellenWert(_ zelle: [String: Any], _ kandidaten: [String]) -> Double? {
        for feld in kandidaten {
            if let roh = zelle[feld], let zahl = alsZahl(roh) { return zahl }
        }
        return nil
    }

    /// NaN und Unendlich gelten als „kein Wert".
    ///
    /// Ohne diese Prüfung rutschen sie an den Plausibilitätsgrenzen und am `>= 0` vorbei — jeder
    /// Vergleich mit NaN ist falsch — und machen dann ein ganzes Aggregat zu NaN. Auf Android war
    /// das ein eigener Fehlerbericht.
    static func alsZahl(_ roh: Any) -> Double? {
        let wert: Double?
        switch roh {
        case let zahl as Double: wert = zahl
        case let zahl as Int: wert = Double(zahl)
        case let zahl as NSNumber: wert = zahl.doubleValue
        case let text as String:
            let sauber = text.trimmingCharacters(in: .whitespaces)
            if sauber.isEmpty || sauber.lowercased() == "null" || sauber == "-" {
                wert = nil
            } else if sauber.contains(".") && sauber.contains(",") {
                wert = Double(sauber.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: "."))
            } else if sauber.contains(",") {
                wert = Double(sauber.replacingOccurrences(of: ",", with: "."))
            } else {
                wert = Double(sauber)
            }
        default: wert = nil
        }
        guard let zahl = wert, zahl.isFinite else { return nil }
        return zahl
    }

    private static func kodiert(_ text: String) -> String {
        var erlaubt = CharacterSet.alphanumerics
        erlaubt.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? text
    }
}
