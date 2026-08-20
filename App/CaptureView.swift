import CoreLocation
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
    @StateObject private var adressSuche = AdresseAufloesen()
    @State private var manuelleAdresse = ""

    // Standortpruefung beim Speichern, sinngemaess wie Androids PosterPhotoLocationValidation.kt:
    // fehlender/unbewertbarer/zu alter Fix blockiert, schlechte Genauigkeit fragt nach.
    @State private var standortFehler: String?
    @State private var ungenaueGenauigkeitBestaetigen = false
    // Gegenstück zu BswHelpDialog "Foto & Standort" (PosterPhotoCaptureSection.kt) - erklärt
    // die Genauigkeitsstufen, bevor jemand ratlos vor "über 10 m" steht.
    @State private var hilfeOffen = false

    /// Der Ort, der wirklich benutzt wird: Handeingabe schlaegt Ortung. Genau EINE Stelle, an
    /// der das entschieden wird - sonst prueft der Speichern-Knopf etwas anderes als das, was
    /// gespeichert wird, und das faellt erst auf, wenn ein Plakat am falschen Fleck steht.
    private var wirksamerOrt: CLLocationCoordinate2D? {
        adressSuche.treffer?.ort ?? standort.position?.coordinate
    }

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
                            hilfeOffen = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Hilfe zu Foto & Standort")
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
                    if let gefunden = adressSuche.treffer {
                        // Die Handeingabe schlaegt das GPS, solange sie steht - wer sie benutzt
                        // hat, hat sich bewusst dafuer entschieden.
                        LabeledContent("Von Hand", value: gefunden.beschriftung)
                        Button("Wieder Ortung benutzen") { adressSuche.verwirf() }
                            .font(.footnote)
                    } else if standort.abgelehnt {
                        Label("Ortung ist abgelehnt.", systemImage: "location.slash")
                            .foregroundStyle(.red)
                    } else if let position = standort.position {
                        LabeledContent("Genauigkeit", value: "ca. \(Int(position.horizontalAccuracy)) m")
                        // Dreistufige Rueckmeldung statt eines einzelnen 30-m-Schwellwerts -
                        // sinngemaess PosterPhotoLocationValidation.accuracyWarning wie auf Android.
                        if let hinweis = PosterPhotoLocationValidation.accuracyWarning(
                            accuracyMeters: position.horizontalAccuracy >= 0 ? position.horizontalAccuracy : nil
                        ) {
                            Text(hinweis)
                                .font(.footnote)
                                .foregroundStyle(position.horizontalAccuracy > PosterPhotoLocationValidation.okAccuracyMeters ? .red : .orange)
                        }
                    } else {
                        Label("Standort wird gesucht …", systemImage: "location")
                            .foregroundStyle(.secondary)
                    }
                }

                // HIER STAND NICHTS, UND DAS WAR DIE LUECKE: Ohne Standort blieb der
                // Speichern-Knopf grau, und zwar endgueltig. Genau die Faelle, in denen man
                // draussen steht und arbeiten will - Haeuserschlucht, Innenhof, einmal
                // abgelehnte Ortung - endeten damit. Android laesst dort die Adresse tippen.
                //
                // Angeboten wird der Weg nur, wenn die Ortung tatsaechlich nichts liefert.
                // Immer sichtbar waere er eine zweite Art, dasselbe zu tun, und die schlechtere.
                if standort.position == nil && adressSuche.treffer == nil {
                    Section {
                        TextField("Straße Hausnummer, PLZ Stadt", text: $manuelleAdresse)
                            .textContentType(.fullStreetAddress)
                            .autocorrectionDisabled()
                        Button {
                            adressSuche.suche(manuelleAdresse)
                        } label: {
                            if adressSuche.laeuft {
                                HStack { ProgressView(); Text("Wird gesucht …").padding(.leading, 8) }
                            } else {
                                Label("Adresse suchen", systemImage: "mappin.and.ellipse")
                            }
                        }
                        .disabled(manuelleAdresse.trimmingCharacters(in: .whitespaces).isEmpty
                                  || adressSuche.laeuft)

                        if let fehler = adressSuche.fehler {
                            Text(fehler).font(.footnote).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Standort von Hand")
                    } footer: {
                        Text("""
                        Wenn die Ortung nicht greift — enge Bebauung, Innenhof, abgelehnte \
                        Berechtigung. Die Adresse wird über das Netz in Koordinaten umgesetzt; \
                        dafür genügt Mobilfunk, GPS-Empfang braucht es nicht. Der Marker sollte \
                        danach auf der Karte geprüft werden.
                        """)
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
                    Button("Plakat speichern") { pruefeStandortUndSpeichere() }
                        .disabled(foto == nil || wirksamerOrt == nil || !model.istEingerichtet)
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
            .alert("Standort ungültig", isPresented: .constant(standortFehler != nil)) {
                Button("OK") { standortFehler = nil }
            } message: {
                Text(standortFehler ?? "")
            }
            .alert("Foto & Standort", isPresented: $hilfeOffen) {
                Button("Fertig") {}
            } message: {
                Text("""
                Die App versucht beim Foto automatisch, den Standort zu ermitteln. \
                Ideal sind 3 bis 5 m Genauigkeit. Bis 10 m wird der Standort direkt \
                übernommen. Über 10 m fragt die App nach, ob du den Standort trotzdem \
                übernehmen willst. Alternativ kannst du die Adresse manuell eingeben.
                """)
            }
            .confirmationDialog(
                standort.position.map { PosterPhotoLocationValidation.confirmationMessage(accuracyMeters: $0.horizontalAccuracy) } ?? "",
                isPresented: $ungenaueGenauigkeitBestaetigen,
                titleVisibility: .visible
            ) {
                Button("Trotzdem übernehmen") { speichere() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    /// Blockiert bei fehlendem, unbewertbarem oder zu altem GPS-Fix (sinngemaess Androids
    /// `validatePosterPhotoLocation`) und fragt bei schlechter Genauigkeit erst nach
    /// (`shouldConfirmInaccurateLocation`), bevor tatsaechlich gespeichert wird. Die
    /// Handeingabe-Adresse hat kein GPS-Alter und keine GPS-Genauigkeit - dafuer greift die
    /// Pruefung nicht, genau wie sie auf Android fuer diesen Weg gar nicht existiert.
    private func pruefeStandortUndSpeichere() {
        guard adressSuche.treffer == nil, let position = standort.position else {
            speichere()
            return
        }

        let accuracyMeters: Double? = position.horizontalAccuracy >= 0 ? position.horizontalAccuracy : nil
        let timestampMs = Int64(position.timestamp.timeIntervalSince1970 * 1000)

        let ergebnis = PosterPhotoLocationValidation.validate(accuracyMeters: accuracyMeters, timestampMs: timestampMs)
        guard ergebnis.isValid else {
            standortFehler = ergebnis.errorMessage
            return
        }

        if PosterPhotoLocationValidation.shouldConfirmInaccurateLocation(accuracyMeters: accuracyMeters, timestampMs: timestampMs) {
            ungenaueGenauigkeitBestaetigen = true
            return
        }

        speichere()
    }

    private func speichere() {
        guard let foto, let ort = wirksamerOrt else { return }

        // Wer die Adresse von Hand gesucht hat und das Hinweisfeld leer liess, bekommt Apples
        // saubere Schreibweise als Hinweis. Eigene Eingabe hat aber Vorrang - sie steht oft
        // genauer da ("Laterne gegenueber Nr. 12").
        let hinweis = adresse.isEmpty ? (adressSuche.treffer?.beschriftung ?? "") : adresse

        let geklappt = model.erfassePlakat(
            foto: foto,
            latitude: ort.latitude,
            longitude: ort.longitude,
            adresse: hinweis,
            typ: typ,
            abnahmeInTagen: abnahmeInTagen,
            amtlicheBemerkung: amtlicheBemerkung,
            interneBemerkung: interneBemerkung
        )

        // Das Formular NUR bei Erfolg leeren.
        //
        // Vorher wurde es in jedem Fall geleert. Wer beim Speichern einen Fehler bekam — kein
        // Platz auf dem Gerät, kein Team — stand mit einer Meldung da und ohne Foto, mitten auf
        // der Straße, und musste zum Plakat zurück. Die Meldung erschien, das Bild war weg.
        guard geklappt else { return }
        self.foto = nil
        adresse = ""
        // Auch die Handeingabe zuruecksetzen: Das naechste Plakat steht woanders, und eine
        // stehengebliebene Adresse waere der sicherste Weg zu zwei Plakaten auf einem Punkt.
        manuelleAdresse = ""
        adressSuche.verwirf()
        amtlicheBemerkung = ""
        interneBemerkung = ""
        // Art und Abnahmefrist bleiben stehen: Das nächste Plakat ist meistens dasselbe an der
        // nächsten Laterne, und eine Kampagne hat eine Frist.
    }
}
