import SwiftUI

/// Die Kurzanleitung: je Bereich ein paar Sätze, die beim **ersten** Öffnen erscheinen.
///
/// Gegenstück zu `ui/onboarding/OnboardingSteps.kt` auf Android, aber die Texte sind **neu
/// geschrieben, nicht übersetzt**. Drüben stehen darin „der runde Plus-Knopf", „die farbige
/// Leiste", „Handywechsel-Backup senden" — Bedienelemente, die es hier nicht gibt. Eine
/// Anleitung, die auf Knöpfe zeigt, die nicht da sind, ist schlimmer als keine: Sie lässt den
/// Nutzer suchen und am Ende an sich zweifeln.
///
/// Das Prinzip der Vorlage ist dagegen übernommen, und es ist das eigentlich Wertvolle: Die
/// Erklärung liegt **über dem echten, laufenden Bildschirm**, nicht über einem Abbild davon. Wer
/// liest „Filter oben links", sieht den Filter oben links, während er es liest.
enum Kurzanleitung {

    struct Seite {
        let ueberschrift: String
        let text: String
    }

    struct Bereich: Identifiable {
        /// Muss mit [RootView.Reiter] übereinstimmen.
        let id: String
        let marke: String
        let titel: String
        let seiten: [Seite]
    }

    static let alle: [Bereich] = [
        Bereich(
            id: "start",
            marke: "Start",
            titel: "Willkommen bei Plakat Kompass",
            seiten: [
                Seite(
                    ueberschrift: "Fünf Reiter unten",
                    text: """
                    Start, Erfassen, Liste, Karte und Abgleich. Jeder Bereich erklärt sich beim \
                    ersten Öffnen selbst — so wie dieser hier gerade.
                    """
                ),
                Seite(
                    ueberschrift: "Zuerst ein Team",
                    text: """
                    Ohne Team lässt sich nichts erfassen. Unter „Abgleich“ trittst du per \
                    QR-Code einem Team bei, gründest ein eigenes — oder legst allein los, wenn \
                    du für deine Gemeinde ohne Verbund unterwegs bist.
                    """
                ),
                Seite(
                    ueberschrift: "In deiner Nähe",
                    text: """
                    Sobald Plakate erfasst sind, steht hier das nächstgelegene hängende Plakat \
                    mit Entfernung. „Hinlaufen“ übergibt es an die Karten-App.
                    """
                )
            ]
        ),

        Bereich(
            id: "erfassen",
            marke: "Erfassen",
            titel: "Ein Plakat aufnehmen",
            seiten: [
                Seite(
                    ueberschrift: "Zuerst das Foto",
                    text: """
                    Tippe auf das Kamerasymbol. Die Kamera öffnet sich nur auf diesen Tipp hin, \
                    nie von selbst — und genau dort fragt iOS zum ersten Mal nach der \
                    Berechtigung, nicht schon beim Start der App.
                    """
                ),
                Seite(
                    ueberschrift: "Standort prüfen",
                    text: """
                    Der Standort kommt automatisch. Steht darunter „Ungenau“, lohnt sich später \
                    ein Blick auf die Karte. Ohne Standort lässt sich nicht speichern — ein \
                    Plakat, das man nicht wiederfindet, hilft niemandem.
                    """
                ),
                Seite(
                    ueberschrift: "Abnahmefrist setzen",
                    text: """
                    „Abnahme in … Tagen“ legt fest, bis wann das Plakat wieder abgehängt sein \
                    muss. Daraus rechnet die App die Frist, zeigt sie in der Liste und erinnert \
                    am Tag der Abnahme.
                    """
                ),
                Seite(
                    ueberschrift: "Zwei Bemerkungsfelder",
                    text: """
                    Sie sind nicht dasselbe: „Bemerkung für die Verwaltung“ landet im amtlichen \
                    Export und geht ans Rathaus. „Interne Bemerkung“ bleibt im Team und wird \
                    dort nie mitgeschickt.
                    """
                )
            ]
        ),

        Bereich(
            id: "liste",
            marke: "Liste",
            titel: "Liste und Status",
            seiten: [
                Seite(
                    ueberschrift: "Filter oben links",
                    text: """
                    „Aktiv“, „Überfällig“, „Probleme“ und „Alle“ — dieselbe Auswahl wie auf der \
                    Karte. Wer hier „Überfällig“ wählt und zur Karte wechselt, findet dort \
                    dieselben Plakate wieder.
                    """
                ),
                Seite(
                    ueberschrift: "Status pflegen",
                    text: """
                    Ein Plakat antippen, dann „Status ändern“: hängt, kontrolliert, beschädigt, \
                    fehlt, ersetzt, entfernt. Der Verlauf unter „Einstellungen“ hält fest, wer \
                    wann was geändert hat.
                    """
                ),
                Seite(
                    ueberschrift: "Löschen bleibt gelöscht",
                    text: """
                    Nach links wischen löscht ein Plakat — und zwar dauerhaft: Es kommt beim \
                    nächsten Abgleich nicht von einem anderen Gerät zurück.
                    """
                ),
                Seite(
                    ueberschrift: "Flyer-Touren",
                    text: """
                    Oben rechts geht es zu den Flyer-Touren. Eine laufende Tour zeichnet den \
                    Weg auch dann auf, wenn das Telefon in der Tasche steckt.
                    """
                )
            ]
        ),

        Bereich(
            id: "karte",
            marke: "Karte",
            titel: "Karte, Flyer und Sozialdaten",
            seiten: [
                Seite(
                    ueberschrift: "Plakate und Adressen",
                    text: """
                    Jeder Punkt ist ein Plakat; Antippen öffnet die Details. Über das Suchfeld \
                    springt die Karte an eine Adresse — praktisch, bevor es losgeht.
                    """
                ),
                Seite(
                    ueberschrift: "Flyerkarte",
                    text: """
                    Der Schalter mit der laufenden Figur blendet die Plakate aus und zeigt \
                    stattdessen die gelaufenen Wege als mintgrünes Band. So sieht das Team, \
                    welche Straßen schon versorgt sind.
                    """
                ),
                Seite(
                    ueberschrift: "Sozialdaten",
                    text: """
                    Der Schalter mit den drei Figuren legt einen Kreis von 300 Metern um die \
                    Kartenmitte und liest die amtlichen Zensus-Werte dafür — Durchschnittsalter, \
                    Miete je m², Anteil ab 65 und mehr. Das dauert rund fünfzehn Sekunden.
                    """
                ),
                Seite(
                    ueberschrift: "Gebietswerte, keine Personen",
                    text: """
                    Die Zahlen gelten für das Gebiet, nicht für einzelne Haushalte. Sie helfen \
                    bei der Frage, welche Themen vor Ort zählen — und wo sich Plakate und \
                    Flyer-Touren am ehesten lohnen.
                    """
                )
            ]
        ),

        Bereich(
            id: "abgleich",
            marke: "Abgleich",
            titel: "Team und Abgleich",
            seiten: [
                Seite(
                    ueberschrift: "Zwei Wege zum selben Ziel",
                    text: """
                    „Geräte in der Nähe“ gleicht per Funk ab. „Sync-Paket teilen“ verschickt \
                    denselben Inhalt als Datei. Beides spricht mit der Android-App.
                    """
                ),
                Seite(
                    ueberschrift: "Der Funk-Abgleich",
                    text: """
                    Beide Geräte müssen im selben WLAN sein — der Hotspot eines der Telefone \
                    genügt. Beim ersten Mal fragt iOS nach dem lokalen Netzwerk: Wer hier \
                    ablehnt, findet danach nie ein Gerät, ohne dass es eine Meldung gäbe.
                    """
                ),
                Seite(
                    ueberschrift: "Der Weg über die Datei",
                    text: """
                    Das Sync-Paket ist verschlüsselt und nur mit dem Team-Schlüssel zu öffnen. \
                    Es kann deshalb bedenkenlos durch einen Messenger — und funktioniert auch \
                    dann, wenn kein gemeinsames WLAN da ist.
                    """
                ),
                Seite(
                    ueberschrift: "Liste für die Verwaltung",
                    text: """
                    „Liste für die Verwaltung“ erzeugt ein ZIP mit Tabelle und Fotos. Anders \
                    als das Sync-Paket ist es unverschlüsselt — es geht ans Rathaus. Interne \
                    Bemerkungen stehen nicht darin.
                    """
                ),
                Seite(
                    ueberschrift: "Als Teamleitung",
                    text: """
                    Der QR-Code nimmt andere auf. Geräte lassen sich freigeben und sperren. \
                    Geht ein Telefon verloren, reicht Sperren nicht — dann „Team-Schlüssel \
                    erneuern“, denn wer den alten hat, öffnet weiterhin jedes Paket.
                    """
                )
            ]
        )
    ]

