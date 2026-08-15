import Foundation
import UIKit

/// Ein Protokoll, das den Neustart überlebt — Gegenstück zu `util/AppLogStore.kt` und
/// `util/CrashLogStore.kt`.
///
/// **Wofür es da ist:** Wenn jemand im Feld schreibt „der Abgleich geht nicht", ist die einzige
/// brauchbare Rückfrage „was steht im Protokoll?". Die Protokolle im Experten-Bildschirm gab es
/// schon, aber sie lebten nur, solange die App lief. Wer die App nach dem Fehlschlag schloss —
/// und das tut man — hatte nichts mehr zu berichten.
///
/// ## Was auf iOS **nicht** geht, und das gehört gesagt
///
/// Android fängt mit `Thread.setDefaultUncaughtExceptionHandler` **jeden** Absturz ab und
/// schreibt ihn weg. Auf iOS gibt es dafür kein Gegenstück:
///
/// - [NSSetUncaughtExceptionHandler] fängt nur **Objective-C-Ausnahmen**. Die kommen aus UIKit
///   und Foundation durchaus vor, sind aber nicht der häufigste Fall.
/// - Swift-Laufzeitfehler — `fatalError`, ein Index über das Ende hinaus, ein `nil` beim
///   Auspacken — lösen **keine** Ausnahme aus, sondern ein `SIGTRAP`. Daran kommt kein
///   Handler heran, den man gefahrlos schreiben könnte.
///
/// Statt zu behaupten, wir fingen Abstürze, macht diese Klasse zwei Dinge, die **stimmen**:
/// Sie schreibt Objective-C-Ausnahmen mit, und sie merkt sich beim Start eine Marke, die beim
/// geordneten Beenden wieder verschwindet. Ist sie beim nächsten Start noch da, ist der vorige
/// Lauf **nicht geordnet zu Ende gegangen** — was der Grund war, weiss sie nicht, und behauptet
/// es auch nicht.
///
/// ## Den Grund liefert MetricKit
///
/// Der Absatz oben stand hier zuerst als „geht also gar nicht". Das war ein Fehlschluss: Für
/// selbstgebaute Signal-Handler stimmt er, aber [Absturzberichte] holt sich über Apples eigene
/// Schnittstelle den Bericht, den **das System** zum Absturz geschrieben hat — mitsamt Grund
/// und Aufrufliste, Swift-Laufzeitfehler eingeschlossen.
///
/// Beide Wege bleiben nebeneinander, weil sie sich ergänzen: Die Marke merkt sofort **dass**
/// etwas war, auch im Simulator und ohne TestFlight. MetricKit sagt **warum**, aber nur auf
/// einem echten Gerät.
@MainActor
final class Protokoll: ObservableObject {

    static let geteilt = Protokoll()

    /// Mehr als das behält niemand im Kopf, und mehr braucht auch kein Fehlerbericht.
    private static let maxZeilen = 400
    private static let schreibVerzoegerungSekunden: UInt64 = 2

    @Published private(set) var zeilen: [String] = []

    /// Gegenstück zu `AppLogStore.isEnabled` auf Android. Dort abschaltbar, hier bisher nicht —
    /// obwohl die Marke fürs Absturzerkennen (`beimStart`/`gehtInDenHintergrund`) unabhängig
    /// davon weiterläuft: Wer das Protokoll abschaltet, will keine Mitschrift, nicht dass die
    /// App plötzlich jeden Absturz für einen geordneten Lauf hält.
    private static let aktivSchluessel = "protokollAktiv"
    private var aktiv: Bool { UserDefaults.standard.object(forKey: Self.aktivSchluessel) as? Bool ?? true }

    private let datei: URL
    private let markeDatei: URL
    private var schreiber: Task<Void, Never>?

    /// Wird beim Start gesetzt, wenn der vorige Lauf nicht geordnet endete.
    private(set) var vorigerLaufBrachAb = false

    init(ordner: URL? = nil) {
        let basis = ordner ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        datei = basis.appendingPathComponent("protokoll.log")
        markeDatei = basis.appendingPathComponent("laeuft.marke")
        lade()
    }

    // MARK: - Schreiben

