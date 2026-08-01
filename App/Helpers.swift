import CoreLocation
import SwiftUI
import UIKit

/// Welche Fassung hier läuft.
///
/// **Gepflegt wird sie an genau einer Stelle:** `MARKETING_VERSION` und
/// `CURRENT_PROJECT_VERSION` in `project.yml`. Von dort setzt Xcode sie beim Bauen in die
/// Platzhalter `$(MARKETING_VERSION)` und `$(CURRENT_PROJECT_VERSION)` in `App/Info.plist` ein,
/// und hier wird sie zur Laufzeit aus dem Bundle gelesen.
///
/// Eine Konstante im Quelltext wäre die naheliegende und die falsche Lösung: Sie stünde neben der
/// Zahl, mit der die App tatsächlich gebaut und eingereicht wird, und beide gingen früher oder
/// später auseinander. Dann zeigte der Bildschirm „Lizenzen und Dank" eine Fassung an, die es nie
/// gab — und der Fehlerbericht nennte sie ebenfalls.
enum Fassung {
    /// „0.1.0 (1)" — Fassung und Baunummer. Zwei Zahlen, weil sie zwei Dinge sagen: Die erste ist
    /// die, die im App Store steht, die zweite unterscheidet mehrere Einreichungen derselben.
    static let anzeige: String = {
        let angaben = Bundle.main.infoDictionary
        let fassung = angaben?["CFBundleShortVersionString"] as? String ?? "unbekannt"
        let bau = angaben?["CFBundleVersion"] as? String ?? "?"
        return "\(fassung) (\(bau))"
    }()
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

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func starte() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: abgelehnt = true
        default: manager.startUpdatingLocation()
        }
    }

    func stoppe() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let letzte = locations.last else { return }
        Task { @MainActor in self.position = letzte }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.abgelehnt = false
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.abgelehnt = true
            default:
                break
            }
        }
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
