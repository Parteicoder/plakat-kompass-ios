// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlakatKompass",
    // macOS muss mit dabei stehen, obwohl es keine Mac-App gibt: `swift test` uebersetzt den
    // Kern fuer macOS. Ohne diese Zeile gilt dort die uralte Voreinstellung, und dann sind
    // CryptoKit (ab 10.15) und .completeFileProtection (ab 11) nicht verfuegbar.
    platforms: [.iOS(.v16), .macOS(.v13)],
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
