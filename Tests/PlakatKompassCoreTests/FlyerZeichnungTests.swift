import XCTest
@testable import PlakatKompassCore

final class FlyerZeichnungTests: XCTestCase {
    func testStartpunktErscheintAbDemErstenFix() {
        // Der Kern der Regel: Bei EINEM Wegpunkt muss etwas auf der Karte erscheinen. Auf Android
        // war es nichts, und eine gerade gestartete Tour sah kaputt aus, bis nach zwanzig bis
        // vierzig Metern Fussweg der zweite Punkt kam.
        XCTAssertEqual(FlyerZeichnung.formenAnzahl(punkte: 0), 0)
        XCTAssertEqual(FlyerZeichnung.formenAnzahl(punkte: 1), 1)
        XCTAssertEqual(FlyerZeichnung.formenAnzahl(punkte: 2), 2)
        XCTAssertEqual(FlyerZeichnung.formenAnzahl(punkte: 500), 2)
    }

    func testBalkenBleibtDurchscheinend() {
        // Deckt die Deckkraft die Strasse zu, ist der Weg zwar sichtbar, aber man erkennt nicht
        // mehr, WO er langfuehrt - und genau dafuer schaut man auf die Karte.
        XCTAssertGreaterThan(FlyerZeichnung.deckkraft, 0.5)
        XCTAssertLessThan(FlyerZeichnung.deckkraft, 1.0)
    }
}
