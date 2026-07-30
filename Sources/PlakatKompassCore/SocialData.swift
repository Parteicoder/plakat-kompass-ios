import Foundation

/// Sozialdaten aus dem Regionalatlas. Gegenstück zu `feature/socialdata/` auf Android.
///
/// Alle Werte sind **gebietsbezogen und aggregiert** (amtliche Regionalstatistik). Es entstehen
/// und es werden nie personenbezogene Daten gespeichert — das ist nicht nur eine juristische
/// Formalie, sondern der Grund, warum diese Auswertung überhaupt vertretbar ist.
///
/// In dieser Datei steht alles, was **ohne Netz** prüfbar ist: der Katalog, der Aufbau der
/// Abfrage-URL und die Auswertung der Antwort. Der Abruf selbst liegt in der App — er braucht
/// `URLSession` und lässt sich in einem Unit-Test ohnehin nur nachstellen, nicht prüfen.

/// Gebietsebene, auf der ein Wert tatsächlich vorliegt.
///
/// Wichtig für die Anzeige: Eine Arbeitslosenquote gibt es nur je Kreis. Sie als Wert „für diese
/// Gemeinde" auszugeben wäre eine Genauigkeit, die die Zahl nicht hat.
public enum RegionLevel: String, Sendable {
    case GEMEINDE, KREIS, RASTER, UNKNOWN

    public var beschriftung: String {
        switch self {
        case .GEMEINDE: return "Gemeinde"
        case .KREIS: return "Kreis"
        case .RASTER: return "Umkreis ~300 m"
        case .UNKNOWN: return "Gebiet"
        }
    }

    /// typ-Code der Verwaltungsgrenzen im Regionalatlas.
    var typCode: Int {
        switch self {
        case .GEMEINDE, .RASTER: return 5
        case .KREIS, .UNKNOWN: return 3
        }
    }
}

/// Einheit samt deutscher Zahlenschreibweise.
public enum SocialUnit: Sendable {
    case percent, years, euro, density, per10k, plain
    // Nur beim Zensus-Raster: Haushaltsgröße, Wohnfläche, Miete je Quadratmeter, Kopfzahlen.
    case personen, quadratmeter, euroProQm, anzahl

    var suffix: String {
        switch self {
        case .percent: return " %"
        case .years: return " Jahre"
        case .euro: return " €"
        case .density: return " EW/km²"
        case .per10k: return " je 10.000 EW"
        case .plain: return ""
        case .personen: return " Pers."
        case .quadratmeter: return " m²"
        case .euroProQm: return " €/m²"
        case .anzahl: return ""
        }
    }

    var nachkommastellen: Int {
        switch self {
        case .percent, .years, .plain, .personen, .quadratmeter: return 1
        case .euroProQm: return 2
        case .euro, .density, .per10k, .anzahl: return 0
        }
    }

    public func format(_ wert: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = nachkommastellen
        f.maximumFractionDigits = nachkommastellen
        let zahl = f.string(from: NSNumber(value: wert)) ?? "\(wert)"
        return zahl + suffix
    }
}

/// Ein Indikator aus dem Regionalatlas.
///
/// `plausibleMin`/`plausibleMax` sind kein Zierrat: Der Parser muss aus einer Antwort mit vielen
/// Spalten die richtige heraussuchen. Greift er daneben, kommt ein Wert heraus, der aussieht wie
/// eine Zahl — ein Durchschnittsalter von 5 Jahren etwa. Der Bereich fängt das ab, und dann steht
/// „keine Daten" da statt Unsinn.
public struct SocialIndicator: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let category: String
    public let tableCode: String
    public let attributeCode: String
    public let unit: SocialUnit
    public let availableAtGemeinde: Bool
    public let plausibleMin: Double
    public let plausibleMax: Double

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (a: SocialIndicator, b: SocialIndicator) -> Bool { a.id == b.id }
}

public extension SocialIndicator {

