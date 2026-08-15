import CoreLocation
import MapKit
import PlakatKompassCore
import StoreKit
import SwiftUI

/// Die Startseite. Gegenstück zu `ModernHomeScreen` auf Android.
///
/// Sie kann nichts, was die anderen Bereiche nicht auch können — und ist trotzdem der wichtigste
/// Bildschirm: Wer die App im Stehen aufmacht, mit einer Hand, will in zwei Sekunden wissen, ob
/// etwas ansteht und wo das nächste Plakat ist. Dafür durch drei Reiter zu suchen ist eine
/// Zumutung.
struct StartView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.requestReview) private var bewertungAnfragen
    @StateObject private var standort = Standort()
    @AppStorage("bewertungErsterStart") private var bewertungErsterStart = 0.0
    @AppStorage("bewertungLetzteAnfrage") private var bewertungLetzteAnfrage = 0.0
    @AppStorage("bewertungAnzahl") private var bewertungAnzahl = 0

    private var zahlen: HomeStats { HomeStats(posters: model.state.posters) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BswKopfkarte(
                        teamName: model.state.teamName ?? "Lokales Plakat-Team",
                        rolle: model.state.role == .LEADER ? "Teamleitung" : "Mitglied",
                        plakate: model.state.posters.count,
                        ueberfaellig: model.faelligeAbnahmen
                    )

                    if model.faelligeAbnahmen > 0 {
                        Faelliges(anzahl: model.faelligeAbnahmen)
                    }

                    Zahlenreihe(zahlen: zahlen)

                    // Nur fuer die Teamleitung, genau wie auf Android (AccessPolicy.canShowQr).
                    // Wer keinen QR ausgeben darf, soll den Schalter gar nicht erst sehen.
                    if AccessPolicy.canShowQr(model.state) {
                        Teamaufnahme(nearby: model.nearby)
                    }

                    UnterstuetzenUndGemeinschaft {
                        bewertungAnzahl = RatingPromptPolicy.maximaleAnfragen
                        bewertungAnfragen()
                    }

                    if let treffer = naechstes {
                        NaechstesPlakat(treffer: treffer)
                    } else if standort.abgelehnt && !model.state.posters.isEmpty {
                        // Sonst fehlt die Karte "naechstes Plakat" einfach, ohne dass jemand
                        // erfaehrt warum - und man sucht den Fehler bei den Plakaten.
                        OrtungAbgelehnt(
                            text: "Ohne Standort lässt sich das nächste Plakat nicht bestimmen."
                        )
                    } else if model.state.posters.isEmpty {
                        Text("Noch keine Plakate erfasst. Der Anfang steht unter „Erfassen“.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            // Der warme Grundton aus AppColors.kt. Kein Verlauf: Unter einer List waere er
            // ohnehin verdeckt, und einer, den man nur hier sieht, faellt als Unstimmigkeit auf
            // statt als Wiedererkennung.
            .background(Farben.flaeche)
            .navigationTitle("Plakat Kompass")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        EinstellungenView()
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SozialdatenView()
                    } label: {
                        Label("Sozialdaten", systemImage: "chart.bar")
                    }
                }
            }
            .onAppear { standort.starte() }
            .onDisappear { standort.stoppe() }
            .task { pruefeBewertungsfenster() }
        }
    }

    private func pruefeBewertungsfenster() {
        let jetzt = Date()
        guard bewertungErsterStart > 0 else {
            bewertungErsterStart = jetzt.timeIntervalSince1970
            return
        }

        let letzteAnfrage = bewertungLetzteAnfrage > 0
            ? Date(timeIntervalSince1970: bewertungLetzteAnfrage)
            : nil
        guard RatingPromptPolicy.sollAnzeigen(
            ersterStart: Date(timeIntervalSince1970: bewertungErsterStart),
            letzteAnfrage: letzteAnfrage,
            anzahl: bewertungAnzahl,
            jetzt: jetzt
        ) else { return }

        bewertungAnzahl += 1
        bewertungLetzteAnfrage = jetzt.timeIntervalSince1970
        bewertungAnfragen()
    }

    private var naechstes: NearestPoster.Treffer? {
        guard let hier = standort.position else { return nil }
        return NearestPoster.find(
            model.state.posters,
            latitude: hier.coordinate.latitude,
            longitude: hier.coordinate.longitude
        )
    }
}

