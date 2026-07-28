import PlakatKompassCore
import SwiftUI
import UniformTypeIdentifiers

struct SyncView: View {
    @EnvironmentObject private var model: AppModel

    @State private var teilenDatei: URL?
    @State private var importDialogOffen = false
    @State private var teamNameEingabe = ""

    var body: some View {
        NavigationStack {
            Form {
                if model.istImTeam {
                    Section("Team") {
                        LabeledContent("Name", value: model.state.teamName ?? "—")
                        LabeledContent("Dieses Gerät", value: model.state.deviceName)
                        LabeledContent("Rolle", value: model.state.role == .LEADER ? "Teamleiter" : "Mitglied")
                        LabeledContent("Plakate", value: "\(model.state.posters.count)")
                    }

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
                        Das Paket ist verschlüsselt und lässt sich nur mit dem Team-Schlüssel öffnen. \
                        Es kann deshalb bedenkenlos über einen Messenger verschickt werden. \
                        Android und iPhone verstehen dasselbe Format.
                        """)
                    }

                    Section("Teamgeräte") {
                        if model.state.devices.isEmpty {
                            Text("Noch keine anderen Geräte.").foregroundStyle(.secondary)
                        }
                        ForEach(model.state.devices, id: \.deviceId) { geraet in
                            HStack {
                                VStack(alignment: .leading) {
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
                        }
                    }
                } else {
                    Section {
                        TextField("Teamname", text: $teamNameEingabe)
                        Button("Team anlegen") {
                            model.legeTeamAn(name: teamNameEingabe.isEmpty ? "Mein Team" : teamNameEingabe)
                        }
                    } header: {
                        Text("Noch kein Team")
                    } footer: {
                        Text("""
                        Wer einem bestehenden Team beitreten will, braucht dessen Schlüssel. \
                        Der Beitritt über den QR-Code des Teamleiters kommt als Nächstes.
                        """)
                    }

                    Section {
                        Button {
                            importDialogOffen = true
                        } label: {
                            Label("Sync-Paket öffnen", systemImage: "square.and.arrow.down")
                        }
                    } footer: {
                        Text("Ohne Team-Schlüssel lässt sich ein Paket nicht entschlüsseln.")
                    }
                }
            }
            .navigationTitle("Abgleich")
            .sheet(item: $teilenDatei) { datei in
                TeilenDialog(dateien: [datei])
            }
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

/// Damit sich eine URL als `item` an ein Sheet übergeben lässt.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
