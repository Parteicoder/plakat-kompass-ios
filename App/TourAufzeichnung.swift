import CoreLocation
import PlakatKompassCore
import SwiftUI

/// Zeichnet den Weg einer Flyer-Tour auf. Gegenstück zu `tracking/FlyerTourService.kt`.
///
/// **Der Weg dorthin ist auf iOS ein anderer.** Android startet einen Vordergrunddienst mit
/// dauerhafter Meldung und fragt alle acht Sekunden aktiv nach dem Standort. Auf iOS gibt es
/// keinen Dienst, den eine App am Leben halten kann; stattdessen liefert `CLLocationManager`
/// weiter Positionen, solange `allowsBackgroundLocationUpdates` gesetzt und die Berechtigung
/// „Immer" erteilt ist. Das System bestimmt den Takt, nicht die App.
///
/// Zwei Dinge sind deshalb Pflicht und stehen in der Info.plist:
/// `UIBackgroundModes: location` und `NSLocationAlwaysAndWhenInUseUsageDescription`.
/// `showsBackgroundLocationIndicator` lässt iOS die Statusleiste einfärben, solange
/// aufgezeichnet wird — das ist keine Schikane, sondern genau die Ehrlichkeit, die eine App
/// schuldet, die im Hintergrund dem Standort folgt.
///
/// Wird „Immer" abgelehnt, läuft die Aufzeichnung trotzdem — nur eben nur, solange die App
/// offen ist. Das wird in der Oberfläche gesagt, statt still weniger zu tun als versprochen.
@MainActor
final class TourAufzeichnung: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Wie auf Android: näher als 20 Meter ist kein neuer Wegpunkt. Ohne diese Schwelle füllt
    /// das Rauschen der Ortung die Tour mit hunderten Punkten auf derselben Stelle — und jeder
    /// davon wandert in jedes Sync-Paket.
    private static let mindestabstandMeter: CLLocationDistance = 20

    /// Nach fünf Stunden ist Schluss, ebenfalls wie drüben. Eine vergessene Tour, die über Nacht
    /// weiterläuft, kostet Akku und zeichnet den Heimweg auf.
    private static let maximaleDauer: TimeInterval = 5 * 60 * 60

    @Published private(set) var laeuft = false
    @Published private(set) var nurImVordergrund = false

    private let manager = CLLocationManager()
    private var tourId: String?
    private var letzterPunkt: CLLocation?
    private var beginn: Date?
    private var punktAufnehmen: ((Double, Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = Self.mindestabstandMeter
        manager.activityType = .fitness
    }

    func starte(tourId: String, punktAufnehmen: @escaping (Double, Double) -> Void) {
        self.tourId = tourId
        self.punktAufnehmen = punktAufnehmen
        self.letzterPunkt = nil
        self.beginn = Date()

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        // „Immer" erst hier erfragen, nicht beim ersten Start der App: Apple verlangt, dass die
        // Frage in dem Moment kommt, in dem der Nutzen erkennbar ist.
        manager.requestAlwaysAuthorization()

        nurImVordergrund = manager.authorizationStatus != .authorizedAlways
        manager.allowsBackgroundLocationUpdates = !nurImVordergrund
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        laeuft = true
    }

    func stoppe() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        laeuft = false
        tourId = nil
        punktAufnehmen = nil
        beginn = nil
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let neu = locations.last else { return }
        Task { @MainActor in self.nimmAuf(neu) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.laeuft else { return }
            self.nurImVordergrund = manager.authorizationStatus != .authorizedAlways
            manager.allowsBackgroundLocationUpdates = !self.nurImVordergrund
        }
    }

    private func nimmAuf(_ ort: CLLocation) {
        guard laeuft, tourId != nil else { return }

        if let beginn, Date().timeIntervalSince(beginn) > Self.maximaleDauer {
            stoppe()
            return
        }
        // Ausreisser aussortieren: Eine Position mit 200 Metern Ungenauigkeit verzerrt die
        // Strecke mehr, als sie sie beschreibt.
        guard ort.horizontalAccuracy > 0, ort.horizontalAccuracy < 100 else { return }
        if let vorher = letzterPunkt, vorher.distance(from: ort) < Self.mindestabstandMeter { return }

        letzterPunkt = ort
        punktAufnehmen?(ort.coordinate.latitude, ort.coordinate.longitude)
    }
}