/// „Support & Community" — die drei runden Knöpfe von der Android-Startseite.
///
/// Die Ziele sind aus `ModernHomeScreen.kt` übernommen, nicht geraten:
/// `SUPPORT_URL`, `C3_DISCORD_URL` und `X_URL`.
///
/// **Die Symbole sind die echten aus der Android-Fassung**, aus deren `res/drawable` übernommen:
/// `ic_kofi.png`, `ic_c3.png` und `ic_x_logo.xml`. Hier stand zuerst ein Ersatz aus
/// Systemzeichen — der war nur nötig, solange ich die Dateien nicht gefunden hatte.
///
/// Beim X-Zeichen war das ein Glücksfall: Androids `pathData` **ist** SVG-Syntax. Der Pfad
/// konnte wörtlich in eine SVG-Hülle übernommen werden, statt ihn nachzuzeichnen — und
/// Xcode legt SVG als echten Vektor ab. Als Schablone eingebunden, damit das schwarze Zeichen
/// im dunklen Erscheinungsbild nicht verschwindet; Ko-fi und C3 bleiben farbig, das sind Logos.
///
/// Die Beschriftungen bleiben unter den Symbolen stehen. Für VoiceOver ist ein Logo ohne Text
/// ein leerer Knopf, und die Vorlesetexte sind wörtlich die `contentDescription` von drüben.
private struct UnterstuetzenUndGemeinschaft: View {
    let bewerten: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("SUPPORT & COMMUNITY")
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            HStack(spacing: 22) {
                Knopf(ziel: "https://ko-fi.com/parteicoder",
                      bild: "SymbolKofi", schablone: false,
                      titel: "Ko-fi", vorlesen: "Ko-fi unterstützen")
                Knopf(ziel: "https://discord.gg/6GxADmF5Re",
                      bild: "SymbolC3", schablone: false,
                      titel: "C3", vorlesen: "C3-Discord")
                Knopf(ziel: "https://x.com/Plakatkompass",
                      bild: "SymbolX", schablone: true,
                      titel: "X", vorlesen: "X, at Plakatkompass")
            }

