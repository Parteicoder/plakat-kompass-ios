import PlakatKompassCore
import SwiftUI

/// „Experten" — Gegenstück zu `ModernExpertScreen.kt`: Handywechsel und Diagnose.
///
/// Der Bildschirm liegt bewusst **hinter** den Einstellungen und nicht in der Reiterleiste. Was
/// hier steht, braucht man ein- oder zweimal im Leben der App: beim Umzug auf ein neues Telefon
/// und wenn etwas nicht geht und jemand fragt, was im Protokoll steht.
struct ExpertenView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var umzug: HandywechselNearby

    @State private var empfangBestaetigen = false

    init(model: AppModel) {
        _umzug = StateObject(wrappedValue: HandywechselNearby(model: model))
    }

    var body: some View {
        List {
            Handywechsel(umzug: umzug, empfangBestaetigen: $empfangBestaetigen)
            Diagnose(umzug: umzug)
        }
        .navigationTitle("Experten")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { umzug.stop() }
        .confirmationDialog(
            "Alles auf diesem Gerät überschreiben?",
            isPresented: $empfangBestaetigen,
            titleVisibility: .visible
        ) {
            Button("Backup empfangen", role: .destructive) { umzug.empfange() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("""
            Ein Handywechsel ist kein Abgleich: Der Stand des alten Geräts ersetzt alles, was \
            hier ist — Plakate, Touren, Team und Rolle. Was auf diesem Gerät nur lokal erfasst \
            wurde, ist danach weg.
            """)
        }
    }
}

private struct Handywechsel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var umzug: HandywechselNearby
    @Binding var empfangBestaetigen: Bool

    var body: some View {
        Section {
            switch umzug.zustand {
            case .aus:
                Button {
                    umzug.sende()
                } label: {
                    Label("Auf ein neues Gerät umziehen", systemImage: "iphone.and.arrow.forward")
                }
                .disabled(!model.istEingerichtet)

                Button {
                    empfangBestaetigen = true
                } label: {
                    Label("Von einem alten Gerät übernehmen", systemImage: "square.and.arrow.down")
                }

            case .sucht(let rolle):
                HStack {
                    ProgressView()
                    Text(rolle == .senden
                         ? "Warte auf das neue Gerät …"
                         : "Warte auf das alte Gerät …")
                        .padding(.leading, 8)
                }
                Button("Abbrechen", role: .cancel) { umzug.stop() }

            case .uebertraegt:
                HStack {
                    ProgressView()
                    Text("Übertragung läuft …").padding(.leading, 8)
                }

            case .fertig(let text):
                Label(text, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Button("Fertig") { umzug.stop() }

            case .fehler(let text):
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Noch einmal") { umzug.stop() }
            }
        } header: {
            Text("Handywechsel")
        } footer: {
            Text("""
            Auf dem **alten** Gerät „umziehen" wählen, auf dem **neuen** „übernehmen" — beide \
            Bildschirme müssen gleichzeitig offen sein, und beide Telefone im selben WLAN. \
            Übertragen wird alles: Plakate mit Fotos, Touren, Team und Rolle. Das Backup ist \
            verschlüsselt, und der Schlüssel gilt nur für diesen einen Umzug.

            Danach das alte Gerät **nicht** weiterbenutzen: Beide trügen dieselbe \
            Geräte-Kennung, und das Team hielte sie für ein einziges Gerät.
            """)
        }
    }
}

private struct Diagnose: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var umzug: HandywechselNearby

    var body: some View {
        Section {
            LabeledContent("Geräte-Kennung", value: String(model.state.deviceId.prefix(12)))
            LabeledContent("Plakate", value: "\(model.state.posters.count)")
            LabeledContent("Touren", value: "\(model.state.flyerTours.count)")
            LabeledContent("Gelöschte (Grabsteine)", value: "\(model.state.deletedPosters.count)")
            LabeledContent("Ereignisse", value: "\(model.state.events.count)")
            LabeledContent("Abgleich-Dienst", value: NearbyDienst.bonjourTyp)
            LabeledContent("Handywechsel-Dienst", value: NearbyDienst.backupBonjourTyp)
        } header: {
            Text("Diagnose")
        } footer: {
            Text("""
            Die beiden Dienstnamen stehen hier, weil genau sie stumm versagen: Fehlt einer in \
            den Berechtigungen der App, findet das iPhone nie ein Gerät — ohne Meldung.
            """)
        }

        Section {
            if umzug.protokoll.isEmpty {
                Text("Noch nichts passiert.").foregroundStyle(.secondary)
            }
            ForEach(Array(umzug.protokoll.enumerated().reversed()), id: \.offset) { _, zeile in
                Text(zeile).font(.caption).textSelection(.enabled)
            }
        } header: {
            Text("Protokoll Handywechsel")
        }

        Section {
            if model.nearby.protokoll.isEmpty {
                Text("Noch nichts passiert.").foregroundStyle(.secondary)
            }
            ForEach(Array(model.nearby.protokoll.enumerated().reversed()), id: \.offset) { _, zeile in
                Text(zeile).font(.caption).textSelection(.enabled)
            }
        } header: {
            Text("Protokoll Funk-Abgleich")
        } footer: {
            Text("""
            Neueste Meldung oben. Das Protokoll lebt nur, solange die App läuft — es landet \
            weder auf der Platte noch bei uns.
            """)
        }
    }
}