    static func fuer(_ bereich: String) -> Bereich? { alle.first { $0.id == bereich } }

    static var bereiche: [String] { alle.map(\.id) }

    // MARK: - Was schon gesehen wurde
    //
    // Der Stand liegt als EINE Zeichenkette in den Voreinstellungen, und die Ansichten lesen ihn
    // beide über dasselbe `@AppStorage`. Ein eigenes ObservableObject dafür wäre ein Umweg:
    // SwiftUI hält zwei `@AppStorage` mit demselben Schlüssel von allein synchron, ein Objekt
    // dazwischen müsste die Benachrichtigung von Hand nachbauen.

    static let schluessel = "kurzanleitungGesehen"

    static func zeigen(_ bereich: String, gesehen: String) -> Bool {
        fuer(bereich) != nil && !menge(gesehen).contains(bereich)
    }

    /// Der neue Stand, nachdem [bereich] erklärt wurde. Doppelte Einträge gibt es nicht.
    static func gemerkt(_ bereich: String, gesehen: String) -> String {
        var menge = menge(gesehen)
        menge.insert(bereich)
        // Sortiert, damit der gespeicherte Wert nicht bei jedem Lauf anders aussieht.
        return menge.sorted().joined(separator: ",")
    }

    static func anzahlGesehen(_ gesehen: String) -> Int {
        menge(gesehen).intersection(bereiche).count
    }

