import PlakatKompassCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SyncView: View {
    @EnvironmentObject private var model: AppModel

    @State private var teilenDatei: URL?
    @State private var importDialogOffen = false
    @State private var teamDialogOffen = false
    @State private var erneuernBestaetigen = false
    /// Sperrt den „Sync-Paket teilen"-Knopf, solange schon gepackt wird — seit dem Off-Main-Fix
    /// (ZIP in `Task.detached`) blockiert ein laufender Aufruf den Knopf nicht mehr von selbst,
    /// ein zweiter Tipp würde sonst ein zweites Riesen-ZIP parallel bauen.
    @State private var syncPaketWirdErstellt = false

    var body: some View {
        NavigationStack {
            Form {
                if model.istEingerichtet {
                    Section("Team") {
                        LabeledContent("Name", value: model.state.teamName ?? "—")
                        LabeledContent("Dieses Gerät", value: model.state.deviceName)
                        LabeledContent("Rolle", value: model.state.role == .LEADER ? "Teamleiter" : "Mitglied")
                        LabeledContent("Plakate", value: "\(model.state.posters.count)")
                    }

                    // Wer allein losgelegt hat, hat kein Team-Geheimnis. Der Abgleich waere
                    // technisch unmoeglich, deshalb steht hier der Weg dorthin statt eines
                    // ausgegrauten Knopfes, der nicht erklaert, warum er nicht geht.
                    if !model.kannAbgleichen {
                        Section {
                            Button {
                                teamDialogOffen = true
                            } label: {
                                Label("Einem Team beitreten", systemImage: "person.2.badge.plus")
                            }
                        } header: {
                            Text("Abgleich")
                        } footer: {
                            Text("""
                            Du bist ohne Team unterwegs. Erfassen, Liste, Karte und die Liste für \
                            die Verwaltung funktionieren vollständig — nur der Abgleich mit anderen \
                            Geräten braucht den Team-Schlüssel. Die bereits erfassten Plakate \
                            bleiben beim Beitritt erhalten.
                            """)
                        }
                    }

                    if model.kannAbgleichen {
                        FunkAbgleich(nearby: model.nearby)

                        Section {
                            Button {
                                syncPaketWirdErstellt = true
                                Task {
                                    teilenDatei = await model.erzeugeSyncPaket()
                                    syncPaketWirdErstellt = false
                                }
                            } label: {
                                if syncPaketWirdErstellt {
                                    HStack { ProgressView(); Text("Wird gepackt …") }
                                } else {
                                    Label("Sync-Paket teilen", systemImage: "square.and.arrow.up")
                                }
                            }
                            .disabled(syncPaketWirdErstellt)
                            Button {
                                importDialogOffen = true
                            } label: {
                                Label("Sync-Paket öffnen", systemImage: "square.and.arrow.down")
                            }
                        } header: {
                            Text("Abgleich")
                        } footer: {
                            Text("""
                            Das Paket ist verschlüsselt und lässt sich nur mit dem Team-Schlüssel \
                            öffnen. Es kann deshalb bedenkenlos über einen Messenger verschickt \
                            werden. Android und iPhone verstehen dasselbe Format.
                            """)
                        }
                    }

                    // Der amtliche Export braucht kein Team: Die Liste geht ans Rathaus, nicht
                    // an ein anderes Geraet. Ein gesperrtes Geraet ist ausgenommen - wer aus dem
                    // Team geworfen wurde, soll nicht in dessen Namen bei der Gemeinde auftreten.
                    if model.kannExportieren {
                        VerwaltungsExport(teilenDatei: $teilenDatei)
                    }

                    if model.istGesperrt {
                        Section {
                            Text("""
                            Dieses Gerät wurde von der Teamleitung gesperrt. Abgleich und Export \
                            sind deshalb nicht möglich. Die bereits erfassten Plakate bleiben \
                            gespeichert.
                            """)
                            .foregroundStyle(.secondary)
                        } header: {
                            Text("Gesperrt")
                        }
                    }

                    if model.kannAbgleichen {
                        if model.state.role == .LEADER {
                            Section {
                                TeamQrView()
                            } header: {
                                Text("Andere aufnehmen")
                            }
                        }

                        Section("Teamgeräte") {
                            if model.state.devices.isEmpty {
                                Text("Noch keine anderen Geräte.").foregroundStyle(.secondary)
                            }
                            ForEach(model.state.devices, id: \.deviceId) { geraet in
                                GeraeteZeile(geraet: geraet)
                            }
                        }

                        if model.istTeamleitung {
                            Section {
                                Button(role: .destructive) {
                                    erneuernBestaetigen = true
                                } label: {
                                    Label("Team-Schlüssel erneuern", systemImage: "key.horizontal")
                                }
                            } header: {
                                Text("Wenn ein Gerät verloren ging")
                            } footer: {
                                Text("""
                                Ein Gerät zu sperren reicht bei Verlust oder Diebstahl nicht: Wer den \
                                alten Schlüssel hat, kann weiterhin jedes Paket öffnen, das ihm in die \
                                Hände fällt. Nach dem Erneuern müssen alle anderen Geräte einen neuen \
                                QR-Code scannen.
                                """)
                            }
                        }
                    }
                } else {
                    Section {
                        Button {
                            teamDialogOffen = true
                        } label: {
                            Label("Loslegen", systemImage: "person.2.badge.plus")
                        }
                    } header: {
                        Text("Noch nicht eingerichtet")
                    } footer: {
                        Text("""
                        Einem Team beitreten, ein eigenes gründen — oder allein loslegen, wenn du \
                        ohne Team plakatierst. Erst danach lässt sich erfassen.
                        """)
                    }

                    // HIER FEHLTE DER UMZUG, UND DAS WAR EIN ABLAUF-FEHLER, KEIN SCHOENHEITSFEHLER.
                    //
                    // Der Handywechsel-Empfang lag nur unter Einstellungen → Experten. Dorthin
                    // kommt man aber erst mit eingerichtetem Team - man haette also auf dem NEUEN
                    // Telefon erst ein Team anlegen muessen, um es Sekunden spaeter vom Backup
                    // ueberschreiben zu lassen. Auf Android steht "Backup empfangen" direkt auf
                    // dem Einrichtungsbildschirm, und genau dort gehoert es hin: Ein frisches
                    // Geraet hat nichts, und das ist der Moment, in dem man umzieht.
                    //
                    // Der Abschnitt steht NUR hier, im nicht eingerichteten Zustand. Wer schon ein
                    // Team hat, findet den Umzug weiterhin unter Experten - dort mit Rueckfrage,
                    // weil dann tatsaechlich etwas ueberschrieben wuerde.
                    UmzugBeimEinrichten(umzug: model.handywechsel)
                }
            }
            .navigationTitle("Abgleich")
            .confirmationDialog(
                "Team-Schlüssel wirklich erneuern?",
                isPresented: $erneuernBestaetigen,
                titleVisibility: .visible
            ) {
                Button("Erneuern", role: .destructive) { model.erneuereTeamSchluessel() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle anderen Geräte im Team können danach erst wieder abgleichen, wenn sie einen neuen QR-Code gescannt haben.")
            }
            .sheet(isPresented: $teamDialogOffen) { TeamBeitrittView() }
            .sheet(item: $teilenDatei) { datei in TeilenDialog(dateien: [datei]) }
            .fileImporter(
                isPresented: $importDialogOffen,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { ergebnis in
                switch ergebnis {
                case .success(let urls):
                    if let erste = urls.first { model.importiereSyncPaket(von: erste) }
                case .failure(let fehler):
                    model.fehler = fehler.localizedDescription
                }
            }
        }
    }
}

/// Der Abgleich per Funk, ohne dass jemand eine Datei verschicken muss.
///
/// Der Abschnitt sagt beides: was er kann und woran es liegt, wenn nichts passiert. Beide
/// Fehlerfälle auf iOS sind **lautlos** — ein verweigertes lokales Netzwerk und zwei Geräte in
/// verschiedenen WLANs sehen beide aus wie „niemand in der Nähe". Ohne diesen Text sucht man den
/// Fehler beim Team-Schlüssel oder beim anderen Gerät.
private struct FunkAbgleich: View {
    @ObservedObject var nearby: NearbyAbgleich

    var body: some View {
        Section {
            Toggle("Geräte in der Nähe", isOn: Binding(
                get: { nearby.laeuft },
                set: { $0 ? nearby.start() : nearby.stop() }
            ))

            if nearby.laeuft {
                LabeledContent(
                    "Geprüfte Geräte",
                    value: nearby.gepruefteGeraete == 0 ? "sucht …" : "\(nearby.gepruefteGeraete)"
                )
            }

            if nearby.nichtsGefunden {
                StilleErklaeren()
            }

            if let letzte = nearby.protokoll.last {
                Text(letzte).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Funk-Abgleich")
        } footer: {
            Text("""
            Läuft über dieselbe Schnittstelle wie die Android-App und gleicht direkt mit ihr ab — \
            ohne Datei, ohne Messenger. Beide Geräte müssen dafür im **selben WLAN** sein; der \
            Hotspot eines der beiden Telefone genügt. Ohne Netz finden sie sich nicht, dann bleibt \
            das Sync-Paket als Datei. Beim ersten Mal fragt iOS nach dem lokalen Netzwerk — wer \
            hier ablehnt, sieht danach nie ein Gerät, ohne dass es eine Meldung gäbe.
            """)
        }
    }
}

/// „Backup empfangen" für ein Telefon, auf dem noch nichts eingerichtet ist.
///
/// **Ohne Rückfrage, anders als im Experten-Bildschirm.** Dort überschreibt der Empfang einen
/// vorhandenen Stand und muss deshalb bestätigt werden. Hier ist nichts da, was
/// überschrieben werden könnte — eine Warnung „alles wird ersetzt" wäre schlicht unwahr.
private struct UmzugBeimEinrichten: View {
    @ObservedObject var umzug: HandywechselNearby

    var body: some View {
        Section {
            switch umzug.zustand {
            case .aus:
                Button {
                    umzug.empfange()
                } label: {
                    Label("Backup empfangen", systemImage: "iphone.and.arrow.forward")
                }

            case .sucht:
                HStack {
                    ProgressView()
                    Text("Warte auf das alte Gerät …").padding(.leading, 8)
                }
                Button("Abbrechen", role: .cancel) { umzug.stop() }

            case .uebertraegt:
                HStack {
                    ProgressView()
                    Text("Übertragung läuft …").padding(.leading, 8)
                }

            case .fertig(let text):
                Label(text, systemImage: "checkmark.circle").foregroundStyle(.green)

            case .fehler(let text):
                Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Noch einmal") { umzug.stop() }
            }
        } header: {
            Text("Vom alten Handy umziehen")
        } footer: {
            Text("""
            Wechselst du von einem alten Telefon? Dann hier empfangen, statt ein neues Team \
            anzulegen — Plakate, Fotos, Touren, Team und Rolle kommen vollständig mit.

            Auf dem **alten** Gerät dazu Einstellungen → Experten → „Auf ein neues Gerät \
            umziehen" wählen. Beide Telefone müssen im selben WLAN sein.
            """)
        }
    }
}

/// Kommt nach 25 Sekunden Stille — und nur dann.
///
/// Der Fussnotentext unten steht immer da und wird deshalb genau dann nicht gelesen, wenn er
/// gebraucht wird. Dies hier erscheint erst, wenn das Problem eingetreten ist, und nennt beide
/// Ursachen in der Reihenfolge, in der man sie prüfen kann. Der Knopf führt direkt auf die Seite
/// mit dem Schalter „Lokales Netzwerk" — den Weg über Einstellungen → Datenschutz → Lokales
/// Netzwerk → App suchen findet sonst kaum jemand.
private struct StilleErklaeren: View {
    @Environment(\.openURL) private var oeffne

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bisher kein Gerät gefunden", systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text("""
            Zwei mögliche Gründe, beide ohne Fehlermeldung: Die Geräte hängen in \
            verschiedenen WLANs — oder iOS hat beim ersten Mal nach dem lokalen Netzwerk \
            gefragt und die Antwort war „Nicht erlauben".
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            if let einstellungen = URL(string: UIApplication.openSettingsURLString) {
                Button("Lokales Netzwerk prüfen") { oeffne(einstellungen) }
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Die Plakatliste für die Stadtverwaltung.
///
/// Der Kommunenname bleibt gespeichert: Wer für eine Gemeinde plakatiert, exportiert über Wochen
/// immer wieder für dieselbe, und ihn jedes Mal neu einzutippen wäre nur Reibung.
private struct VerwaltungsExport: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("kommune") private var kommune = ""
    @Binding var teilenDatei: URL?
    /// Siehe `syncPaketWirdErstellt` in `SyncView`: derselbe Riegel gegen einen zweiten Tipp,
    /// während schon ein ZIP gepackt wird.
    @State private var wirdErstellt = false

    var body: some View {
        Section {
            TextField("Kommune", text: $kommune)
                .textInputAutocapitalization(.words)
            Button {
                wirdErstellt = true
                Task {
                    teilenDatei = await model.erzeugeVerwaltungsExport(kommune: kommune)
                    wirdErstellt = false
                }
            } label: {
                if wirdErstellt {
                    HStack { ProgressView(); Text("Wird gepackt …") }
                } else {
                    Label("Liste für die Verwaltung", systemImage: "doc.text")
                }
            }
            .disabled(model.state.posters.isEmpty || wirdErstellt)
        } header: {
            Text("Amtlicher Export")
        } footer: {
            Text("""
            Ein ZIP mit der Plakatliste als Tabelle und allen Fotos. Anders als das Sync-Paket ist \
            es unverschlüsselt — es geht an die Verwaltung, nicht an ein Teamgerät. Interne \
            Bemerkungen stehen nicht darin.
            """)
        }
    }
}

private struct GeraeteZeile: View {
    @EnvironmentObject private var model: AppModel
    let geraet: DeviceRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(geraet.displayName)
                Text(geraet.role == .LEADER ? "Teamleiter" : "Mitglied")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if geraet.blocked {
                Text("gesperrt").font(.caption).foregroundStyle(.red)
            } else if !geraet.approved {
                Text("wartet").font(.caption).foregroundStyle(.orange)
            }
        }
        .swipeActions {
            if model.state.role == .LEADER && geraet.deviceId != model.state.deviceId {
                if !geraet.approved || geraet.blocked {
                    Button("Freigeben") { model.gibFrei(geraet) }.tint(.green)
                }
                if !geraet.blocked {
                    Button("Sperren", role: .destructive) { model.sperre(geraet) }
                }
            }
        }
    }
}

/// Damit sich eine URL als `item` an ein Sheet übergeben lässt.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