    static let arbeitslosenquote = SocialIndicator(
        id: "ARBEITSLOSENQUOTE", label: "Arbeitslosenquote", category: "Arbeit",
        tableCode: "ai008_1_5", attributeCode: "AI0801", unit: .percent,
        availableAtGemeinde: false, plausibleMin: 0, plausibleMax: 100
    )
    static let durchschnittsalter = SocialIndicator(
        id: "DURCHSCHNITTSALTER", label: "Durchschnittsalter", category: "Alter",
        tableCode: "ai002_4_5", attributeCode: "AI0218", unit: .years,
        availableAtGemeinde: true, plausibleMin: 15, plausibleMax: 100
    )
    static let auslaenderanteil = SocialIndicator(
        id: "AUSLAENDERANTEIL", label: "Ausländeranteil", category: "Migration",
        tableCode: "ai002_1_5", attributeCode: "AI0208", unit: .percent,
        availableAtGemeinde: true, plausibleMin: 0, plausibleMax: 100
    )
    static let bevoelkerungsdichte = SocialIndicator(
        id: "BEVOELKERUNGSDICHTE", label: "Bevölkerungsdichte", category: "Bevölkerung",
        tableCode: "ai002_1_5", attributeCode: "AI0201", unit: .density,
        availableAtGemeinde: true, plausibleMin: 0, plausibleMax: 100_000
    )
    static let rentneralter = SocialIndicator(
        id: "RENTNERALTER", label: "Ab 65 Jahre", category: "Alter",
        tableCode: "ai002_2_5", attributeCode: "AI0207", unit: .percent,
        availableAtGemeinde: true, plausibleMin: 0, plausibleMax: 100
    )
    static let grundsicherungAlter = SocialIndicator(
        id: "GRUNDSICHERUNG_ALTER", label: "Grundsicherung im Alter", category: "Soziales",
        tableCode: "ai_s_05", attributeCode: "AI2201", unit: .percent,
        availableAtGemeinde: false, plausibleMin: 0, plausibleMax: 100
    )
    static let sgb2Quote = SocialIndicator(
        id: "SGB2_QUOTE", label: "SGB-II-Quote", category: "Soziales",
        tableCode: "ai_s_04", attributeCode: "AI2101", unit: .percent,
        availableAtGemeinde: false, plausibleMin: 0, plausibleMax: 100
    )
    /// Selbst im ärmsten Landkreis nie unter etwa 15.000 €, im reichsten nie über 60.000 €. Eng
    /// genug, dass ein Fehlgriff auf eine Index- oder Rangspalte nicht als Euro-Betrag durchgeht.
    static let verfuegbaresEinkommen = SocialIndicator(
        id: "VERFUEGBARES_EINKOMMEN", label: "Verfügb. Einkommen", category: "Einkommen",
        tableCode: "ai016_1", attributeCode: "AI1601", unit: .euro,
        availableAtGemeinde: false, plausibleMin: 5_000, plausibleMax: 60_000
    )
    /// Kann negativ sein — eine schrumpfende Gemeinde ist genau das, was man sehen will.
    static let bevoelkerungsentwicklung = SocialIndicator(
        id: "BEVOELKERUNGSENTWICKLUNG", label: "Bev.-Entwicklung", category: "Bevölkerung",
        tableCode: "ai002_1_5", attributeCode: "AI0202", unit: .per10k,
        availableAtGemeinde: true, plausibleMin: -100_000, plausibleMax: 100_000
    )
    static let jugendanteil = SocialIndicator(
        id: "JUGENDANTEIL", label: "Unter 18 Jahre", category: "Alter",
        tableCode: "ai002_2_5", attributeCode: "AI0204", unit: .percent,
        availableAtGemeinde: true, plausibleMin: 0, plausibleMax: 100
    )

    static let alle: [SocialIndicator] = [
        .arbeitslosenquote, .durchschnittsalter, .auslaenderanteil, .bevoelkerungsdichte,
        .rentneralter, .grundsicherungAlter, .sgb2Quote, .verfuegbaresEinkommen,
        .bevoelkerungsentwicklung, .jugendanteil
    ]

    static let standard = SocialIndicator.arbeitslosenquote

    static func mitId(_ id: String?) -> SocialIndicator {
        alle.first { $0.id == id } ?? standard
    }
}

public struct SocialValue: Equatable, Sendable {
    public let indicator: SocialIndicator
    public let value: Double
    public let year: Int?
    public let level: RegionLevel
    public let regionName: String

    public var formatted: String { indicator.unit.format(value) }
}

