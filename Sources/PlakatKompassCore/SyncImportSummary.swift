import Foundation

/// Was hat ein Import am Plakatbestand geändert? Formuliert die Rückmeldung, die nach einem
/// Sync-Paket oder einer Funk-Übertragung angezeigt wird. Portierung von `SyncImportSummary.kt`.
///
/// Bewusst ohne UI-Bezug und ohne Zustand: Der Text hängt allein am Vorher/Nachher, deshalb lässt
/// er sich per Unit-Test festnageln.
public func syncImportSummary(before: LocalTeamState, after: LocalTeamState, source: String) -> String {
    let beforePosters = Dictionary(uniqueKeysWithValues: before.posters.map { ($0.id, $0) })
    let afterPosterIds = Set(after.posters.map(\.id))
    let added = after.posters.filter { beforePosters[$0.id] == nil }.count
    let updated = after.posters.filter { poster in
        guard let old = beforePosters[poster.id] else { return false }
        return old != poster
    }.count
    let removed = beforePosters.keys.filter { !afterPosterIds.contains($0) }.count
    let unchanged = after.posters.count - added - updated
    let removedSuffix = removed > 0 ? ", \(removed) teamweit gelöscht" : ""
    return "\(source) erfolgreich importiert: \(added) Plakate neu, \(updated) aktualisiert, "
        + "\(unchanged) unverändert\(removedSuffix)."
}