    private static func menge(_ gesehen: String) -> Set<String> {
        Set(gesehen.split(separator: ",").map(String.init))
    }
}

/// Die Erklärung als Schicht über dem echten Bildschirm.
///
/// Bewusst kein `sheet`: Ein Blatt schiebt sich über die Ansicht und verdeckt genau das, wovon
/// die Rede ist. Hier bleibt der Bildschirm sichtbar, nur abgedunkelt — man liest „Filter oben
/// links" und sieht den Filter oben links.
struct KurzanleitungOverlay: View {
    let bereich: Kurzanleitung.Bereich
    let fertig: () -> Void

    @State private var seite = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Nur so dunkel, dass der Text trägt. Ganz abdunkeln hiesse, den Bildschirm zu
            // verstecken, um ihn zu erklären.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { weiter() }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(bereich.marke.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Überspringen", action: fertig)
                        .font(.footnote)
                }

                Text(bereich.titel).font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bereich.seiten[seite].ueberschrift)
                        .font(.subheadline.weight(.semibold))
                    Text(bereich.seiten[seite].text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Feste Mindesthöhe, damit die Karte beim Blättern nicht springt — sonst wandert
                // der Knopf unter dem Finger weg.
                .frame(minHeight: 132, alignment: .top)

                HStack {
                    ForEach(bereich.seiten.indices, id: \.self) { i in
                        Circle()
                            .fill(i == seite ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                    Spacer()
                    Button(seite + 1 < bereich.seiten.count ? "Weiter" : "Verstanden") { weiter() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .transition(.opacity)
    }

    private func weiter() {
        if seite + 1 < bereich.seiten.count {
            withAnimation { seite += 1 }
        } else {
            fertig()
        }
    }
}
