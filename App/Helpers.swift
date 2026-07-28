import CoreLocation
import SwiftUI
import UIKit

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
