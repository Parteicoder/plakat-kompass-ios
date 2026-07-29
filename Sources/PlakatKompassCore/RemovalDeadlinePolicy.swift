import Foundation

/// Abnahmefristen. Gegenstück zu `core/RemovalDeadlinePolicy.kt`.
///
/// Ein Plakat wird von selbst zum Problem, sobald die geplante Abnahme erreicht ist und es noch
/// nicht als entfernt gilt. Das ist keine Kosmetik: Wahlplakate müssen innerhalb einer Frist
/// abgenommen werden, sonst wird es für die Partei teuer. Wer sich darauf verlässt, dass jemand
/// von Hand nachhält, hat am Ende zwanzig übersehene Plakate in drei Gemeinden.
///
/// Die Regeln stehen hier und nicht in der Oberfläche, weil vier Stellen davon abhängen: der
/// Status, die Liste, die Zahlen auf der Startseite und die Erinnerung.
public enum RemovalDeadlinePolicy {

    /// Überfällige Plakate gelten als beschädigt.
    ///
    /// Nicht schön, aber richtig: Es gibt keinen eigenen Status „überfällig", und `DAMAGED` ist
    /// der einzige, den die Oberfläche schon überall als Problem anzeigt. Ein neuer Status müsste
    /// zeitgleich auf Android eingeführt werden, sonst versteht die andere Seite ihn nicht.
    static let problemStatus: PosterStatus = .DAMAGED

    public static func applyToState(_ state: LocalTeamState, now: Int64 = Date.nowMillis) -> LocalTeamState {
        var geaendert = false
        let neue = state.posters.map { plakat -> Poster in
            let aktualisiert = applyToPoster(plakat, now: now)
            if aktualisiert != plakat { geaendert = true }
            return aktualisiert
        }
        guard geaendert else { return state }
        var neuerStand = state
        neuerStand.posters = neue
        return neuerStand
    }

    public static func applyToPoster(_ plakat: Poster, now: Int64 = Date.nowMillis) -> Poster {
        guard let frist = plakat.plannedRemovalAt else { return plakat }
        guard plakat.status != .REMOVED, plakat.status != problemStatus else { return plakat }
        guard frist <= now else { return plakat }

        var geaendert = plakat
        geaendert.status = problemStatus
        geaendert.updatedAt = now
        return geaendert
    }

    /// Wie viele Plakate fällig oder überfällig sind. Die Zahl steht auf der Startseite.
    public static func countDueOrOverdue(_ posters: [Poster], now: Int64 = Date.nowMillis) -> Int {
        posters.filter { plakat in
            guard let frist = plakat.plannedRemovalAt else { return false }
            return frist <= now && plakat.status != .REMOVED
        }.count
    }

    /// „Noch 3 Tage", „Heute abnehmen", „Überfällig seit 2 Tagen".
    ///
    /// Gerechnet wird in **Kalendertagen**, nicht in 24-Stunden-Schritten. Wer abends um 22 Uhr
    /// eine Frist auf morgen früh 8 Uhr setzt, soll „Morgen abnehmen" lesen und nicht „Heute" —
    /// dazwischen liegen zwar nur zehn Stunden, aber eben eine Nacht.
    public static func removalCountdownText(
        _ plannedRemovalAt: Int64?,
        now: Int64 = Date.nowMillis,
        kalender: Calendar = .current
    ) -> String? {
        guard let plannedRemovalAt else { return nil }

        let heute = kalender.startOfDay(for: Date(timeIntervalSince1970: Double(now) / 1000))
        let ziel = kalender.startOfDay(for: Date(timeIntervalSince1970: Double(plannedRemovalAt) / 1000))
        let tage = kalender.dateComponents([.day], from: heute, to: ziel).day ?? 0

        switch tage {
        case 1...: return tage > 1 ? "Noch \(tage) Tage" : "Morgen abnehmen"
        case 0: return "Heute abnehmen"
        case -1: return "Überfällig seit 1 Tag"
        default: return "Überfällig seit \(-tage) Tagen"
        }
    }

    /// Höchstzahl aufbewahrter Ereignisse. Gegenstück zu `core/EventHistoryPolicy.kt`.
    ///
    /// Jede Aktion legt einen Eintrag an, und entfernt wurde nie etwas. Weil der **komplette**
    /// Stand bei jeder Änderung als JSON geschrieben wird, wurde jedes Speichern über eine
    /// Kampagne hinweg langsamer — das war auf Android die Ursache dafür, dass sich die App „mit
    /// der Zeit" träge anfühlte.
    ///
    /// Der Deckel verliert keine fachliche Information: Löschungen hängen an den Grabsteinen,
    /// nicht an dieser Liste. Und weil die Auswahl deterministisch ist (neueste zuerst), landen
    /// alle Teamgeräte nach einem Abgleich auf derselben Auswahl, statt sich gegenseitig
    /// aufzuschaukeln.
    public static let maxEvents = 1_000

    public static func withCappedEvents(_ state: LocalTeamState) -> LocalTeamState {
        guard state.events.count > maxEvents else { return state }
        var neu = state
        neu.events = Array(state.events.sorted { $0.createdAt > $1.createdAt }.prefix(maxEvents))
        return neu
    }

    /// Der Text der Erinnerung. Wortgleich mit Android, damit ein Team mit beiden Plattformen
    /// nicht zwei verschiedene Meldungen bespricht.
    public static func reminderText(dueCount: Int) -> (titel: String, text: String)? {
        guard dueCount > 0 else { return nil }
        return (
            titel: dueCount == 1
                ? "1 Plakat muss abgenommen werden"
                : "\(dueCount) Plakate müssen abgenommen werden",
            text: "Abnahmefrist erreicht. Die betroffenen Plakate wurden auf Problem gesetzt."
        )
    }
}
