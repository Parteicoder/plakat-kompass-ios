import XCTest

@testable import PlakatKompassCore

final class FlyerTourFilterTests: XCTestCase {

    func testAusreisserUeber25MeterWirdVerworfen() {
        XCTAssertFalse(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 40, abstandZumVorgaengerMeter: nil
        ))
    }

    func testPunktMit25MeterGenauigkeitDarfRein() {
        XCTAssertTrue(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 25, abstandZumVorgaengerMeter: nil
        ))
    }

    func testUngueltigeGenauigkeitWirdVerworfen() {
        XCTAssertFalse(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 0, abstandZumVorgaengerMeter: nil
        ))
        XCTAssertFalse(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: -1, abstandZumVorgaengerMeter: nil
        ))
    }

    func testAbstandSkaliertMitGenauigkeit() {
        // 10 m Ungenauigkeit → max(20, 15) = 20. 12 m Abstand ist zu nah.
        XCTAssertFalse(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 10, abstandZumVorgaengerMeter: 12
        ))
        XCTAssertTrue(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 10, abstandZumVorgaengerMeter: 25
        ))
        // 20 m Ungenauigkeit → max(20, 30) = 30.
        XCTAssertFalse(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 20, abstandZumVorgaengerMeter: 25
        ))
        XCTAssertTrue(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 20, abstandZumVorgaengerMeter: 30
        ))
    }

    func testErsterPunktBrauchtKeinenVorgaenger() {
        XCTAssertTrue(FlyerTourFilter.sollAufnehmen(
            genauigkeitMeter: 10, abstandZumVorgaengerMeter: nil
        ))
    }
}
