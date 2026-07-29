import PlakatKompassCore
import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var standort = Standort()

    @State private var kameraOffen = false
    @State private var foto: Data?
    @State private var adresse = ""
    @State private var typ: PosterType = .LAMP_POST
    @State private var abnahmeInTagen = 14
    @State private var amtlicheBemerkung = ""
    @State private var interneBemerkung = ""

    var body: some View {
        NavigationStack {
            Form {
                if !model.istEingerichtet {
                    Section {
                        Text("""
                        Noch nicht eingerichtet. Unter „Abgleich“ einem Team beitreten, eins \
                        gründen — oder allein loslegen.
                        """)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    // Nur solange noch nie ein Foto gemacht wurde - genau wie auf Android.
                    if !model.hatFotoAufgenommen && foto == nil {
                        Text("Erfasse dein erstes Plakat, indem du auf das Symbol tippst.")
                            .font(.body).fontWeight(.medium)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.mint, lineWidth: 1.5))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    HStack {
                        Spacer()
                        Button {
                            kameraOffen = true
                        } label: {
                            Image(systemName: foto == nil ? "camera.fill" : "checkmark.circle.fill")
                                .font(.system(size: 34))
                                .frame(width: 92, height: 92)
                                .background(Circle().fill(foto == nil ? Color.accentColor : Color.green))
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(foto == nil ? "Foto aufnehmen" : "Foto erneut aufnehmen")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Standort") {
                    if standort.abgelehnt {
                        Label("Ortung ist abgelehnt. Ohne Standort lässt sich kein Plakat erfassen.",
                              systemImage: "location.slash")
                            .foregroundStyle(.red)
                    } else if let position = standort.position {
                        LabeledContent("Genauigkeit", value: "ca. \(Int(position.horizontalAccuracy)) m")
                        if position.horizontalAccuracy > 30 {
                            Text("Ungenau. Der Marker sollte später auf der Karte geprüft werden.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    } else {
                        Label("Standort wird gesucht …", systemImage: "location")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Angaben") {
                    TextField("Standort-Hinweis, etwa Bahnhofstraße 1", text: $adresse)
                    Picker("Art", selection: $typ) {
                        ForEach(PosterType.allCases, id: \.self) { Text($0.beschriftung).tag($0) }
                    }
                    Stepper("Abnahme in \(abnahmeInTagen) Tagen", value: $abnahmeInTagen, in: 1...180)
                    TextField("Bemerkung für die Verwaltung", text: $amtlicheBemerkung, axis: .vertical)
                    TextField("Interne Bemerkung", text: $interneBemerkung, axis: .vertical)
                }

                Section {
                    Button("Plakat speichern") { speichere() }
                        .disabled(foto == nil || standort.position == nil || !model.istEingerichtet)
                }
            }
            .navigationTitle("Erfassen")
            .fullScreenCover(isPresented: $kameraOffen) {
                KameraAufnahme { aufgenommen in
                    if let aufgenommen { foto = aufgenommen }
                    kameraOffen = false
                }
                .ignoresSafeArea()
            }
            .task { standort.starte() }
            .onDisappear { standort.stoppe() }
        }
    }

    private func speichere() {
        guard let foto, let position = standort.position else { return }
        model.erfassePlakat(
            foto: foto,
            latitude: position.coordinate.latitude,
            longitude: position.coordinate.longitude,
            adresse: adresse,
            typ: typ,
            abnahmeInTagen: abnahmeInTagen,
            amtlicheBemerkung: amtlicheBemerkung,
            interneBemerkung: interneBemerkung
        )
        self.foto = nil
        adresse = ""
        amtlicheBemerkung = ""
        interneBemerkung = ""
    }
}