    func schreibe(_ text: String) {
        guard aktiv else { return }
        let zeit = Self.zeitformat.string(from: Date())
        zeilen.append("\(zeit)  \(text)")
        if zeilen.count > Self.maxZeilen { zeilen.removeFirst(zeilen.count - Self.maxZeilen) }
        planeSchreiben()
    }

    func leeren() {
        zeilen.removeAll()
        schreiber?.cancel()
        schreiber = nil
        try? FileManager.default.removeItem(at: datei)
    }

    /// Für den Teilen-Dialog. Neueste Zeile unten, wie in einer Logdatei üblich — anders als
    /// in der Anzeige, wo man das Neueste zuerst sehen will.
    func alsText() -> String {
        zeilen.joined(separator: "\n")
    }

    // MARK: - Start und Ende

    /// Beim App-Start aufrufen. Legt die Marke an und meldet, wenn die vorige noch lag.
    func beimStart() {
        vorigerLaufBrachAb = FileManager.default.fileExists(atPath: markeDatei.path)
        if vorigerLaufBrachAb {
            schreibe("Der vorige Lauf ist nicht geordnet zu Ende gegangen.")
        }
        try? Data().write(to: markeDatei)

        NSSetUncaughtExceptionHandler { ausnahme in
            // Hier laeuft die App bereits im Sterben. Kein Task, kein await, kein Hauptakteur -
            // nur ein Anhaengen an die Datei, das entweder gelingt oder eben nicht.
            let text = "ABSTURZ (ObjC): \(ausnahme.name.rawValue) — \(ausnahme.reason ?? "ohne Grund")"
            Protokoll.haengeRohAn(text)
        }
        // Erst jetzt anmelden: MetricKit liefert unmittelbar nach dem Anmelden, und die Zeilen
        // sollen hinter "App gestartet" stehen, nicht davor.
        Absturzberichte.geteilt.melde_an()
        // Fassung und iOS-Stand in die Startzeile. Ein geteiltes Protokoll landet Tage spaeter
        // bei jemandem, der nicht mehr weiss, welche Fassung darauf lief - und dann ist die
        // erste Rueckfrage immer dieselbe.
        schreibe("App gestartet. Fassung \(Fassung.anzeige), iOS \(UIDevice.current.systemVersion)")
    }

    /// Beim geordneten Wechsel in den Hintergrund aufrufen. Nimmt die Marke wieder weg.
    ///
    /// **Warum der Hintergrund und nicht das Beenden:** iOS ruft beim Abschiessen einer App aus
    /// dem App-Umschalter nichts mehr auf. Der Hintergrund ist der letzte Zeitpunkt, an dem man
    /// sicher etwas tun kann — und eine App, die im Hintergrund vom System entsorgt wird, ist
    /// nicht abgestuerzt.
    func gehtInDenHintergrund() {
        try? FileManager.default.removeItem(at: markeDatei)
        schreibe("In den Hintergrund gegangen.")
        schreibeJetzt()
    }

    // MARK: - Platte

    private static let zeitformat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm:ss"
        return f
    }()

    /// Wird aus dem Ausnahme-Handler gerufen, also ausserhalb jeder Isolation. Deshalb
    /// `nonisolated static` und ein reines Anhaengen ohne Zustand.
    nonisolated private static func haengeRohAn(_ text: String) {
        guard let basis = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        let ziel = basis.appendingPathComponent("protokoll.log")
        guard let daten = ("\n" + text).data(using: .utf8) else { return }
        if let griff = try? FileHandle(forWritingTo: ziel) {
            defer { try? griff.close() }
            _ = try? griff.seekToEnd()
            try? griff.write(contentsOf: daten)
        } else {
            try? daten.write(to: ziel)
        }
    }

    private func lade() {
        guard let text = try? String(contentsOf: datei, encoding: .utf8) else { return }
        zeilen = Array(text.split(separator: "\n").map(String.init).suffix(Self.maxZeilen))
    }

    private func planeSchreiben() {
        schreiber?.cancel()
        schreiber = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.schreibVerzoegerungSekunden * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.schreibeJetzt()
        }
    }

    private func schreibeJetzt() {
        try? zeilen.joined(separator: "\n").write(to: datei, atomically: true, encoding: .utf8)
    }
}
