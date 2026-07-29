import Foundation
import XCTest
@testable import PlakatKompassCore

/// Portierung von `SyncMergeTest.kt` und `SyncMergeTombstoneTest.kt`.
///
/// `SyncMerge` war bis hierhin die größte ungeprüfte Stelle im Kern: 223 Zeilen, die entscheiden,
/// welche Fassung eines Plakats gewinnt, ob eine Löschung hält und wer wen freigeben darf. Ein
/// Fehler darin verliert Felddaten, ohne dass irgendwo etwas rot wird — das Plakat ist dann
/// einfach weg oder wieder da.
///
/// Die Fälle sind bewusst dieselben wie drüben, in derselben Reihenfolge. Wo eine Seite anders
/// entscheidet als die andere, hat dasselbe Team nach einem Abgleich zwei Wahrheiten, je nachdem,
/// wessen Gerät zusammengeführt hat.
final class SyncMergeTests: XCTestCase {

    private let teamId = "team-1"
    private let teamSecret = "secret-1"

    private func lokal(deviceId: String = "member-phone") -> LocalTeamState {
        LocalTeamState(
            deviceId: deviceId,
            deviceName: "Mitglied",
            role: .MEMBER,
            teamId: teamId,
            teamName: "BSW Nordsachsen",
            teamSecret: teamSecret,
            devices: [
                DeviceRecord(deviceId: deviceId, displayName: "Mitglied", role: .MEMBER),
                DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)
            ]
        )
    }

    private func paket(
        sender: String = "leader-phone",
        senderName: String = "David",
        geheimnis: String? = nil,
        devices: [DeviceRecord] = [],
        posters: [Poster] = [],
        tombstones: [PosterTombstone] = [],
        events: [PosterEvent] = [],
        touren: [FlyerTour] = []
    ) -> SyncSnapshot {
        SyncSnapshot(
            teamId: teamId,
            teamName: "BSW Nordsachsen",
            senderDeviceId: sender,
            senderName: senderName,
            teamSecretHash: Crypto.sha256Hex(geheimnis ?? teamSecret),
            devices: devices,
            posters: posters,
            deletedPosters: tombstones,
            events: events,
            flyerTours: touren
        )
    }

    private func plakat(
        id: String = "poster-1",
        createdBy: String = "leader-phone",
        adresse: String = "",
        updatedAt: Int64 = 1000
    ) -> Poster {
        Poster(
            id: id,
            teamId: teamId,
            latitude: 51.46,
            longitude: 12.63,
            addressHint: adresse,
            createdByDeviceId: createdBy,
            createdByName: "David",
            createdAt: 500,
            updatedAt: updatedAt
        )
    }

    // MARK: - verify: wer darf überhaupt hereinreden

    func testPasstDasGeheimnisUndIstDerAbsenderFreigegeben() {
        XCTAssertTrue(SyncMerge.verify(snapshot: paket(), local: lokal()))
    }

    func testDasEigeneGeraetDarfImmer() {
        XCTAssertTrue(SyncMerge.verify(snapshot: paket(sender: "member-phone"), local: lokal()))
    }

    func testUnbekannterAbsenderWirdAbgewiesenTrotzRichtigemGeheimnis() {
        // Das Geheimnis allein reicht nicht - sonst genuegte ein einmal abfotografierter QR-Code.
        XCTAssertFalse(SyncMerge.verify(snapshot: paket(sender: "unknown-phone"), local: lokal()))
    }

    func testNichtFreigegebenerAbsenderWirdAbgewiesen() {
        var local = lokal()
        local.devices = [
            DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER),
            DeviceRecord(deviceId: "guest-phone", displayName: "Gast", role: .MEMBER, approved: false)
        ]
        XCTAssertFalse(SyncMerge.verify(snapshot: paket(sender: "guest-phone"), local: local))
    }

    func testFalschesGeheimnisWirdAbgewiesen() {
        XCTAssertFalse(SyncMerge.verify(snapshot: paket(geheimnis: "wrong-secret"), local: lokal()))
    }

    func testGesperrterAbsenderWirdAbgewiesen() {
        var local = lokal()
        local.devices = [
            DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER),
            DeviceRecord(deviceId: "old-phone", displayName: "Ausgeschieden", role: .MEMBER, blocked: true)
        ]
        XCTAssertFalse(SyncMerge.verify(snapshot: paket(sender: "old-phone"), local: local))
    }

    func testMergeWirftBeiFremdemPaket() {
        XCTAssertThrowsError(
            try SyncMerge.merge(local: lokal(), incoming: paket(geheimnis: "wrong-secret"))
        ) { fehler in
            XCTAssertEqual(fehler as? SyncError, .fremdesTeam)
        }
    }

    // MARK: - Plakate

    func testNeuereFassungGewinnt() throws {
        var local = lokal()
        local.posters = [plakat(adresse: "Alt", updatedAt: 1000)]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)],
                posters: [plakat(adresse: "Neu", updatedAt: 2000)]
            )
        )

        XCTAssertEqual(merged.posters.count, 1)
        XCTAssertEqual(merged.posters.first?.addressHint, "Neu")
    }

    func testPlakatVonUnbekanntemGeraetWirdVerworfen() throws {
        // Der Absender ist freigegeben, das erfassende Geraet nicht. Sonst koennte ein
        // freigegebenes Geraet beliebige Fremddaten einschleusen.
        let merged = try SyncMerge.merge(
            local: lokal(),
            incoming: paket(
                devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)],
                posters: [plakat(id: "poster-unknown", createdBy: "unknown-phone", updatedAt: 2000)]
            )
        )

        XCTAssertFalse(merged.posters.contains { $0.id == "poster-unknown" })
    }

    func testBeiGleichemZeitstempelGewinntDasLokaleUndErgaenztLuecken() throws {
        var lokalesPlakat = plakat(adresse: "", updatedAt: 1000)
        lokalesPlakat.officialNote = "lokal"
        var local = lokal()
        local.posters = [lokalesPlakat]

        var eingehend = plakat(adresse: "Vom Kollegen", updatedAt: 1000)
        eingehend.officialNote = "eingehend"
        eingehend.localPhotoFileName = "foto.jpg"
        eingehend.plannedRemovalAt = 9000

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)],
                posters: [eingehend]
            )
        )
        let ergebnis = try XCTUnwrap(merged.posters.first)

        // Gleichstand: das lokale Feld gewinnt, aber leere Felder werden aufgefuellt.
        XCTAssertEqual(ergebnis.officialNote, "lokal")
        XCTAssertEqual(ergebnis.addressHint, "Vom Kollegen")
        XCTAssertEqual(ergebnis.localPhotoFileName, "foto.jpg")
        XCTAssertEqual(ergebnis.plannedRemovalAt, 9000)
    }

    func testAeltereFassungAendertNichts() throws {
        var local = lokal()
        local.posters = [plakat(adresse: "Aktuell", updatedAt: 5000)]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)],
                posters: [plakat(adresse: "Veraltet", updatedAt: 1000)]
            )
        )

        XCTAssertEqual(merged.posters.first?.addressHint, "Aktuell")
    }

    // MARK: - Ereignisse

    func testEreignisVonNichtFreigegebenemGeraetWirdVerworfen() throws {
        var local = lokal()
        local.devices = [
            DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER),
            DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER),
            DeviceRecord(deviceId: "guest-phone", displayName: "Gast", role: .MEMBER, approved: false)
        ]
        let ereignis = PosterEvent(
            posterId: "poster-1", teamId: teamId,
            actorDeviceId: "guest-phone", actorName: "Gast", action: "Fake"
        )

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                devices: [DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)],
                events: [ereignis]
            )
        )

        XCTAssertFalse(merged.events.contains { $0.id == ereignis.id })
    }

    // MARK: - Flyer-Touren

    func testTourenWerdenUeberDieIdZusammengefuehrt() throws {
        let lokaleTour = FlyerTour(
            id: "tour-1", teamId: teamId, name: "Eilenburg Nord", status: .ACTIVE,
            points: [FlyerTrackPoint(latitude: 51.0, longitude: 12.0, createdAt: 1000)],
            createdByDeviceId: "member-phone", createdByName: "Mitglied",
            startedAt: 900, updatedAt: 1500
        )
        var gleicheTour = lokaleTour
        gleicheTour.status = .FINISHED
        gleicheTour.points = [
            FlyerTrackPoint(latitude: 51.0, longitude: 12.0, createdAt: 1000),
            FlyerTrackPoint(latitude: 51.1, longitude: 12.1, createdAt: 2000)
        ]
        gleicheTour.updatedAt = 2500
        gleicheTour.finishedAt = 2600

        let andereTour = FlyerTour(
            id: "tour-2", teamId: teamId, name: "Delitzsch", status: .FINISHED,
            points: [FlyerTrackPoint(latitude: 51.5, longitude: 12.3, createdAt: 3000)],
            createdByDeviceId: "other-phone", createdByName: "Anderes Mitglied",
            startedAt: 2900, updatedAt: 3100, finishedAt: 3200
        )

        var local = lokal()
        local.flyerTours = [lokaleTour]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                devices: [
                    DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER),
                    DeviceRecord(deviceId: "other-phone", displayName: "Anderes Mitglied", role: .MEMBER)
                ],
                touren: [gleicheTour, andereTour]
            )
        )

        XCTAssertEqual(merged.flyerTours.count, 2)
        let zusammengefuehrt = try XCTUnwrap(merged.flyerTours.first { $0.id == "tour-1" })
        XCTAssertEqual(zusammengefuehrt.status, .FINISHED)
        XCTAssertEqual(zusammengefuehrt.points.count, 2, "Doppelte Punkte muessen verschmelzen.")
        XCTAssertEqual(zusammengefuehrt.finishedAt, 2600)
        XCTAssertTrue(merged.flyerTours.contains { $0.id == "tour-2" })
    }

    // MARK: - Wer darf Geräte ändern

    func testMitgliedKannDenTeamleiterNichtEntmachten() throws {
        let leiter = DeviceRecord(
            deviceId: "leader-phone", displayName: "David", role: .LEADER,
            joinedAt: 100, approved: true, blocked: false
        )
        let mitglied = DeviceRecord(
            deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER,
            joinedAt: 100, approved: true, blocked: false
        )
        var local = lokal()
        local.devices = [mitglied, leiter]

        var gefaelschterLeiter = leiter
        gefaelschterLeiter.role = .MEMBER
        gefaelschterLeiter.approved = false
        gefaelschterLeiter.blocked = true
        gefaelschterLeiter.joinedAt = 999

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(
                sender: "member-phone", senderName: "Mitglied",
                devices: [mitglied, gefaelschterLeiter]
            )
        )
        let ergebnis = try XCTUnwrap(merged.devices.first { $0.deviceId == "leader-phone" })

        XCTAssertEqual(ergebnis.role, .LEADER)
        XCTAssertTrue(ergebnis.approved)
        XCTAssertFalse(ergebnis.blocked)
        XCTAssertEqual(ergebnis.joinedAt, 100)
    }

    func testMitgliedKannEinAnderesMitgliedNichtSperren() throws {
        let absender = DeviceRecord(deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER)
        let anderes = DeviceRecord(
            deviceId: "other-phone", displayName: "Anderes Mitglied", role: .MEMBER,
            joinedAt: 200, approved: true, blocked: false
        )
        var local = lokal()
        local.devices = [
            absender, anderes,
            DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)
        ]

        var gesperrt = anderes
        gesperrt.approved = false
        gesperrt.blocked = true
        gesperrt.joinedAt = 999

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(sender: "member-phone", senderName: "Mitglied", devices: [absender, gesperrt])
        )
        let ergebnis = try XCTUnwrap(merged.devices.first { $0.deviceId == "other-phone" })

        XCTAssertEqual(ergebnis.role, .MEMBER)
        XCTAssertTrue(ergebnis.approved)
        XCTAssertFalse(ergebnis.blocked)
        XCTAssertEqual(ergebnis.joinedAt, 200)
    }

    func testDerTeamleiterDarfSperren() throws {
        let beobachter = DeviceRecord(deviceId: "observer-phone", displayName: "Beobachter", role: .MEMBER)
        let mitglied = DeviceRecord(
            deviceId: "member-phone", displayName: "Mitglied", role: .MEMBER,
            joinedAt: 100, approved: true, blocked: false
        )
        let leiter = DeviceRecord(deviceId: "leader-phone", displayName: "David", role: .LEADER)

        var local = lokal(deviceId: "observer-phone")
        local.deviceName = "Beobachter"
        local.devices = [beobachter, mitglied, leiter]

        var gesperrt = mitglied
        gesperrt.joinedAt = 999
        gesperrt.approved = false
        gesperrt.blocked = true

        let merged = try SyncMerge.merge(local: local, incoming: paket(devices: [leiter, gesperrt]))
        let ergebnis = try XCTUnwrap(merged.devices.first { $0.deviceId == "member-phone" })

        XCTAssertFalse(ergebnis.approved)
        XCTAssertTrue(ergebnis.blocked)
        XCTAssertEqual(ergebnis.joinedAt, 999)
    }

    // MARK: - Löschmarker

    func testLokalGeloeschtesBleibtGeloescht() throws {
        // Der Teamkollege hat das Plakat noch und schickt es mit. Ohne Loeschmarker kaeme es
        // bei jedem Abgleich zurueck.
        var local = lokal()
        local.posters = []
        local.deletedPosters = [
            PosterTombstone(
                posterId: "poster-1", teamId: teamId,
                deletedByDeviceId: "member-phone", deletedByName: "Mitglied"
            )
        ]

        let merged = try SyncMerge.merge(local: local, incoming: paket(posters: [plakat(id: "poster-1")]))

        XCTAssertFalse(merged.posters.contains { $0.id == "poster-1" })
        XCTAssertEqual(merged.deletedPosters.count, 1)
    }

    func testEingehenderMarkerEntferntDasLokalePlakat() throws {
        var local = lokal()
        local.posters = [plakat(id: "poster-2")]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(tombstones: [
                PosterTombstone(
                    posterId: "poster-2", teamId: teamId,
                    deletedByDeviceId: "leader-phone", deletedByName: "David"
                )
            ])
        )

        XCTAssertFalse(merged.posters.contains { $0.id == "poster-2" })
        XCTAssertTrue(merged.deletedPosters.contains { $0.posterId == "poster-2" })
    }

    func testMarkerSchlaegtNeuereAenderung() throws {
        // Die eingehende Fassung wurde NACH dem Loeschen noch einmal aktualisiert. Der Marker
        // gewinnt trotzdem, sonst braechte jedes Geraet, das die Loeschung noch nicht kennt,
        // das Plakat zurueck.
        var local = lokal()
        local.deletedPosters = [
            PosterTombstone(
                posterId: "poster-3", teamId: teamId,
                deletedByDeviceId: "member-phone", deletedByName: "Mitglied", deletedAt: 2000
            )
        ]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(posters: [plakat(id: "poster-3", updatedAt: 3000)])
        )

        XCTAssertFalse(merged.posters.contains { $0.id == "poster-3" })
    }

    func testMarkerEinesGesperrtenGeraetsWirdVerworfen() throws {
        var local = lokal()
        local.posters = [plakat(id: "poster-4")]
        local.devices.append(
            DeviceRecord(
                deviceId: "blocked-phone", displayName: "Gesperrt", role: .MEMBER,
                approved: false, blocked: true
            )
        )

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(tombstones: [
                PosterTombstone(
                    posterId: "poster-4", teamId: teamId,
                    deletedByDeviceId: "blocked-phone", deletedByName: "Gesperrt"
                )
            ])
        )

        XCTAssertTrue(merged.posters.contains { $0.id == "poster-4" })
        XCTAssertFalse(merged.deletedPosters.contains { $0.posterId == "poster-4" })
    }

    func testDerFruehereLoeschzeitpunktGewinnt() throws {
        var local = lokal()
        local.deletedPosters = [
            PosterTombstone(
                posterId: "poster-5", teamId: teamId,
                deletedByDeviceId: "member-phone", deletedByName: "Mitglied", deletedAt: 5000
            )
        ]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(tombstones: [
                PosterTombstone(
                    posterId: "poster-5", teamId: teamId,
                    deletedByDeviceId: "leader-phone", deletedByName: "David", deletedAt: 3000
                )
            ])
        )

        XCTAssertEqual(merged.deletedPosters.count, 1)
        XCTAssertEqual(merged.deletedPosters.first?.deletedAt, 3000)
    }

    func testMarkerBeiderSeitenBleibenErhalten() throws {
        var local = lokal()
        local.deletedPosters = [
            PosterTombstone(
                posterId: "poster-a", teamId: teamId,
                deletedByDeviceId: "member-phone", deletedByName: "Mitglied"
            )
        ]

        let merged = try SyncMerge.merge(
            local: local,
            incoming: paket(tombstones: [
                PosterTombstone(
                    posterId: "poster-b", teamId: teamId,
                    deletedByDeviceId: "leader-phone", deletedByName: "David"
                )
            ])
        )

        XCTAssertEqual(Set(merged.deletedPosters.map(\.posterId)), ["poster-a", "poster-b"])
    }
}
