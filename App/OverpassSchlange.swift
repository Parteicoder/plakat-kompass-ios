import Foundation

/// Serialisiert alle Overpass-Anfragen der App auf höchstens eine gleichzeitig, mit einem
/// Mindestabstand zwischen zwei Anfragen. Gegenstück zu `OverpassSchlange` in
/// `feature/socialdata/OverpassSchlange.kt` (dort mit einem `Mutex` serialisiert; ein `actor`
/// ist das direkte Swift-Pendant — Zugriffe auf seinen Zustand sind ohne eigenes Sperren schon
/// serialisiert).
///
/// Overpass ist ein von Freiwilligen betriebener Dienst ohne Schlüssel und ohne Rechnung. Mit
/// `Gemeindegrenze` und der Gebietsschlüssel-Abfrage für Wahldaten hat die App zwei unabhängige
/// Aufrufer — ohne diese Warteschlange könnten sie sich gegenseitig in eine Drosselung (HTTP 429)
/// laufen lassen, etwa wenn ein Kartenschwenk beide gleichzeitig auslöst.
actor OverpassSchlange {
    static let geteilt = OverpassSchlange()

    private static let mindestabstand: TimeInterval = 1.0
    private var letzteAnfrage: Date?

    private init() {}

    func nacheinander<T: Sendable>(_ aufgabe: @Sendable () async -> T) async -> T {
        if let letzte = letzteAnfrage {
            let seither = Date().timeIntervalSince(letzte)
            if seither < Self.mindestabstand {
                try? await Task.sleep(nanoseconds: UInt64((Self.mindestabstand - seither) * 1_000_000_000))
            }
        }
        letzteAnfrage = Date()
        return await aufgabe()
    }
}
