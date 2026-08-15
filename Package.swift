// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlakatKompass",
    // iOS 17, weil die Oberflaeche darauf aufbaut: Map(position:), Annotation,
    // MapUserLocationButton, ContentUnavailableView und .topBarLeading gibt es nicht frueher.
    // Ausgeschlossen sind damit iPhone X, 8 und 8 Plus - Geraete von 2017. Ab dem iPhone XS
    // von 2018 laeuft alles.
    //
    // macOS muss mit dabei stehen, obwohl es keine Mac-App gibt: `swift test` uebersetzt den
    // Kern fuer macOS. Ohne diese Zeile gilt dort die uralte Voreinstellung, und dann sind
    // CryptoKit (ab 10.15) und .completeFileProtection (ab 11) nicht verfuegbar.
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PlakatKompassCore", targets: ["PlakatKompassCore"])
    ],
    dependencies: [
        // ZIP-Lesen und -Schreiben. Foundation kann das nicht, und ein selbst gebauter
        // ZIP-Parser waere an dieser Stelle die falsche Sparsamkeit: Er muss Deflate
        // beherrschen und gleichzeitig gegen ZIP-Bomben dichthalten.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
        //
        // NEARBY CONNECTIONS STEHT HIER BEWUSST NICHT. Der Funk-Abgleich mit Android braucht es,
        // aber es gehoert zur App und nicht zum geteilten Kern: Das Paket zieht abseil, BoringSSL,
        // protobuf und den ganzen C++-Kern von Nearby als Quelltext mit. Stuende es hier, muesste
        // jedes "swift build" und jedes "swift test" das mitbauen - fuer einen Kern, der davon
        // kein Byte benutzt. Die Abhaengigkeit steht in project.yml am App-Ziel.
    ],
    targets: [
        .target(
            name: "PlakatKompassCore",
            dependencies: ["ZIPFoundation"],
            // Bundeswahlkreis-Umrisse fuer die Wahldaten-Gebietssuche. Dieselbe Datei wie im
            // Android-Repo (app/src/main/assets/wahlkreise_btw25.geojson) - eine zweite Herleitung
            // waere nur eine zweite Fehlerquelle.
            resources: [.copy("Resources/wahlkreise_btw25.geojson")]
        ),
        .testTarget(
            name: "PlakatKompassCoreTests",
            dependencies: ["PlakatKompassCore"],
            resources: [.copy("Vektoren")]
        )
    ]
)