/// Der Aufbau der Abfrage und die Auswertung der Antwort.
public enum RegionalAtlas {

    public static let endpunkt =
        "https://www.gis-idmz.nrw.de/arcgis/rest/services/stba/regionalatlas/MapServer/dynamicLayer/query"

    public static let quellenangabe =
        "Regionalatlas – Statistische Ämter des Bundes und der Länder"

    /// Baut die vollständige Abfrage-URL für einen Indikator, eine Ebene und einen Punkt.
    public static func buildUrl(
        indicator: SocialIndicator, level: RegionLevel, longitude: Double, latitude: Double
    ) -> String {
        let sql = "SELECT * FROM verwaltungsgrenzen_gesamt "
            + "LEFT OUTER JOIN \(indicator.tableCode) ON ags = ags2 and jahr = jahr2 "
            + "WHERE typ = \(level.typCode) AND (jahr2 IS NULL OR jahr2 = jahr)"

        let layer = "{\"source\":{\"dataSource\":{\"geometryType\":\"esriGeometryPolygon\","
            + "\"workspaceId\":\"gdb\",\"query\":\(jsonString(sql)),\"oidFields\":\"id\","
            + "\"spatialReference\":{\"wkid\":25832},\"type\":\"queryTable\"},\"type\":\"dataLayer\"}}"
        let geometry = "{\"x\":\(longitude),\"y\":\(latitude),\"spatialReference\":{\"wkid\":4326}}"

        let parameter: [(String, String)] = [
            ("layer", layer),
            ("geometry", geometry),
            ("geometryType", "esriGeometryPoint"),
            ("inSR", "4326"),
            ("spatialRel", "esriSpatialRelIntersects"),
            ("outFields", "*"),
            ("returnGeometry", "false"),
            ("f", "json")
        ]
        let query = parameter
            .map { "\($0.0)=\(prozentkodiert($0.1))" }
            .joined(separator: "&")
        return "\(endpunkt)?\(query)"
    }

    /// Wie `JSONObject.quote`: die Zeichenkette als JSON-Literal, mit Anführungszeichen.
    private static func jsonString(_ text: String) -> String {
        let daten = try? JSONSerialization.data(withJSONObject: [text], options: [])
        guard let daten, let ganz = String(data: daten, encoding: .utf8) else { return "\"\"" }
        return String(ganz.dropFirst().dropLast())   // die eckigen Klammern weg
    }

    /// `addingPercentEncoding` mit einem Zeichenvorrat, der auch `+`, `&` und `=` kodiert —
    /// `.urlQueryAllowed` lässt die stehen, und dann zerfällt die Abfrage.
    private static func prozentkodiert(_ text: String) -> String {
        let erlaubt = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? text
    }

    // MARK: - Auswertung

    private static let namensSchluessel = ["gen", "GEN", "name", "NAME", "bez", "BEZ", "gebiet", "gebietsname", "raumeinheit"]
    private static let jahresSchluessel = ["jahr", "JAHR", "jahr2", "JAHR2", "stand", "year"]
    private static let uebergehen: Set<String> = ["id", "objectid", "oid", "ags", "ags2", "sn_l", "sn_r", "sn_k", "sn_v", "sn_g"]

    /// Wertet die ArcGIS-Antwort aus. `nil`, wenn kein belastbarer Wert darinsteht.
    ///
    /// Bewusst **defensiv** gegenüber den genauen Feldnamen: Die Antwort ist ein Join über zwei
    /// Tabellen, und wie die Spalten am Ende heißen, hängt vom Indikator ab. Lieber „keine Daten"
    /// als der falsche Wert — deshalb gibt der Parser an jeder mehrdeutigen Stelle auf.
    public static func parseResponse(
        _ rohJson: String, indicator: SocialIndicator, level: RegionLevel
    ) -> SocialValue? {
        guard let daten = rohJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              root["error"] == nil,
              let features = root["features"] as? [[String: Any]],
              !features.isEmpty
        else { return nil }

        // Der Join liefert für ein Gebiet oft mehrere Jahrgänge. Immer den mit der HÖCHSTEN
        // Jahreszahl nehmen, nicht den ersten - der ist gern zehn Jahre alt.
        var bester: SocialValue?
        var bestesJahr = Int.min

        for feature in features {
            guard let attribute = feature["attributes"] as? [String: Any],
                  let wert = indikatorWert(attribute, indicator)
            else { continue }
            guard wert >= indicator.plausibleMin, wert <= indicator.plausibleMax else { continue }

            let jahr = jahresWert(attribute)
            let rang = jahr ?? Int.min
            if bester == nil || rang > bestesJahr {
                bestesJahr = rang
                bester = SocialValue(
                    indicator: indicator,
                    value: wert,
                    year: jahr,
                    level: level,
                    regionName: gebietsname(attribute) ?? level.beschriftung
                )
            }
        }
        return bester
    }

