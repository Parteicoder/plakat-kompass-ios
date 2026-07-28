import PlakatKompassCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct PlakatKompassApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // Der ganze Android-iOS-Abgleich haengt an dieser einen Zeile: Ein Sync-Paket
                // kommt als Datei herein, egal ob aus einem Messenger, aus Mail, per AirDrop
                // oder aus der Dateien-App.
                .onOpenURL { url in model.importiereSyncPaket(von: url) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Erfassen", systemImage: "camera") }
            PosterListView()
                .tabItem { Label("Liste", systemImage: "list.bullet") }
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
