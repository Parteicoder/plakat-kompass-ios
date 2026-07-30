import PlakatKompassCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct PlakatKompassApp: App {
    @StateObject private var model = AppModel()

    /// Der Tour-Aufzeichner gehört **der App**, nicht einem Bildschirm.
    ///
    /// Vorher stand er als `@StateObject` in `FlyerTourenView`. Damit lebte er nur, solange die
    /// Ansicht auf dem Navigationsstapel lag — wer nach dem Start der Tour zurückging, tötete
    /// den `CLLocationManager`, und die Aufzeichnung endete lautlos.
    ///
    /// Das ist genau der Ablauf, für den die Funktion gedacht ist: Tour starten, Telefon
    /// einstecken, Flyer verteilen. Der Fehler wäre nur auf einem Gerät aufgefallen, und dort
    /// hätte er wie ein Problem mit der Ortung ausgesehen.
    @StateObject private var aufzeichnung = TourAufzeichnung()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(aufzeichnung)
                // Der ganze Android-iOS-Abgleich haengt an dieser einen Zeile: Ein Sync-Paket
                // kommt als Datei herein, egal ob aus einem Messenger, aus Mail, per AirDrop
                // oder aus der Dateien-App.
                .onOpenURL { url in model.importiereSyncPaket(von: url) }
                .task { await model.beimStart() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            StartView()
                .tabItem { Label("Start", systemImage: "house") }
            CaptureView()
                .tabItem { Label("Erfassen", systemImage: "camera") }
            PosterListView()
                .tabItem { Label("Liste", systemImage: "list.bullet") }
                // Die Zahl der fälligen Abnahmen am Reiter. Wer die App öffnet, soll nicht erst
                // suchen müssen, ob etwas ansteht.
                .badge(model.faelligeAbnahmen)
            PosterMapView()
                .tabItem { Label("Karte", systemImage: "map") }
            SyncView()
                .tabItem { Label("Abgleich", systemImage: "arrow.triangle.2.circlepath") }
        }
        .alert("Fehler", isPresented: .constant(model.fehler != nil)) {
            Button("OK") { model.fehler = nil }
        } message: {
            Text(model.fehler ?? "")
        }
        .overlay(alignment: .top) {
            if let meldung = model.meldung {
                Text(meldung)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        model.meldung = nil
                    }
            }
        }
    }
}
