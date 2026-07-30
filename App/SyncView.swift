import PlakatKompassCore
import SwiftUI
import UniformTypeIdentifiers

struct SyncView: View {
    @EnvironmentObject private var model: AppModel

    @State private var teilenDatei: URL?
    @State private var importDialogOffen = false
    @State private var teamDialogOffen = false
    @State private var erneuernBestaetigen = false

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
                                teilenDatei = model.erzeugeSyncPaket()
                            } label: {
                                Label("Sync-Paket teilen", systemImage: "square.and.arrow.up")
                            }
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

/// Die Plakatliste für die Stadtverwaltung.
///
/// Der Kommunenname bleibt gespeichert: Wer für eine Gemeinde plakatiert, exportiert über Wochen
/// immer wieder für dieselbe, und ihn jedes Mal neu einzutippen wäre nur Reibung.
private struct VerwaltungsExport: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("kommune") private var kommune = ""
    @Binding var teilenDatei: URL?

    var body: some View {
        Section {
            TextField("Kommune", text: $kommune)
                .textInputAutocapitalization(.words)
            Button {
                teilenDatei = model.erzeugeVerwaltungsExport(kommune: kommune)
            } label: {
                Label("Liste für die Verwaltung", systemImage: "doc.text")
            }
            .disabled(model.state.posters.isEmpty)
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
