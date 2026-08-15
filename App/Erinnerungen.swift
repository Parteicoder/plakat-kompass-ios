import PlakatKompassCore
import UserNotifications

/// Erinnerung an fällige Plakat-Abnahmen.
///
/// **Bewusst anders gelöst als auf Android.** Dort läuft alle sechs Stunden ein `WorkManager`,
/// zählt die fälligen Plakate und schickt gegebenenfalls eine Meldung. So etwas gibt es auf iOS
/// nicht: Hintergrundausführung ist hier weder regelmäßig noch zugesichert — das System entscheidet
/// nach Ladezustand und Nutzungsgewohnheit, ob eine App überhaupt aufwacht. Wer den Android-Weg
/// nachbaut, bekommt eine Erinnerung, die manchmal kommt. Das ist schlechter als keine, weil sich
/// niemand darauf einstellen kann.
///
/// Stattdessen wird die Meldung **beim Erfassen** eingeplant, auf den Tag der Frist um 9 Uhr. iOS
/// stellt sie dann zu, auch wenn die App seit Wochen nicht offen war. Ändert sich die Frist oder
/// verschwindet das Plakat, wird die Meldung neu gesetzt oder gestrichen.
enum Erinnerungen {

    /// Kennung je Plakat, damit sich eine Meldung gezielt ersetzen und löschen lässt.
    private static func kennung(_ posterId: String) -> String { "abnahme-\(posterId)" }

    /// Fragt einmalig nach Erlaubnis. Ohne sie passiert der Rest still gar nichts — das ist in
    /// Ordnung, die App funktioniert auch ohne Erinnerungen vollständig.
    static func frageErlaubnis() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Setzt die Meldungen für den ganzen Stand neu.
    ///
    /// Erst alles wegräumen, dann neu planen: Das ist kürzer als jede Einzelfallunterscheidung
    /// und kann nicht in einen Zustand geraten, in dem eine Meldung für ein längst gelöschtes
    /// Plakat übrig bleibt.
    /// Der Schlüssel des Schalters „Abnahme-Erinnerungen" in den Einstellungen — dieselbe
    /// `@AppStorage`, hier direkt gelesen, weil diese Funktion nicht selbst eine View ist.
    private static let abschaltSchluessel = "abnahmeErinnerung"

    static func planeNeu(fuer state: LocalTeamState) async {
        let zentrale = UNUserNotificationCenter.current()
        let erlaubt = await zentrale.notificationSettings().authorizationStatus
        guard erlaubt == .authorized || erlaubt == .provisional else { return }

        let alte = await zentrale.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("abnahme-") }
        zentrale.removePendingNotificationRequests(withIdentifiers: alte)

        // Ausgeschaltet: Alte Meldungen sind eben weggeräumt, neue kommen keine dazu.
        guard UserDefaults.standard.object(forKey: abschaltSchluessel) as? Bool ?? true else { return }

        for plakat in state.posters {
            guard let frist = plakat.plannedRemovalAt,
                  plakat.status != .REMOVED,
                  let ausloeser = ausloeser(frist: frist)
            else { continue }

            let inhalt = UNMutableNotificationContent()
            inhalt.title = plakat.addressHint.isEmpty
                ? "Plakat abnehmen"
                : "Plakat abnehmen: \(plakat.addressHint)"
            inhalt.body = "Die Abnahmefrist ist heute erreicht."
            inhalt.sound = .default

            try? await zentrale.add(
                UNNotificationRequest(
                    identifier: kennung(plakat.id), content: inhalt, trigger: ausloeser
                )
            )
        }
    }

    // MARK: - Pausen

    /// Kennung der Pausen-Erinnerung. Nur eine gleichzeitig.
    private static let pausenKennung = "pause"

    /// Voreinstellung und Grenzen wie auf Android.
    static let pausenVorgabeMinuten = 60
    static let pausenSpanne = 15...240

    /// Erinnert nach der eingestellten Zeit ans Essen und Trinken.
    ///
    /// Wer im Sommer vier Stunden mit Leiter und Kabelbindern unterwegs ist, vergisst beides.
    /// Anders als die Abnahmefrist hat diese Meldung keinen festen Termin — sie hängt daran,
    /// wann jemand losgezogen ist. Deshalb ein Zeitgeber, kein Kalendereintrag.
    static func startePause(minuten: Int) async {
        let zentrale = UNUserNotificationCenter.current()
        let erlaubt = await zentrale.notificationSettings().authorizationStatus
        guard erlaubt == .authorized || erlaubt == .provisional else { return }

        beendePause()

        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Plakat Kompass"
        inhalt.body = "Kurze Pause? Trink etwas und iss eine Kleinigkeit."
        inhalt.sound = .default

        let sekunden = Double(min(max(minuten, pausenSpanne.lowerBound), pausenSpanne.upperBound) * 60)
        try? await zentrale.add(
            UNNotificationRequest(
                identifier: pausenKennung,
                content: inhalt,
                // Wiederholend: Wer einmal erinnert werden will, will es auch beim zweiten Mal.
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: sekunden, repeats: true)
            )
        )
    }

    static func beendePause() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [pausenKennung])
    }

    /// 9 Uhr am Tag der Frist. Liegt der Zeitpunkt schon hinter uns, wird nichts geplant —
    /// eine Meldung für gestern hilft niemandem, und die Liste zeigt überfällige Plakate ohnehin.
    private static func ausloeser(frist: Int64) -> UNCalendarNotificationTrigger? {
        let kalender = Calendar.current
        let tag = Date(timeIntervalSince1970: Double(frist) / 1000)
        var teile = kalender.dateComponents([.year, .month, .day], from: tag)
        teile.hour = 9

        guard let zeitpunkt = kalender.date(from: teile), zeitpunkt > Date() else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: teile, repeats: false)
    }
}