            Button(action: bewerten) {
                VStack(spacing: 5) {
                    Text("APP BEWERTEN")
                        .font(.caption2.weight(.semibold))
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("App bewerten")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private struct Knopf: View {
        let ziel: String
        let bild: String
        /// Nur fuer das X-Zeichen: Es ist einfarbig schwarz und muesste im dunklen
        /// Erscheinungsbild sonst gegen einen dunklen Grund antreten. Ko-fi und C3 sind
        /// mehrfarbige Logos und bleiben, wie sie sind.
        let schablone: Bool
        let titel: String
        let vorlesen: String

        var body: some View {
            // Ein fehlerhaftes Ziel laesst hier lieber den Knopf weg, als die App mit einem
            // erzwungenen Auspacken zu beenden. Die drei Adressen sind fest, aber ein Tippfehler
            // beim naechsten Aendern soll niemanden etwas kosten.
            if let url = URL(string: ziel) {
                Link(destination: url) {
                    VStack(spacing: 5) {
                        Image(bild)
                            .renderingMode(schablone ? .template : .original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 52, height: 52)
                            .background(.thinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.25)))
                        Text(titel).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vorlesen)
            }
        }
    }
}

/// „Teamaufnahme" auf der Startseite — Gegenstück zu `ModernTeamQrCard.kt`.
///
/// **Der Schalter tut zwei Dinge, und das zweite ist der eigentliche Punkt:** Er zeigt den
/// Team-QR *und* startet den Funk-Abgleich. Auf Android hängt beides an
/// `setTeamJoinWindowActive`, und das hat einen handfesten Grund — der QR allein genügt nicht.
/// Wer ihn scannt, hat den Team-Schlüssel, aber ohne laufenden Funk gibt es keinen Rückkanal:
/// Das neue Gerät kann sich nicht melden, und die Teamleitung sieht es nicht in ihrer Liste.
///
/// Genau das war auf iOS die Lücke. `TeamQrView` lag unter „Abgleich" und zeigte brav einen
/// rollenden Code — den Funk musste man daneben von Hand einschalten und daran denken. Wer es
/// vergaß, hielt einen gültigen QR hin, der nichts bewirkte.
private struct Teamaufnahme: View {
    // Bindet direkt an nearby.laeuft, wie der bestehende Funk-Regler in SyncView.swift -
    // statt an ein eigenes @State, das den Startwert nicht kennt: Wer den Funk schon vom
    // Abgleich-Tab aus gestartet hatte, saehe hier trotzdem "aus" und keinen QR-Code, obwohl
    // der Abgleich laengst lief.
    @ObservedObject var nearby: NearbyAbgleich

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Team-QR").font(.headline)
                Spacer()
                Toggle("Teamaufnahme", isOn: Binding(
                    get: { nearby.laeuft },
                    set: { $0 ? nearby.start() : nearby.stop() }
                ))
                .labelsHidden()
            }

            Text(nearby.laeuft ? "Teamaufnahme aktiv" : "Teamaufnahme starten")
                .font(.subheadline)
                .foregroundStyle(nearby.laeuft ? .primary : .secondary)

            if nearby.laeuft {
                TeamQrView()
            } else {
                Text("""
                Schaltet den Funk ein und zeigt den QR-Code. Beides zusammen — ohne Funk hat das \
                neue Gerät zwar den Code, aber keinen Weg zurück.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Der einzige Hinweis, der auffallen muss. Alles andere auf dieser Seite ist Information,
/// das hier ist eine Frist.
private struct Faelliges: View {
    let anzahl: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(anzahl == 1 ? "1 Plakat abnehmen" : "\(anzahl) Plakate abnehmen")
                    .font(.headline)
                Text("Die Abnahmefrist ist erreicht.")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Farben.rot, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Zahlenreihe: View {
    let zahlen: HomeStats

    var body: some View {
        // Zwei mal zwei statt vier nebeneinander: Auf einem iPhone SE wären vier Kacheln so
        // schmal, dass dreistellige Zahlen umbrechen.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Kachel(wert: zahlen.aktiv, titel: "Aktiv", farbe: Farben.blau)
                Kachel(wert: zahlen.kontrolliert, titel: "OK", farbe: Farben.gruen)
            }
            GridRow {
                Kachel(wert: zahlen.probleme, titel: "Probleme", farbe: Farben.rot)
                Kachel(wert: zahlen.entfernt, titel: "Entfernt", farbe: Farben.grau)
            }
        }
    }
}

private struct Kachel: View {
    let wert: Int
    let titel: String
    let farbe: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(wert)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(farbe)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(titel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titel): \(wert)")
    }
}

private struct NaechstesPlakat: View {
    @EnvironmentObject private var model: AppModel
    let treffer: NearestPoster.Treffer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In deiner Nähe")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                if let name = treffer.poster.localPhotoFileName,
                   let bild = UIImage(contentsOfFile: model.photoURL(name).path) {
                    Image(uiImage: bild)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(treffer.poster.addressHint.isEmpty
                         ? treffer.poster.type.beschriftung
                         : treffer.poster.addressHint)
                        .font(.headline)
                    Text("\(NearestPoster.distanceText(treffer.entfernungMeter)) · \(treffer.poster.status.beschriftung)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button { treffer.poster.hinlaufen() } label: {
                Label("Hinlaufen", systemImage: "figure.walk")
                    .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

