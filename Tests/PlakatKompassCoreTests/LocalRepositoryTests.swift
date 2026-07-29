import Foundation
import XCTest
@testable import PlakatKompassCore

/// Prüft das **zweite** JSON-Schema im Projekt.
///
/// `LocalRepository` speichert nicht dasselbe wie ein Sync-Paket: Hier stehen zusätzlich das
/// Team-Geheimnis und die Rolle, die ein Paket niemals verlassen dürfen. Damit ist es ein eigenes
/// Format mit eigenen Feldnamen — und bis hierhin ungeprüft.
///
/// Was schiefgehen kann, ist unspektakulär und teuer: Wenn ein Feld beim Schreiben anders heißt
/// als beim Lesen, fällt beim Übersetzen nichts auf. Die App startet, der Stand ist leer, und die
/// Arbeit eines Nachmittags ist weg. Deshalb hier der vollständige Hin- und Rückweg.
final class LocalRepositoryTests: XCTestCase {

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func vollerStand() -> LocalTeamState {
        var plakat = Poster(
            id: "poster-1",
            teamId: "team-1",
            latitude: 51.46,
            longitude: 12.63,
            addressHint: "Am Markt 1",
            type: .TRIANGLE_STAND,
            status: .DAMAGED,
            localPhotoFileName: "foto.jpg",
            createdByDeviceId: "device-1",
            createdByName: "David",
            createdAt: 1000,
            updatedAt: 2000,
            plannedRemovalAt: 9000,
            officialNote: "Für die Verwaltung",
            internalNote: "Intern"
        )
        // Ein zweites Plakat ohne Foto und ohne Frist: Genau die beiden Felder, bei denen
        // "nicht gesetzt" und "leer" auseinanderlaufen koennen.
        var ohneExtras = plakat
        ohneExtras.id = "poster-2"
        ohneExtras.localPhotoFileName = nil
        ohneExtras.plannedRemovalAt = nil
        ohneExtras.addressHint = ""

        return LocalTeamState(
            deviceId: "device-1",
            deviceName: "Davids iPhone",
            role: .LEADER,
            teamId: "team-1",
            teamName: "BSW Nordsachsen",
            teamSecret: "0123456789abcdef",
            devices: [
                DeviceRecord(
                    deviceId: "device-1", displayName: "Davids iPhone", role: .LEADER,
                    joinedAt: 100, approved: true, blocked: false
                ),
                DeviceRecord(
                    deviceId: "device-2", displayName: "Gast", role: .MEMBER,
                    joinedAt: 200, approved: false, blocked: true
                )
            ],
            posters: [plakat, ohneExtras],
            deletedPosters: [
                PosterTombstone(
                    posterId: "poster-9", teamId: "team-1",
                    deletedByDeviceId: "device-1", deletedByName: "David", deletedAt: 3000
                )
            ],
            events: [
                PosterEvent(
                    id: "event-1", posterId: "poster-1", teamId: "team-1",
                    actorDeviceId: "device-1", actorName: "David",
                    action: "Status: Beschädigt", createdAt: 2500
                )
            ],
            flyerTours: [
                FlyerTour(
                    id: "tour-1", teamId: "team-1", name: "Eilenburg Nord", status: .PAUSED,
                    points: [
                        FlyerTrackPoint(latitude: 51.0, longitude: 12.0, createdAt: 1000),
                        FlyerTrackPoint(latitude: 51.1, longitude: 12.1, createdAt: 2000)
                    ],
                    createdByDeviceId: "device-1", createdByName: "David",
                    startedAt: 900, updatedAt: 2100, finishedAt: nil
                )
            ]
        )
    }

    func testSchreibenUndLesenAendertNichts() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        let stand = vollerStand()

        try repo.save(stand)
        let gelesen = try LocalRepository(ordner: ordner, geraeteName: "Testgerät").load()

        XCTAssertEqual(gelesen, stand, "Der lokale Stand muss den Weg durch das JSON unveraendert ueberstehen.")
    }

    func testDasTeamGeheimnisWirdMitgespeichert() throws {
        // Ohne das Geheimnis liesse sich nach einem Neustart kein Paket mehr entschluesseln -
        // das Team waere aus Sicht des Geraets verloren.
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        try repo.save(vollerStand())

        let roh = try String(
            contentsOf: ordner.appendingPathComponent("teamstate.json"), encoding: .utf8
        )
        XCTAssertTrue(roh.contains("0123456789abcdef"))
        XCTAssertTrue(roh.contains("\"schemaVersion\""))
    }

    func testFehlendeFelderBleibenFehlend() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        try repo.save(vollerStand())

        let gelesen = repo.load()
        let ohneExtras = try XCTUnwrap(gelesen.posters.first { $0.id == "poster-2" })

        // Der haeufigste Portierungsfehler zwischen org.json und JSONSerialization: aus einem
        // fehlenden Wert wird "" oder 0 statt nil.
        XCTAssertNil(ohneExtras.localPhotoFileName)
        XCTAssertNil(ohneExtras.plannedRemovalAt)
        XCTAssertEqual(ohneExtras.addressHint, "")
    }

    func testOhneDateiKommtEinFrischerStand() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        let frisch = repo.load()

        XCTAssertEqual(frisch.deviceName, "Testgerät")
        XCTAssertFalse(frisch.deviceId.isEmpty, "Ohne Geraete-Kennung liesse sich nichts zuordnen.")
        XCTAssertNil(frisch.teamId)
        XCTAssertTrue(frisch.posters.isEmpty)
    }

    func testKaputteDateiVerliertNichtDenStartDerApp() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        try Data("kein JSON".utf8).write(to: ordner.appendingPathComponent("teamstate.json"))

        // Lieber ein leerer Stand als eine App, die nicht mehr startet. Die alte Datei bleibt
        // dabei liegen - wer sie retten will, kommt noch heran.
        let gelesen = repo.load()
        XCTAssertTrue(gelesen.posters.isEmpty)
        XCTAssertNil(gelesen.teamId)
    }

    func testVerwaisteFotosWerdenAufgeraeumt() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        let gebraucht = try repo.speichereFoto(Data("bild".utf8))
        let verwaist = try repo.speichereFoto(Data("altes bild".utf8))

        var stand = vollerStand()
        var mitFoto = stand.posters[0]
        mitFoto.localPhotoFileName = gebraucht
        stand.posters = [mitFoto]

        repo.raeumeVerwaisteFotosAuf(stand)

        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.photoURL(gebraucht).path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repo.photoURL(verwaist).path),
            "Ohne Aufraeumen waechst der Fotoordner unbegrenzt."
        )
    }

    func testSnapshotBrauchtEinTeam() throws {
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        var ohneTeam = vollerStand()
        ohneTeam.teamId = nil

        XCTAssertThrowsError(try repo.toSnapshot(ohneTeam)) { fehler in
            XCTAssertEqual(fehler as? SyncError, .fremdesTeam)
        }
    }

    func testSnapshotTraegtNurDenHashDesGeheimnisses() throws {
        // Das Geheimnis selbst darf das Geraet nie verlassen. Steht es im Snapshot, steht es im
        // Sync-Paket, und wer den Team-Schluessel einmal hat, ist dauerhaft im Team.
        let repo = try LocalRepository(ordner: ordner, geraeteName: "Testgerät")
        let snapshot = try repo.toSnapshot(vollerStand())

        XCTAssertEqual(snapshot.teamSecretHash, Crypto.sha256Hex("0123456789abcdef"))
        XCTAssertNotEqual(snapshot.teamSecretHash, "0123456789abcdef")
    }
}
