import Foundation

/// Standortpruefung beim Fotografieren eines Plakats. Gegenstuecke zu
/// `feature/capture/PosterPhotoLocationValidation.kt` auf Android.
///
/// Android blockiert das Speichern bei fehlendem oder nicht bewertbarem GPS-Fix und bei einer
/// Position, die aelter als 30 Sekunden ist, und stuft die Genauigkeit danach dreistufig ab
/// (3/5/10 m) mit Bestaetigungsdialog jenseits von 10 m. Bislang zeigte iOS an dieser Stelle nur
/// einen statischen Warnhinweis ab 30 m - kein Blockieren, keine Alterspruefung, keine gestufte
/// Rueckmeldung. Diese Datei uebernimmt die Android-Schwellwerte 1:1, ohne CoreLocation zu
/// importieren, damit sie wie der Rest von `PlakatKompassCore` reine Logik bleibt und unter
/// macOS testbar ist.
public enum PosterPhotoLocationValidation {

    public static let excellentAccuracyMeters = 3.0
    public static let goodAccuracyMeters = 5.0
    public static let okAccuracyMeters = 10.0
    public static let maxLocationAgeMs: Int64 = 30_000

    public struct Result: Equatable {
        public let isValid: Bool
        public let errorMessage: String?
    }

    /// `accuracyMeters`: `nil` oder negativ entspricht Androids `!location.hasAccuracy()` -
    /// CoreLocation liefert bei unbekannter Genauigkeit einen negativen Wert statt eines
    /// optionalen Felds.
    public static func validate(
        accuracyMeters: Double?,
        timestampMs: Int64?,
        nowMs: Int64 = Date.nowMillis
    ) -> Result {
        guard let timestampMs else {
            return Result(
                isValid: false,
                errorMessage: "Foto aufgenommen, aber kein Standort gefunden. Bitte GPS kurz warten lassen und Foto neu aufnehmen."
            )
        }
        guard let accuracyMeters, accuracyMeters >= 0 else {
            return Result(
                isValid: false,
                errorMessage: "Foto aufgenommen, aber GPS meldet keine Genauigkeit. Bitte Foto neu aufnehmen."
            )
        }
        guard nowMs - timestampMs <= maxLocationAgeMs else {
            return Result(
                isValid: false,
                errorMessage: "GPS beim Foto war zu alt. Bitte Foto neu aufnehmen."
            )
        }
        return Result(isValid: true, errorMessage: nil)
    }

    /// Ob vor dem Speichern ein Bestaetigungsdialog noetig ist - der Fix ist grundsaetzlich
    /// gueltig (siehe `validate`), aber ungenauer als der Zielbereich.
    public static func shouldConfirmInaccurateLocation(
        accuracyMeters: Double?,
        timestampMs: Int64?,
        nowMs: Int64 = Date.nowMillis
    ) -> Bool {
        validate(accuracyMeters: accuracyMeters, timestampMs: timestampMs, nowMs: nowMs).isValid
            && (accuracyMeters ?? 0) > okAccuracyMeters
    }

    public static func confirmationMessage(accuracyMeters: Double) -> String {
        "GPS beim Foto ist sehr ungenau (ca. \(Int(accuracyMeters)) m). Möchtest du diesen Standort trotzdem übernehmen?"
    }

    /// Dreistufige Rueckmeldung zur Genauigkeit, wortgleich mit
    /// `posterPhotoLocationAccuracyWarning` auf Android. `nil` heisst: Genauigkeit ist exzellent
    /// (<= 3 m), kein Hinweis noetig.
    public static func accuracyWarning(accuracyMeters: Double?) -> String? {
        guard let accuracyMeters, accuracyMeters >= 0 else {
            return "GPS-Genauigkeit unbekannt. Marker bitte später prüfen."
        }
        if accuracyMeters > okAccuracyMeters {
            return "Standort manuell bestätigt trotz ungenauer GPS-Messung (ca. \(Int(accuracyMeters)) m). Marker bitte auf der Karte prüfen."
        }
        if accuracyMeters > goodAccuracyMeters {
            return "Standort akzeptiert (ca. \(Int(accuracyMeters)) m) – liegt im Zielbereich von 3 bis 10 m."
        }
        if accuracyMeters > excellentAccuracyMeters {
            return "Standort gut (ca. \(Int(accuracyMeters)) m). Zielbereich ist 3 bis 10 m."
        }
        return nil
    }
}
