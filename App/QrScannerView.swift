import AVFoundation
import AudioToolbox
import PlakatKompassCore
import SwiftUI

/// QR-Scanner für die Team-Einladung.
///
/// `AVCaptureMetadataOutput` statt einer Bibliothek: Das System erkennt QR-Codes selbst, und
/// eine Abhängigkeit für etwa achtzig Zeilen wäre hier nicht zu rechtfertigen.
struct QrScannerView: UIViewControllerRepresentable {
    var erkannt: (String) -> Void

    func makeUIViewController(context: Context) -> QrScannerController {
        let controller = QrScannerController()
        controller.erkannt = erkannt
        return controller
    }

    func updateUIViewController(_ controller: QrScannerController, context: Context) {}
}

final class QrScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var erkannt: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var vorschau: AVCaptureVideoPreviewLayer?
    /// Ohne diese Sperre feuert der Rückruf im Dauertakt, solange der Code im Bild ist.
    private var schonGemeldet = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let kamera = AVCaptureDevice.default(for: .video),
              let eingang = try? AVCaptureDeviceInput(device: kamera),
              session.canAddInput(eingang)
        else {
            zeigeHinweis("Keine Kamera verfügbar.")
            return
        }
        session.addInput(eingang)

        let ausgang = AVCaptureMetadataOutput()
        guard session.canAddOutput(ausgang) else {
            zeigeHinweis("QR-Erkennung nicht verfügbar.")
            return
        }
        session.addOutput(ausgang)
        ausgang.setMetadataObjectsDelegate(self, queue: .main)
        ausgang.metadataObjectTypes = [.qr]

        let ebene = AVCaptureVideoPreviewLayer(session: session)
        ebene.videoGravity = .resizeAspectFill
        ebene.frame = view.bounds
        view.layer.addSublayer(ebene)
        vorschau = ebene
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        // startRunning blockiert; auf dem Hauptthread wuerde die Oberflaeche einfrieren.
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        vorschau?.frame = view.bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !schonGemeldet,
              let objekt = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let inhalt = objekt.stringValue
        else { return }
        schonGemeldet = true
        AudioServicesPlaySystemSound(1057)
        erkannt?(inhalt)
    }

    private func zeigeHinweis(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = view.bounds.insetBy(dx: 24, dy: 0)
        view.addSubview(label)
    }
}
