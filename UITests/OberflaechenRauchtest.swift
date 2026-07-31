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

    /// Alle fünf Bereiche einmal öffnen und je einen Beleg verlangen, dass sie da sind.
    func testJederBereichZeichnetSich() {
        let app = starte()

        // Systemnachfragen nach Ort und Meldungen legen sich sonst über die App und
        // verschlucken den naechsten Tipp.
        //
        // ponytail: Unterbrechungswaechter statt fester Wartezeiten. Reicht fuer fuenf
        // Reiterwechsel; wer hier spaeter echte Ablaeufe testet, braucht mehr.
        addUIInterruptionMonitor(withDescription: "Systemnachfrage") { meldung in
            for beschriftung in ["Erlauben", "Allow", "Beim Verwenden der App erlauben", "OK"] {
                let knopf = meldung.buttons[beschriftung]
                if knopf.exists { knopf.tap(); return true }
            }
            return false
        }

        let bereiche = [
            (reiter: "Start", titel: "Plakat Kompass"),
            (reiter: "Erfassen", titel: "Erfassen"),
            (reiter: "Liste", titel: "Plakate"),
            (reiter: "Karte", titel: "Karte"),
            (reiter: "Abgleich", titel: "Abgleich")
        ]

        for bereich in bereiche {
            let knopf = app.tabBars.buttons[bereich.reiter]
            XCTAssertTrue(
                knopf.waitForExistence(timeout: 20),
                "Der Reiter „\(bereich.reiter)“ ist nicht da — die Reiterleiste fehlt oder heisst anders."
            )
            knopf.tap()
            // Ein Tipp auf die App selbst laesst den Waechter greifen, falls gerade eine
            // Systemnachfrage offen steht.
            app.tap()

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

        let abgleich = app.tabBars.buttons["Abgleich"]
        XCTAssertTrue(abgleich.waitForExistence(timeout: 20))
        abgleich.tap()
        app.tap()

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
}
