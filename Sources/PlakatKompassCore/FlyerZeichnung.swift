import Foundation

/// Wie eine Flyer-Tour auf der Karte gezeichnet wird.
///
/// Die Regel steht hier und nicht in der Ansicht, weil sie auf beiden Plattformen dieselbe sein
/// muss und weil genau hier auf Android ein Fehler lag: Dort wurde bei weniger als zwei Wegpunkten
/// gar nichts gezeichnet. Eine gerade gestartete Tour hat null Punkte, nach dem ersten Ortungs-Fix
/// genau einen — und der zweite kommt erst nach zwanzig bis vierzig Metern Fußweg, weil der
/// Aufzeichner Ortungssprünge herausfiltert. Wer die Tour startete, sah bis dahin eine leere Karte
/// und hielt die Aufzeichnung für kaputt.
///
/// Ein Test auf die Zeichenaufrufe selbst bräuchte eine Karte. Diese Zahl reicht, um die
/// Entscheidung festzunageln.
public enum FlyerZeichnung {
    /// Wie viele Formen eine Tour mit `punkte` Wegpunkten auf die Karte legt: keine ohne Punkte,
    /// den Startkreis ab dem ersten, den Balken zusätzlich ab dem zweiten.
    public static func formenAnzahl(punkte: Int) -> Int {
        if punkte <= 0 { return 0 }
        if punkte == 1 { return 1 }
        return 2
    }

    /// Breite des Balkens in Punkten. Deutlich mehr als eine Linie: Der Weg soll auf einen Blick
    /// erkennbar sein, auch während man läuft und nur kurz aufs Telefon schaut.
    public static let balkenBreite: Double = 14

    /// Radius des Startkreises in Metern.
    public static let startKreisRadius: Double = 12

    /// Deckkraft. Durchscheinend, damit die Straße unter dem Balken lesbar bleibt.
    public static let deckkraft: Double = 0.78
}