    private static func gebietsname(_ attribute: [String: Any]) -> String? {
        for schluessel in namensSchluessel {
            if let text = attribute[schluessel] as? String,
               !text.trimmingCharacters(in: .whitespaces).isEmpty,
               !text.allSatisfy(\.isNumber) {
                return text
            }
        }
        for (schluessel, wert) in attribute.sorted(by: { $0.key < $1.key }) {
            guard !uebergehen.contains(schluessel.lowercased()) else { continue }
            if let text = wert as? String, text.contains(where: \.isLetter) { return text }
        }
        return nil
    }

    private static func jahresWert(_ attribute: [String: Any]) -> Int? {
        for schluessel in jahresSchluessel {
            guard let roh = attribute[schluessel], let zahl = alsZahl(roh) else { continue }
            let jahr = Int(zahl)
            if (1990...2100).contains(jahr) { return jahr }
        }
        return nil
    }

    private static func indikatorWert(_ attribute: [String: Any], _ indicator: SocialIndicator) -> Double? {
        for schluessel in [
            indicator.attributeCode.lowercased(), indicator.attributeCode,
            indicator.tableCode, "wert", "WERT", "value", "VALUE"
        ] {
            if let roh = attribute[schluessel], let zahl = alsZahl(roh) { return zahl }
        }

        // Die Indikatorspalte des Joins heisst immer "aiXXXX". Gibt es genau eine solche
        // numerische Spalte, ist das der gesuchte Wert. Bei mehreren wird NICHT geraten.
        let aiWerte = attribute.compactMap { schluessel, roh -> Double? in
            let klein = schluessel.lowercased()
            guard !uebergehen.contains(klein),
                  klein.range(of: "^ai\\d+$", options: .regularExpression) != nil
            else { return nil }
            return alsZahl(roh)
        }
        if aiWerte.count == 1 { return aiWerte.first }

        // Letzter Versuch: der einzige sinnvolle numerische Wert, der weder Jahr noch Kennung ist.
        var gefunden: Double?
        for (schluessel, roh) in attribute {
            let klein = schluessel.lowercased()
            guard !uebergehen.contains(klein),
                  !jahresSchluessel.map({ $0.lowercased() }).contains(klein),
                  let zahl = alsZahl(roh)
            else { continue }
            if gefunden != nil { return nil }   // mehrdeutig - lieber nichts als das Falsche
            gefunden = zahl
        }
        return gefunden
    }

    /// `NaN` und `Infinity` gelten als „kein Wert".
    ///
    /// Das ist keine Kleinigkeit: `Double("NaN")` gelingt, und **jeder** Vergleich mit `NaN` ist
    /// falsch — die Plausibilitätsprüfung oben würde also stillschweigend durchgewunken.
    static func alsZahl(_ roh: Any?) -> Double? {
        switch roh {
        case let zahl as Double: return zahl.isFinite ? zahl : nil
        case let zahl as Int: return Double(zahl)
        case let zahl as NSNumber: return zahl.doubleValue.isFinite ? zahl.doubleValue : nil
        case let text as String:
            let s = text.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, s.lowercased() != "null", s != "-" else { return nil }
            // Deutsche Schreibweise: "1.234,5" -> 1234.5, "7,2" -> 7.2
            let normiert: String
            if s.contains("."), s.contains(",") {
                normiert = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else if s.contains(",") {
                normiert = s.replacingOccurrences(of: ",", with: ".")
            } else {
                normiert = s
            }
            guard let zahl = Double(normiert), zahl.isFinite else { return nil }
            return zahl
        default: return nil
        }
    }
}
