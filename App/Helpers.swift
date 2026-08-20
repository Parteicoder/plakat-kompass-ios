import CoreLocation
import MapKit
import Network
import PlakatKompassCore
import SwiftUI
import UIKit

/// Welche Fassung hier läuft.
///
/// **Gepflegt wird sie an genau einer Stelle:** `MARKETING_VERSION` in `project.yml`. Von dort
/// setzt Xcode sie beim Bauen in den Platzhalter `$(MARKETING_VERSION)` in `App/Info.plist` ein,
/// und hier wird sie zur Laufzeit aus dem Bundle gelesen.
///
/// Eine Konstante im Quelltext wäre die naheliegende und die falsche Lösung: Sie stünde neben der
/// Zahl, mit der die App tatsächlich gebaut und eingereicht wird, und beide gingen früher oder
/// später auseinander. Dann zeigte der Bildschirm „Lizenzen und Dank" eine Fassung an, die es nie
/// gab — und der Fehlerbericht nennte sie ebenfalls.
///
/// **Die Baunummer steht hier bewusst nicht.** `CFBundleVersion` unterscheidet mehrere
/// Einreichungen derselben Fassung — das interessiert beim Hochladen in den App Store, nicht den
/// Menschen, der wissen will, welche Fassung er benutzt. Wer sie doch braucht, hängt sie an
/// dieser einen Stelle an.
enum Fassung {
    static let anzeige: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unbekannt"
}

extension Binding where Value == String {
    /// Deckel schon beim Setzen, damit Tippen und Einfügen dieselbe Grenze haben.
    func begrenzt(auf maximum: Int) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = EingabeGrenzen.kappe($0, auf: maximum) }
        )
    }
}

extension Poster {
    /// Der Fußweg zu diesem Plakat, in Apple Karten.
    ///
    /// Steht hier, weil es inzwischen drei Aufrufer sind: Startseite, Kartenblatt und Liste.
    /// Dreimal dasselbe `MKMapItem` aufzubauen heißt, beim nächsten Ändern zwei davon zu
    /// vergessen — etwa den Namen, den Apple Karten als Ziel anzeigt.
    ///
    /// Die Routenführung selbst überlassen wir Apple. Eine eigene wäre Monate Arbeit für etwas,
    /// das jedes iPhone schon kann.
    func hinlaufen() {
        let ziel = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: latitude, longitude: longitude
        )))
        ziel.name = addressHint.isEmpty ? "Plakat" : addressHint
        ziel.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

/// Kamera über den Systemdialog. `UIImagePickerController` statt eigener AVFoundation-Oberfläche:
/// Die Kamera ist eine Plattformfunktion, sie muss nicht nachgebaut werden.
struct KameraAufnahme: UIViewControllerRepresentable {
    var fertig: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let eltern: KameraAufnahme
        init(_ eltern: KameraAufnahme) { self.eltern = eltern }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let bild = info[.originalImage] as? UIImage
            // Wie auf Android: laengste Kante 1600 px, JPEG-Qualitaet 85. Sonst sprengen die
            // Fotos jedes Sync-Paket - ein Originalfoto ist schnell 5 MB.
            eltern.fertig(bild.flatMap { verkleinert($0) })
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            eltern.fertig(nil)
            picker.dismiss(animated: true)
        }

        private func verkleinert(_ bild: UIImage) -> Data? {
            let maxKante: CGFloat = 1600
            let groesste = max(bild.size.width, bild.size.height)
            let faktor = groesste > maxKante ? maxKante / groesste : 1
            let ziel = CGSize(width: bild.size.width * faktor, height: bild.size.height * faktor)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let skaliert = UIGraphicsImageRenderer(size: ziel, format: format).image { _ in
                bild.draw(in: CGRect(origin: .zero, size: ziel))
            }
            return skaliert.jpegData(compressionQuality: 0.85)
        }
    }
}

