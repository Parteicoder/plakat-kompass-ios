import CoreLocation
import Foundation

/// Eine getippte Adresse in Koordinaten verwandeln — Gegenstück zu `LocationSettingsUtils.kt`,
/// wo Android dasselbe mit `Geocoder.getFromLocationName` macht.
///
/// **Wofür das da ist, und es ist kein Nebenschauplatz:** Ohne Standort liess sich auf iOS
/// bisher **gar kein** Plakat erfassen — der Speichern-Knopf blieb grau. Das trifft genau die
/// Fälle, in denen man draussen steht und arbeiten will: eine Häuserschlucht ohne Empfang, ein
/// Innenhof, ein Telefon, auf dem jemand die Ortung einmal abgelehnt hat. Auf Android tippt man
/// dann die Adresse. Auf iPhone ging man nach Hause.
///
/// [CLGeocoder] arbeitet über Apples Server, braucht also Netz. Das ist kein Widerspruch zum
/// Zweck: Wer keinen GPS-Empfang hat, hat sehr oft trotzdem Mobilfunk — Satellitensicht und
/// Funkzelle sind zwei verschiedene Dinge.
@MainActor
final class AdresseAufloesen: ObservableObject {

    @Published private(set) var laeuft = false
    @Published private(set) var fehler: String?
    /// Der gefundene Ort, samt der Adresse, die Apple daraus gemacht hat. Letztere geht als
    /// Standort-Hinweis ins Plakat — sie ist sauberer geschrieben als die Eingabe.
    @Published private(set) var treffer: (ort: CLLocationCoordinate2D, beschriftung: String)?

    private let geokodierer = CLGeocoder()

    func suche(_ eingabe: String) {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        laeuft = true
        fehler = nil
        treffer = nil

        // "Deutschland" an die Suche haengen: "preferredLocale" unten steuert nur die Sprache
        // der Antwort, nicht welches Land durchsucht wird. Ohne diesen Zusatz findet Apple zu
        // "Bahnhofstraße 1" auch die in Oesterreich und der Schweiz - und nimmt womoeglich die
        // falsche.
        let suchtext = text.localizedCaseInsensitiveContains("deutschland") ? text : "\(text), Deutschland"
        geokodierer.geocodeAddressString(suchtext, in: nil, preferredLocale: Locale(identifier: "de_DE")) {
            [weak self] plaetze, fehlerObjekt in
            Task { @MainActor in
                guard let self else { return }
                self.laeuft = false
                guard let platz = plaetze?.first, let ort = platz.location?.coordinate else {
                    self.fehler = fehlerObjekt == nil
                        ? "Zu dieser Adresse wurde nichts gefunden."
                        : "Adresssuche nicht möglich: \(fehlerObjekt!.localizedDescription)"
                    return
                }
                self.treffer = (ort, Self.beschriftung(platz) ?? text)
            }
        }
    }

    func verwirf() {
        treffer = nil
        fehler = nil
    }

    /// Strasse mit Hausnummer und Ort, sofern Apple beides liefert. Sonst, was da ist.
    private static func beschriftung(_ platz: CLPlacemark) -> String? {
        let strasse = [platz.thoroughfare, platz.subThoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let ort = platz.locality ?? platz.subAdministrativeArea
        let teile = [strasse.isEmpty ? nil : strasse, ort].compactMap { $0 }
        return teile.isEmpty ? nil : teile.joined(separator: ", ")
    }
}
