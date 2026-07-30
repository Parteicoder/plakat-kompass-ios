import PlakatKompassCore
import SwiftUI
import UIKit
import UserNotifications

/// Einstellungen. Gegenstück zum Bereich „Mehr" auf Android — auf das reduziert, was auf iOS
/// überhaupt in einer App einstellbar ist.
///
/// Vieles, was drüben hier steht, gehört auf iOS in die Systemeinstellungen: Berechtigungen für
/// Kamera, Ort und Meldungen lassen sich nicht in der App umschalten. Sie hier nachzubauen hieße,
/// Schalter zu zeigen, die nichts tun. Stattdessen führt ein Verweis dorthin.
struct EinstellungenView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage("pausenErinnerung") private var pausenErinnerung = false
    @AppStorage("pausenMinuten") private var pausenMinuten = Erinnerungen.pausenVorgabeMinuten
    @State private var meldungenErlaubt: UNAuthorizationStatus = .notDetermined

    // Die Abschnitte stehen einzeln, nicht als ein grosses `body`.
    //
    // Nicht aus Ordnungsliebe: Bei allem in einem Ausdruck gibt Swifts Typprüfer auf --
    // "unable to type-check this expression in reasonable time". Die Meldung nennt nur die Zeile
    // mit `body` und sagt nicht, welcher Teil zu viel war. Kleine Abschnitte sind die Loesung
    // UND die Vorbeugung.
    var body: some View {
        List {
            pausenAbschnitt
            berechtigungenAbschnitt
            geraeteAbschnitt
            Section {
                // Der Verlauf ist die einzige Stelle, an der nachvollziehbar wird, wer wann was
                // geaendert hat - wichtig, wenn im Team Unklarheit ueber ein Plakat entsteht.
                NavigationLink("Verlauf") { VerlaufView() }
                NavigationLink("Lizenzen und Dank") { LizenzenView() }
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { meldungenErlaubt = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: pausenErinnerung) { _, an in
            Task { an ? await Erinnerungen.startePause(minuten: pausenMinuten) : Erinnerungen.beendePause() }
        }
        .onChange(of: pausenMinuten) { _, neu in
            guard pausenErinnerung else { return }
            Task { await Erinnerungen.startePause(minuten: neu) }
        }
    }

    @ViewBuilder private var pausenAbschnitt: some View {
        Section {
            Toggle("Ans Trinken erinnern", isOn: $pausenErinnerung)
            if pausenErinnerung {
                Stepper(value: $pausenMinuten, in: Erinnerungen.pausenSpanne, step: 15) {
                    Text("Alle \(pausenMinuten) Minuten")
                }
            }
        } header: {
            Text("Pausen")
        } footer: {
            Text("""
            Wer im Sommer vier Stunden mit Leiter und Kabelbindern unterwegs ist, vergisst das \
            Trinken. Die Erinnerung läuft, bis sie hier wieder ausgeschaltet wird.
            """)
        }
    }

    @ViewBuilder private var berechtigungenAbschnitt: some View {
        Section {
            LabeledContent("Meldungen") {
                Text(meldungenText)
                    .foregroundStyle(meldungenErlaubt == .authorized ? Color.secondary : Color.orange)
            }
            Button("Systemeinstellungen öffnen") {
                if let ziel = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(ziel)
                }
            }
        } header: {
            Text("Berechtigungen")
        } footer: {
            Text("""
            Kamera, Ort und Meldungen verwaltet iOS. Die App kann sie nicht selbst umschalten — \
            hier geht es direkt zur richtigen Stelle.
            """)
        }
    }

    @ViewBuilder private var geraeteAbschnitt: some View {
        Section("Dieses Gerät") {
            LabeledContent("Name", value: model.state.deviceName)
            LabeledContent("Rolle", value: model.state.role == .LEADER ? "Teamleitung" : "Mitglied")
            LabeledContent("Team", value: model.state.teamName ?? "—")
            LabeledContent("Plakate", value: "\(model.state.posters.count)")
            LabeledContent("Touren", value: "\(model.state.flyerTours.count)")
        }
    }

    private var meldungenText: String {
        switch meldungenErlaubt {
        case .authorized, .provisional, .ephemeral: return "erlaubt"
        case .denied: return "abgelehnt"
        default: return "noch nicht gefragt"
        }
    }
}

/// Wer wann was geändert hat.
private struct VerlaufView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.state.events) { ereignis in
            VStack(alignment: .leading, spacing: 3) {
                Text(ereignis.action).font(.subheadline)
                Text("\(ereignis.actorName) · \(zeit(ereignis.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.state.events.isEmpty {
                Text("Noch nichts passiert.").foregroundStyle(.secondary)
            }
        }
    }

    private func zeit(_ millis: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}

/// Lizenzen und Dank.
///
/// Zwei Pflichten: Die Gemeindegrenzen stammen aus OpenStreetMap und stehen unter der ODbL, die
/// Namensnennung verlangt. Die Sozialdaten sind amtlich und stehen unter einer Lizenz mit
/// Namensnennung.
///
/// Die Karte selbst braucht hier nichts: Sie läuft über MapKit, und Apple setzt seinen Hinweis
/// samt „Rechtliche Hinweise" von sich aus in die Karte. Das ist der Unterschied zur
/// Android-Fassung, die OSM-Kacheln über osmdroid zeichnet und den Hinweis selbst setzen muss.
private struct LizenzenView: View {
    var body: some View {
        List {
            Section("Diese App") {
                Text("""
                Plakat Kompass steht unter der GNU Affero General Public License, Version 3 \
                (AGPL-3.0). Der Lizenztext liegt der Quelle als Datei LICENSE bei.
                """)
            }
            Section("Gemeindegrenzen") {
                Text("""
                © OpenStreetMap-Mitwirkende, abgefragt über die Overpass-Schnittstelle. Die Daten \
                stehen unter der Open Database License (ODbL) 1.0.
                """)
            }
            Section("Sozialdaten") {
                Text("""
                Regionalatlas Deutschland und Zensus 2022, Statistische Ämter des Bundes und der \
                Länder. Datenlizenz Deutschland – Namensnennung – Version 2.0 (dl-de/by-2-0).
                """)
            }
            Section("Karte") {
                Text("Apple MapKit. Den Kartenhinweis setzt iOS selbst in die Karte.")
            }
            Section("Verwendete Bibliothek") {
                Text("ZIPFoundation von Thomas Zoechling, MIT-Lizenz.")
            }
            Section("Dank") {
                Text("Malte Steinbach")
            }
        }
        .navigationTitle("Lizenzen und Dank")
        .navigationBarTitleDisplayMode(.inline)
    }
}
