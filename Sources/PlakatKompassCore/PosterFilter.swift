import Foundation

/// Wonach Plakate in Liste und Karte gefiltert werden.
///
/// Steht hier und nicht in einer der beiden Ansichten, weil beide dieselbe Auswahl anbieten. Lägen
/// die Regeln zweimal da, würde früher oder später „Probleme" in der Liste etwas anderes bedeuten
/// als „Probleme" auf der Karte — und niemand würde es merken, weil beide für sich plausibel
/// aussehen.
public enum PosterFilter: String, CaseIterable, Sendable {
    case aktiv = "Aktiv"
    case ueberfaellig = "Überfällig"
    case probleme = "Probleme"
    case alle = "Alle"

    public var beschriftung: String { rawValue }

    /// Ob ein Plakat zu diesem Filter gehört. `jetzt` ist die Zeit in Millisekunden seit 1970 —
    /// als Parameter und nicht intern geholt, damit ein Test die Uhr stellen kann.
    public func passt(_ poster: Poster, jetzt: Int64) -> Bool {
        switch self {
        case .aktiv:
            return poster.status != .REMOVED
        case .ueberfaellig:
            // Ein Plakat ohne Frist ist nie überfällig. Deshalb Int64.max als Ersatzwert und
            // nicht 0 — sonst wäre plötzlich jedes fristlose Plakat überfällig.
            return poster.status != .REMOVED && (poster.plannedRemovalAt ?? Int64.max) < jetzt
        case .probleme:
            return poster.status == .DAMAGED || poster.status == .MISSING
        case .alle:
            return true
        }
    }
}

public extension Array where Element == Poster {
    func gefiltert(nach filter: PosterFilter, jetzt: Int64) -> [Poster] {
        self.filter { filter.passt($0, jetzt: jetzt) }
    }
}
