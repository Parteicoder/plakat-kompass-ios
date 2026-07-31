import SwiftUI

/// Hell, dunkel oder nach System — Gegenstück zu `util/ThemeSettingsStore.kt` und
/// `ui/screens/MoreAppearanceCard.kt`.
///
/// **Ein Wort zur Berechtigung dieser Einstellung.** Auf iOS regelt das System Hell und Dunkel
/// bereits für alle Apps, und eine eigene Einstellung ist damit streng genommen ein zweiter
/// Schalter für dieselbe Sache. Sie steht hier trotzdem, aus zwei Gründen: Die Android-Fassung
/// hat sie, und der Auftrag lautet, beide Apps gleich zu bedienen. Und sie kann etwas, das der
/// Systemschalter nicht kann — **nur diese eine App** umstellen. Wer nachts plakatiert, will
/// womöglich die Plakat-App dunkel und den Rest des Telefons nicht.
///
/// Die Vorgabe bleibt „Automatisch". Wer nichts einstellt, bekommt das Systemverhalten.
enum Darstellung: String, CaseIterable, Identifiable {
    case system
    case hell
    case dunkel

    /// Der Schlüssel in den Voreinstellungen. Auch der Oberflächentest setzt ihn.
    static let schluessel = "darstellung"

    var id: String { rawValue }

    var beschriftung: String {
        switch self {
        case .system: return "Automatisch"
        case .hell: return "Hell"
        case .dunkel: return "Dunkel"
        }
    }

    /// `nil` heisst für SwiftUI ausdrücklich „nicht festlegen", also dem System folgen.
    /// Deshalb ist der Rückgabewert optional und nicht etwa `.light` als Ersatz.
    var farbschema: ColorScheme? {
        switch self {
        case .system: return nil
        case .hell: return .light
        case .dunkel: return .dark
        }
    }

    /// Aus dem gespeicherten Text. Unbekanntes fällt auf „Automatisch" zurück, statt zu
    /// scheitern — ein kaputter Eintrag darf die App nicht ins Dunkel zwingen.
    static func aus(_ gespeichert: String) -> Darstellung {
        Darstellung(rawValue: gespeichert) ?? .system
    }
}
