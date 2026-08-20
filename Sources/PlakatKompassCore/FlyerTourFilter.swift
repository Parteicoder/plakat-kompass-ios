/// Ob ein Wegpunkt in die Flyer-Tour gehört. Zahlen 1:1 aus `FlyerTourService.kt`.
///
/// Der Takt ist auf iOS ein anderer (`CLLocationManager` statt 8-Sekunden-Dienst). Die Filter
/// müssen trotzdem dieselben sein, sonst werden Android- und iOS-Touren nach dem Abgleich
/// unterschiedlich dicht.
public enum FlyerTourFilter {
    /// Ausreißer darüber verzerren die Strecke mehr, als sie sie beschreiben. Android: 25 m.
    public static let maxGenauigkeitMeter = 25.0
    /// Näher als das ist kein neuer Punkt — sonst füllt das Rauschen dieselbe Laterne.
    public static let mindestabstandMeter = 20.0
    /// Ungenauere Fixes brauchen mehr Abstand, sonst liegt der nächste Punkt im Rauschen.
    public static let genauigkeitsFaktor = 1.5

    /// `abstandZumVorgaengerMeter` ist `nil` beim ersten Punkt einer Tour.
    public static func sollAufnehmen(
        genauigkeitMeter: Double,
        abstandZumVorgaengerMeter: Double?
    ) -> Bool {
        guard genauigkeitMeter > 0, genauigkeitMeter <= maxGenauigkeitMeter else { return false }
        let noetig = max(mindestabstandMeter, genauigkeitMeter * genauigkeitsFaktor)
        if let abstand = abstandZumVorgaengerMeter, abstand < noetig { return false }
        return true
    }
}
