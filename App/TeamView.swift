import CoreImage.CIFilterBuiltins
import PlakatKompassCore
import SwiftUI

/// Team anlegen, beitreten, Geräte verwalten.
struct TeamBeitrittView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var schliessen

    @State private var scannerOffen = false
    @State private var teamName = ""
    @State private var codeVonHand = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        scannerOffen = true
                    } label: {
                        Label("QR-Code des Teamleiters scannen", systemImage: "qrcode.viewfinder")
                    }
                } header: {
                    Text("Einem Team beitreten")
                } footer: {
                    Text("""
                    Der Teamleiter zeigt den Code in seiner App unter „Team“. \
                    Er funktioniert zwischen Android und iPhone in beide Richtungen.
                    """)
                }

                Section {
                    TextField("Eingefügter Code", text: $codeVonHand, axis: .vertical)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Code übernehmen") {
                        model.tritTeamBei(qrInhalt: codeVonHand.trimmingCharacters(in: .whitespacesAndNewlines))
                        if model.istImTeam { schliessen() }
                    }
                    .disabled(codeVonHand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Oder Code einfügen")
                } footer: {
                    Text("Falls die Kamera nicht geht: Der Teamleiter kann den Code auch als Text schicken.")
                }

                Section {
                    TextField("Teamname", text: $teamName)
                    Button("Neues Team anlegen") {
                        model.legeTeamAn(name: teamName.isEmpty ? "Mein Team" : teamName)
                        schliessen()
                    }
                } header: {
                    Text("Oder ein eigenes Team gründen")
                } footer: {
                    Text("Dieses Gerät wird dann Teamleiter und kann andere per QR-Code aufnehmen.")
                }
            }
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
            }
            .fullScreenCover(isPresented: $scannerOffen) {
                NavigationStack {
                    QrScannerView { inhalt in
                        scannerOffen = false
                        model.tritTeamBei(qrInhalt: inhalt)
                        if model.istImTeam { schliessen() }
                    }
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { scannerOffen = false }
                        }
                    }
                }
            }
        }
    }
}

/// Der QR-Code, den die Teamleitung anderen zum Scannen hinhält.
struct TeamQrView: View {
    @EnvironmentObject private var model: AppModel
    @State private var codeSichtbar = false

    var body: some View {
        Group {
            if let code = model.einladungFuerQr() {
                VStack(spacing: 14) {
                    if codeSichtbar, let bild = qrBild(code) {
                        Image(uiImage: bild)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 260)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button(codeSichtbar ? "QR-Code verbergen" : "QR-Code anzeigen") {
                        codeSichtbar.toggle()
                    }
                    if codeSichtbar {
                        // Der Code enthaelt das Team-Geheimnis. Wer ihn abfotografiert, ist drin -
                        // deshalb steht er nicht dauerhaft offen auf dem Bildschirm.
                        Text("Der Code enthält den Team-Schlüssel. Nur Leuten zeigen, die ins Team sollen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        ShareLink(item: code) {
                            Label("Code als Text teilen", systemImage: "square.and.arrow.up")
                                .font(.footnote)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                Text("Nur die Teamleitung kann andere Geräte aufnehmen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func qrBild(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // H: hoechste Fehlerkorrektur. Der Code wird oft von einem Bildschirm abfotografiert,
        // schraeg und mit Spiegelungen.
        filter.correctionLevel = "H"
        guard let ausgabe = filter.outputImage else { return nil }
        let skaliert = ausgabe.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let kontext = CIContext()
        guard let cg = kontext.createCGImage(skaliert, from: skaliert.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
