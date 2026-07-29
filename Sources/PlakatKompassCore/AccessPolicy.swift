import Foundation

/// Wer darf was. Gegenstück zu `core/AccessPolicy.kt`.
///
/// Diese Regeln gehören an eine Stelle, weil sie sich sonst leise widersprechen. In der iOS-App
/// standen sie bis eben als zwei selbstgebaute Eigenschaften in `AppModel` — was für den
/// Solo-Modus gerade noch reichte, aber die Fälle „eigenes Gerät gesperrt" und „noch nicht
/// freigegeben" gar nicht kannte.
///
/// Wichtig ist der Unterschied zwischen zwei Sorten Erlaubnis:
///
/// - **lokal** — erfassen, Liste, Karte, amtlicher Export. Braucht nur eine Team-Kennung, kein
///   Geheimnis. Auch wer allein losgelegt hat, darf das.
/// - **Abgleich** — Pakete erzeugen und annehmen. Braucht das Team-Geheimnis **und** ein Gerät,
///   das freigegeben und nicht gesperrt ist.
public enum AccessPolicy {

    public static func hasTeamAccess(_ state: LocalTeamState) -> Bool {
        state.role != nil
            && !(state.teamId ?? "").isEmpty
            && !(state.teamSecret ?? "").isEmpty
    }

    public static func isLeader(_ state: LocalTeamState) -> Bool { state.role == .LEADER }

    public static func selfRecord(_ state: LocalTeamState) -> DeviceRecord? {
        state.devices.first { $0.deviceId == state.deviceId }
    }

    /// Die Teamleitung gilt immer als freigegeben.
    ///
    /// Sonst könnte sie sich selbst aussperren: Der eigene Eintrag entsteht beim Anlegen des
    /// Teams, und wenn der beim Zusammenführen einmal auf `approved = false` fiele, käme man an
    /// den eigenen Schlüssel nicht mehr heran.
    public static func isSelfApproved(_ state: LocalTeamState) -> Bool {
        guard hasTeamAccess(state) else { return false }
        if isLeader(state) { return true }
        guard let eigenes = selfRecord(state) else { return false }
        return eigenes.approved && !eigenes.blocked
    }

    public static func isSelfBlocked(_ state: LocalTeamState) -> Bool {
        selfRecord(state)?.blocked == true
    }

    public static func isDeviceApproved(_ state: LocalTeamState, deviceId: String) -> Bool {
        state.devices.contains { $0.deviceId == deviceId && $0.approved && !$0.blocked }
    }

    public static func canShowQr(_ state: LocalTeamState) -> Bool {
        isLeader(state) && isSelfApproved(state)
    }

    public static func canManageTeamSecurity(_ state: LocalTeamState) -> Bool {
        isLeader(state) && isSelfApproved(state)
    }

    /// Erfassen geht auch ohne Team-Geheimnis — für alle, die allein plakatieren.
    public static func canAddPoster(_ state: LocalTeamState) -> Bool {
        state.role != nil && !(state.teamId ?? "").isEmpty
    }

    public static func canSync(_ state: LocalTeamState) -> Bool {
        hasTeamAccess(state) && isSelfApproved(state)
    }

    /// Die Liste für die Stadtverwaltung darf jeder eingerichtete Nutzer erzeugen, auch ohne
    /// Team. Nur ein gesperrtes Gerät nicht — wer aus dem Team geworfen wurde, soll nicht in
    /// dessen Namen bei der Gemeinde auftreten.
    public static func canExportForAuthority(_ state: LocalTeamState) -> Bool {
        state.role != nil && !(state.teamId ?? "").isEmpty && !isSelfBlocked(state)
    }
}
