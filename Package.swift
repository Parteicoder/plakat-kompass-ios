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
    ],
    targets: [
        .target(
            name: "PlakatKompassCore",
            dependencies: ["ZIPFoundation"]
        ),
        .testTarget(
            name: "PlakatKompassCoreTests",
            dependencies: ["PlakatKompassCore"],
            resources: [.copy("Vektoren")]
        )
    ]
)
