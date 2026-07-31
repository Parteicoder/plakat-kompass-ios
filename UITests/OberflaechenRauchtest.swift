import XCTest

/// Die nächste Stufe nach dem Start-Rauchtest: **zeichnet sich jeder Bereich überhaupt?**
///
/// Der Schritt „App im Simulator starten" beweist, dass die App nicht beim Start aussteigt. Er
/// beweist nichts über die vier Bereiche, die man dabei gar nicht zu sehen bekommt. Ein Absturz
/// beim Wechsel auf die Karte, eine SwiftUI-Aktualisierungsschleife in der Liste, ein
/// `@EnvironmentObject`, das nur einem Bildschirm fehlt — das alles überlebt einen reinen
/// Startversuch und fällt erst auf, wenn jemand unten auf ein Symbol tippt.
///
/// Geprüft wird deshalb je Bereich, dass sein **Titel in der Navigationsleiste** erscheint. Das
/// ist absichtlich nicht viel: Der Titel steht erst da, wenn SwiftUI die Ansicht wirklich gebaut
/// hat. Es ist die kleinste Aussage, die einen leeren oder abgestürzten Bildschirm ausschliesst —
/// und sie kostet keinen Aufbau von Testdaten.
final class OberflaechenRauchtest: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func starte() -> XCUIApplication {
        let app = XCUIApplication()
        // Die Kurzanleitung legt sich beim ersten Start als Schicht über den Bildschirm und
        // fängt jeden Tipp ab. Für den Test gilt sie als gesehen — über die Voreinstellungen,
        // nicht über einen Sonderweg im Programm: `-schluessel wert` in den Startargumenten
        // setzt genau den UserDefaults-Eintrag, an dem auch @AppStorage hängt.
        app.launchArguments += ["-kurzanleitungGesehen", "start,erfassen,liste,karte,abgleich"]
        app.launch()
        return app
    }

    /// Wegklicken, was das System über die App legt — Ort, Meldungen, lokales Netzwerk.
    ///
    /// **Hier stand einmal `app.tap()`**, das übliche Rezept, um einen `UIInterruptionMonitor`
    /// auslösen zu lassen. Es hat den Test zu Fall gebracht, und zwar auf die lehrreiche Art:
    /// `app.tap()` tippt blind in die Bildschirmmitte, und auf „Erfassen" sitzt dort der
    /// Kameraknopf. Der öffnete die Kamera, die verdeckte die Reiterleiste, und der nächste
    /// Reiter war nicht mehr erreichbar — Fehlermeldung „Computed hit point {-1, -1}".
    ///
    /// Ein Werkzeug, das irgendwohin tippt, hat in einem Test nichts zu suchen. Jetzt wird die
    /// Systemoberfläche direkt angesprochen: Dort und nur dort stehen die Knöpfe der Nachfragen.
    private func schliesseSystemfragen() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let beschriftungen = [
            "Beim Verwenden der App erlauben", "Allow While Using App",
            "Erlauben", "Allow", "OK", "Zulassen"
        ]
        // Mehrere Nachfragen koennen nacheinander kommen (Ort, dann Meldungen).
        for _ in 0..<3 {
            guard let knopf = beschriftungen.map({ system.buttons[$0] }).first(where: { $0.exists })
            else { return }
            knopf.tap()
        }
    }

    /// Alle fünf Bereiche einmal öffnen und je einen Beleg verlangen, dass sie da sind.
    func testJederBereichZeichnetSich() {
        let app = starte()

        let bereiche = [
            (reiter: "Start", titel: "Plakat Kompass"),
            (reiter: "Erfassen", titel: "Erfassen"),
            (reiter: "Liste", titel: "Plakate"),
            (reiter: "Karte", titel: "Karte"),
            (reiter: "Abgleich", titel: "Abgleich")
        ]

        for bereich in bereiche {
            schliesseSystemfragen()

            let knopf = app.tabBars.buttons[bereich.reiter]
            XCTAssertTrue(
                knopf.waitForExistence(timeout: 20),
                "Der Reiter „\(bereich.reiter)“ ist nicht da — die Reiterleiste fehlt oder heisst anders."
            )
            // Erreichbar, nicht nur vorhanden: Liegt etwas darueber, ist "exists" wahr und der
            // Tipp scheitert trotzdem. Genau daran ist der erste Anlauf gescheitert.
            XCTAssertTrue(
                warteAufErreichbarkeit(knopf),
                "Der Reiter „\(bereich.reiter)“ ist verdeckt — etwas liegt über der Reiterleiste."
            )
            knopf.tap()

            XCTAssertTrue(
                app.navigationBars[bereich.titel].waitForExistence(timeout: 20),
                "„\(bereich.reiter)“ hat sich nicht gezeichnet: Titel „\(bereich.titel)“ fehlt."
            )
            XCTAssertEqual(app.state, .runningForeground, "Die App ist bei „\(bereich.reiter)“ ausgestiegen.")
        }
    }

    /// Der Weg, den ein neuer Nutzer als Erstes geht — und der einzige, der ohne Team möglich ist.
    ///
    /// Er führt über ein Blatt, und ein Blatt ist die Stelle, an der SwiftUI-Ansichten gern an
    /// einem fehlenden `@EnvironmentObject` scheitern: Ein Blatt bekommt die Umgebung nicht
    /// automatisch mit, wenn es an der falschen Stelle hängt.
    func testDerEinstiegLaesstSichOeffnen() {
        let app = starte()
        schliesseSystemfragen()

        let abgleich = app.tabBars.buttons["Abgleich"]
        XCTAssertTrue(abgleich.waitForExistence(timeout: 20))
        XCTAssertTrue(warteAufErreichbarkeit(abgleich))
        abgleich.tap()

        // „Loslegen“ steht dort, solange kein Team eingerichtet ist — auf einem frisch
        // installierten Simulator ist das immer der Fall.
        let loslegen = app.buttons["Loslegen"]
        guard loslegen.waitForExistence(timeout: 20) else {
            // Kein Fehler: Bleibt ein Zustand aus einem frueheren Lauf stehen, ist die App
            // eingerichtet und dieser Knopf fehlt zu Recht. Den Test daran scheitern zu lassen
            // hiesse, eine Umgebung zu pruefen statt den Code.
            XCTAssertEqual(app.state, .runningForeground)
            return
        }
        loslegen.tap()

        XCTAssertTrue(
            app.navigationBars["Team"].waitForExistence(timeout: 20),
            "Das Einstiegsblatt hat sich nicht geöffnet."
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// `waitForExistence` gibt es fertig, `waitForHittable` nicht — deshalb hier von Hand.
    private func warteAufErreichbarkeit(_ element: XCUIElement, sekunden: Int = 15) -> Bool {
        for _ in 0..<sekunden {
            if element.isHittable { return true }
            schliesseSystemfragen()
            Thread.sleep(forTimeInterval: 1)
        }
        return element.isHittable
    }
}
