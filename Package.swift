// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlakatKompass",
    platforms: [.iOS(.v16)],
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
        )
        // Das Testziel kommt zusammen mit den Testvektoren. Es hier schon einzutragen,
        // bevor Tests/ existiert, laesst jedes `swift build` sofort scheitern.
    ]
)
