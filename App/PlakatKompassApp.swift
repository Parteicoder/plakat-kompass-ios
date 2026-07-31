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

    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(aufzeichnung)
                // Der Funk-Abgleich endet, sobald die App in den Hintergrund geht. Nearby
                // Connections laeuft auf iOS nur im Vordergrund; iOS friert die App ein und die
                // Verbindungen fallen. Wuerde der Schalter trotzdem auf „an" stehen bleiben,
                // behauptete er etwas, das nicht stimmt — und man suchte den Fehler beim WLAN.
                .onChange(of: phase) { _, neu in
                    if neu != .active { model.nearby.stop() }
                }
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

    /// Der TabView hat jetzt eine Auswahl, weil die Kurzanleitung wissen muss, welcher Bereich
    /// gerade offen ist. Die Zeichenketten sind zugleich die Schlüssel in [Kurzanleitung].
    @State private var reiter = "start"
    @AppStorage(Kurzanleitung.schluessel) private var gesehen = ""

    var body: some View {
        TabView(selection: $reiter) {
            StartView()
                .tabItem { Label("Start", systemImage: "house") }
                .tag("start")
            CaptureView()
                .tabItem { Label("Erfassen", systemImage: "camera") }
                .tag("erfassen")
            PosterListView()
                .tabItem { Label("Liste", systemImage: "list.bullet") }
                // Die Zahl der fälligen Abnahmen am Reiter. Wer die App öffnet, soll nicht erst
                // suchen müssen, ob etwas ansteht.
                .badge(model.faelligeAbnahmen)
                .tag("liste")
            PosterMapView()
                .tabItem { Label("Karte", systemImage: "map") }
                .tag("karte")
            SyncView()
                .tabItem { Label("Abgleich", systemImage: "arrow.triangle.2.circlepath") }
                .tag("abgleich")
        }
        // Die Erklärung liegt ÜBER dem echten Bildschirm, nicht davor. Deshalb ein overlay und
        // kein sheet: Wer liest „Filter oben links", soll den Filter oben links sehen.
        .overlay {
            if Kurzanleitung.zeigen(reiter, gesehen: gesehen), let bereich = Kurzanleitung.fuer(reiter) {
                KurzanleitungOverlay(bereich: bereich) {
                    withAnimation { gesehen = Kurzanleitung.gemerkt(reiter, gesehen: gesehen) }
                }
                // Ohne eigene Identität behält SwiftUI beim Reiterwechsel die alte Seitenzahl
                // bei, und die zweite Anleitung startet mitten drin.
                .id(reiter)
            }
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