/// Standort für die Erfassung.
///
/// Die Genauigkeit wird mitgeführt und angezeigt: Ein Plakat, das bei 60 m Ungenauigkeit erfasst
/// wurde, steht auf der Karte womöglich in der falschen Straße, und das muss der Erfasser sehen.
@MainActor
final class Standort: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: CLLocation?
    @Published var abgelehnt = false
    /// Nur ungefährer Standort erlaubt — Gegenstück zu Androids Prüfung auf die
    /// Coarse-Location-Berechtigung, hier aus `accuracyAuthorization` gelesen.
    @Published var reduzierteGenauigkeit = false
    /// Blickrichtung des Geräts in Grad (0 = Norden). Gegenstück zu `rememberDeviceAzimuth` auf
    /// Android — dort aus dem Rotationsvektor-Sensor gerechnet, hier liefert CoreLocation das
    /// direkt. Fehlt der Sensor, bleibt der Wert 0: Die Kompassnadel zeigt dann fest nach Norden
    /// statt zu wackeln, genau wie drüben.
    @Published var peilung: Double = 0

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func starte() {
        reduzierteGenauigkeit = manager.accuracyAuthorization == .reducedAccuracy
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: abgelehnt = true
        default:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
    }

    func stoppe() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let letzte = locations.last else { return }
        Task { @MainActor in self.position = letzte }
    }

    /// Fehlerhafte Peilungen liefert iOS mit negativer Genauigkeit — die werden übersprungen.
    /// `trueHeading` (geografisch Nord, braucht Standort) vor `magneticHeading`, aber nur wenn
    /// gültig: Ohne frischen GPS-Fix steht dort -1.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let grad = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.peilung = grad }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.reduzierteGenauigkeit = manager.accuracyAuthorization == .reducedAccuracy
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.abgelehnt = false
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            case .denied, .restricted:
                self.abgelehnt = true
            default:
                break
            }
        }
    }
}

/// 2,5D-Kompass-Knopf. Gegenstück zu `CompassButton.kt`.
///
/// Die dicke Spitze zeigt zum nächsten Plakat, oder nach Norden, solange keins bekannt ist —
/// beides relativ zur Gerätehaltung. Zifferblatt und Nadel sind die echten Bilder aus der
/// Android-Fassung (`compass_dial.png`, `compass_needle.png`), nicht nachgezeichnet.
struct KompassKnopf: View {
    let geraetePeilung: Double
    let zielPeilung: Double?
    let tippen: () -> Void

    var body: some View {
        let nadelDrehung = (zielPeilung ?? 0) - geraetePeilung
        Button(action: tippen) {
            ZStack {
                Image("SymbolKompassZifferblatt")
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                Image("SymbolKompassNadel")
                    .resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(nadelDrehung))
            }
            .frame(width: 64, height: 64)
            .background(Circle().fill(.white))
            .shadow(radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigation zum nächsten Plakat")
    }
}

/// Ob gerade eine Internetverbindung besteht. Gegenstück zu `istInternetVerfuegbar` auf Android.
///
/// Ein Singleton mit genau einem laufenden `NWPathMonitor`, nicht eins pro Bildschirm: Der
/// Monitor läuft ohnehin unabhängig davon, wer hinschaut, mehrere Instanzen würden nur mehrfach
/// dasselbe beobachten.
@MainActor
final class Netzstatus: ObservableObject {
    static let geteilt = Netzstatus()

    @Published private(set) var verfuegbar = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] pfad in
            Task { @MainActor in self?.verfuegbar = pfad.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "netzstatus"))
    }
}

/// Der Teilen-Dialog des Systems. Damit geht ein Sync-Paket an jeden Messenger, an Mail,
/// per AirDrop oder in die Dateien-App — ohne dass die App eine einzige Zeile Netzwerkcode hat.
struct TeilenDialog: UIViewControllerRepresentable {
    let dateien: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: dateien, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
