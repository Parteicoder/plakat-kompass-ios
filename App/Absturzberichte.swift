import Foundation
import MetricKit

/// Abstürze des **vorigen** Laufs ins Protokoll holen — über Apples eigene Schnittstelle.
///
/// ## Warum das hier steht, obwohl daneben das Gegenteil behauptet wurde
///
/// In [Protokoll] steht, iOS könne Swift-Laufzeitfehler nicht abfangen. Für **Signal-Handler**
/// stimmt das weiterhin: Ein `SIGTRAP`-Handler darf weder Swift noch Objective-C noch `malloc`
/// benutzen, Apple rät ausdrücklich davon ab, einen eigenen Absturzmelder zu bauen, und selbst
/// ausgereifte Fremdpakete haben dort Fehler, bei denen der Handler in `malloc` zurückspringt
/// und damit **den echten Absturz verdeckt**.
///
/// Der Schluss „also geht es gar nicht" war trotzdem falsch. **MetricKit kann es**, und zwar
/// ohne einen einzigen Signal-Handler: Das System schreibt den Absturzbericht selbst weg und
/// übergibt ihn der App beim nächsten Start — seit iOS 15 sofort, nicht erst nach einem Tag.
/// [MXCrashDiagnostic] enthält Ausnahmetyp, Signal, Abbruchgrund und die Aufrufliste, und es
/// deckt Swift-Laufzeitfehler mit ab.
///
/// ## Was das nicht kann
///
/// **Im Simulator kommt nichts an.** MetricKit liefert nur auf echten Geräten, in der Praxis
/// erst bei einem über TestFlight oder den App Store installierten Programm. Der CI kann diesen
/// Weg deshalb nicht prüfen — hier steht bewusst kein Test, der etwas anderes behauptet.
///
/// Und es ist kein Ersatz für die Marke in [Protokoll]: Die merkt sofort, dass der vorige Lauf
/// nicht geordnet endete, auch ohne Gerät und ohne TestFlight. MetricKit sagt dafür, **warum**.
/// Beide zusammen ergeben das Bild.
@MainActor
final class Absturzberichte: NSObject, MXMetricManagerSubscriber {

    static let geteilt = Absturzberichte()

    /// Eine lange Aufrufliste macht das Protokoll unlesbar. Für die Frage „woran ist es
    /// gestorben" reichen die obersten Rahmen.
    private static let maxZeichenAufrufliste = 1200

    private var angemeldet = false

    /// Beim Start aufrufen. Mehrfaches Anmelden wäre ein Fehler — MetricKit hielte den
    /// Empfänger dann mehrfach und lieferte jeden Bericht doppelt.
    func melde_an() {
        guard !angemeldet else { return }
        angemeldet = true
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// Pflichtmethode des Protokolls. Die Leistungsdaten interessieren hier nicht — es geht
    /// allein um Abstürze.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // MetricKit ruft nicht garantiert auf dem Hauptfaden zurueck, das Protokoll lebt aber
        // dort. Deshalb sammeln und einmal hinueberreichen, statt pro Zeile zu springen.
        let zeilen = payloads.flatMap { $0.crashDiagnostics ?? [] }.map(Self.alsZeile)
        guard !zeilen.isEmpty else { return }
        Task { @MainActor in
            Protokoll.geteilt.schreibe("Absturzbericht vom System (\(zeilen.count)):")
            zeilen.forEach { Protokoll.geteilt.schreibe($0) }
        }
    }

    /// Aus einem Bericht eine Zeile machen, die jemand im Fehlerbericht lesen kann.
    ///
    /// `terminationReason` ist die Zeile, die bei einem Swift-Laufzeitfehler den eigentlichen
    /// Text enthält — bei `fatalError("…")` steht die Meldung darin. Deshalb steht sie vorn.
    nonisolated private static func alsZeile(_ bericht: MXCrashDiagnostic) -> String {
        var teile: [String] = []
        if let grund = bericht.terminationReason, !grund.isEmpty { teile.append(grund) }
        if let typ = bericht.exceptionType { teile.append("Ausnahme \(typ)") }
        if let signal = bericht.signal { teile.append("Signal \(signal)") }
        if let code = bericht.exceptionCode { teile.append("Code \(code)") }

        let kopf = teile.isEmpty ? "Absturz ohne nähere Angabe" : teile.joined(separator: ", ")
        let liste = String(
            decoding: bericht.callStackTree.jsonRepresentation(), as: UTF8.self
        ).prefix(maxZeichenAufrufliste)
        return "\(kopf)\n\(liste)"
    }
}
