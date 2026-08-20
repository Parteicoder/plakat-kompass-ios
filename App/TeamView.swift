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
    @State private var eigenerName = ""

    private var nameFehlt: Bool {
        eigenerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // SCHRITT 1, und er steht aus einem Grund ganz oben: Ohne Namen heisst dieses
                // Gerät im Team „iPhone". Seit iOS 16 gibt `UIDevice.current.name` ohne
                // Sonderberechtigung nur noch das Modell zurück. Das Feld gab es vorher nur beim
                // Weg „allein loslegen" — wer per QR beitrat oder ein Team gründete, blieb
                // namenlos, und bei drei iPhones im Team konnte die Teamleitung nicht mehr
                // erkennen, welches Gerät sie gerade freigibt.
                Section {
                    TextField("Zum Beispiel Anna oder Anna M.", text: $eigenerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("1. Dein Name")
                } footer: {
                    Text("""
                    Er steht später an jedem Plakat, das du erfasst, und in der Geräteliste des \
                    Teams. Ein iPhone verrät seinen Namen nicht von selbst — ohne diese Zeile \
                    heisst hier jedes Gerät „iPhone“.
                    """)
                }

                Section {
                    Button {
                        scannerOffen = true
                    } label: {
                        Label("QR-Code des Teamleiters scannen", systemImage: "qrcode.viewfinder")
                    }
                    .disabled(nameFehlt)
                } header: {
                    Text("2. Einem Team beitreten")
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
                        model.tritTeamBei(
                            qrInhalt: codeVonHand.trimmingCharacters(in: .whitespacesAndNewlines),
                            eigenerName: eigenerName
                        )
                        if model.istEingerichtet { schliessen() }
                    }
                    .disabled(nameFehlt || codeVonHand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Oder Code einfügen")
                } footer: {
                    Text("Falls die Kamera nicht geht: Der Teamleiter kann den Code auch als Text schicken.")
                }

                Section {
                    TextField("Teamname", text: $teamName)
                    Button("Neues Team anlegen") {
                        model.legeTeamAn(
                            name: teamName.isEmpty ? "Mein Team" : teamName,
                            eigenerName: eigenerName
                        )
                        schliessen()
                    }
                    .disabled(nameFehlt)
                } header: {
                    Text("Oder ein eigenes Team gründen")
                } footer: {
                    Text("Dieses Gerät wird dann Teamleiter und kann andere per QR-Code aufnehmen.")
                }

                Section {
                    Button("Allein loslegen") {
                        model.losOhneTeam(name: eigenerName)
                        if model.istEingerichtet { schliessen() }
                    }
                    .disabled(nameFehlt)
                } header: {
                    Text("Oder ohne Team")
                } footer: {
                    Text("""
                    Für alle, die allein plakatieren. Erfassen, Liste, Karte und die Liste für die \
                    Verwaltung funktionieren vollständig. Nur der Abgleich mit anderen Geräten \
                    braucht ein Team — dem lässt sich jederzeit später beitreten.
                    """)
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
                        model.tritTeamBei(qrInhalt: inhalt, eigenerName: eigenerName)
                        if model.istEingerichtet { schliessen() }
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
    @State private var code: String?
    @State private var folge: Int64 = 0
    @State private var restSekunden = Int(RollingTeamInvite.ttlSekunden)
    /// Zum `code` gehöriges Bild. Getrennt vom Code gehalten und off-Main erzeugt (siehe
    /// `erneuere()`), statt `qrBild(code)` bei jedem Sekundentakt erneut synchron im Body
    /// aufzurufen: Der Code wechselt nur alle ~55 Sekunden, das Bild wurde bis hierher aber
    /// jede Sekunde neu berechnet — derselbe wiederholte Kostenpunkt, den Android am 25.7.
    /// behoben hat (Commit `162fe36`, `ModernTeamQrCard.kt`, dort über `produceState` auf
    /// `Dispatchers.Default`).
    @State private var bild: UIImage?

    /// Der Takt der Anzeige. Der Code selbst wird kurz VOR Ablauf erneuert, nicht danach —
    /// sonst hielte die Teamleitung für einen Moment einen bereits ungültigen Code hin, und der
    /// andere bekäme „abgelaufen“ zu sehen, obwohl er richtig gescannt hat.
    private let takt = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.einladungFuerQr() != nil {
                VStack(spacing: 14) {
                    if codeSichtbar, let bild {
                        Image(uiImage: bild)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 260)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))

                        Text("Noch \(restSekunden) Sekunden gültig")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button(codeSichtbar ? "QR-Code verbergen" : "QR-Code anzeigen") {
                        codeSichtbar.toggle()
                        if codeSichtbar { erneuere() }
                    }
                    if codeSichtbar {
                        // Der Code enthaelt das Team-Geheimnis. Wer ihn abfotografiert, kaeme
                        // damit ins Team - deshalb verfaellt er nach einer Minute und wird durch
                        // einen neuen ersetzt, solange dieser Bildschirm offen ist.
                        Text("""
                        Der Code enthält den Team-Schlüssel und gilt eine Minute. Danach entsteht \
                        automatisch ein neuer — ein Foto davon nützt später niemandem mehr.
                        """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if let code {
                            ShareLink(item: code) {
                                Label("Code als Text teilen", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .onReceive(takt) { _ in ticke() }
                // Sichtbar verlassen heisst: nicht im Hintergrund weiterrollen. Der Code steht
                // ohnehin nur so lange, wie ihn jemand hinhaelt.
                .onDisappear { codeSichtbar = false }
            } else {
                Text("Nur die Teamleitung kann andere Geräte aufnehmen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func erneuere() {
        folge += 1
        let neuerCode = model.einladungFuerQr(folge: folge)
        code = neuerCode
        restSekunden = Int(RollingTeamInvite.ttlSekunden)
        bild = nil
        guard let neuerCode else { return }
        Task.detached(priority: .userInitiated) {
            let erzeugt = Self.qrBild(neuerCode)
            await MainActor.run {
                // Inzwischen kann schon der naechste Code faellig geworden sein — dann nicht
                // mehr das (bereits veraltete) Bild von diesem Durchlauf einsetzen.
                guard neuerCode == code else { return }
                bild = erzeugt
            }
        }
    }

    private func ticke() {
        guard codeSichtbar else { return }
        // Bei fünf Sekunden Rest, nicht bei null: Wer den Code gerade scannt, soll ihn nicht
        // mitten im Vorgang unter dem Objektiv verlieren.
        if restSekunden <= 5 {
            erneuere()
        } else {
            restSekunden -= 1
        }
    }

    /// `nonisolated`, nicht nur `static`: Ohne das leitet der Compiler MainActor-Isolation aus
    /// der `View`-Konformität her (CI-Fund) — dann liefe die Erzeugung trotz `Task.detached`
    /// weiterhin auf dem Hauptthread und der ganze Umbau in `erneuere()` wäre wirkungslos.
    private nonisolated static func qrBild(_ text: String) -> UIImage? {
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
