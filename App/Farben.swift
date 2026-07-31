import SwiftUI

/// Die Farben der Marke, aus `ui/theme/AppColors.kt` und `ui/components/BswGradient.kt` der
/// Android-Fassung übernommen — damit beide Apps als dasselbe Programm erkennbar sind.
///
/// **Was übernommen wird und was nicht.** Übernommen sind die Werte: der Verlauf, die
/// Status-Ampel, die warmen Flächentöne. Nicht übernommen ist Androids Aufbau mit
/// `LocalAppColors` und einer eigenen `ThemeController`-Umschaltung. Auf iOS macht das System
/// das: `Color(uiColor:)` mit einem `UITraitCollection`-Block liefert je nach Hell/Dunkel den
/// richtigen Wert, und die Wahl trifft der Nutzer in den Systemeinstellungen. Einen eigenen
/// Schalter dafür zu bauen hiesse, dem iPhone-Nutzer eine Einstellung zweimal anzubieten.
enum Farben {

    /// Der Markenverlauf: Magenta über Pink nach Orange. In beiden Modi derselbe — genau wie
    /// drüben, wo `BswGradientColors` ausdrücklich nicht zwischen hell und dunkel unterscheidet.
    static let verlauf = [
        Color(hex: 0x8A1A5B),
        Color(hex: 0xE5005A),
        Color(hex: 0xFF8A00)
    ]

    /// Das Pink der Marke. Steht zusätzlich als `AccentColor` im Asset-Katalog, damit iOS es
    /// von sich aus für Knöpfe, Schalter und Auswahlen nimmt — ohne eine Zeile Code.
    static let pink = Color(hex: 0xE5005A)

    // MARK: - Status-Ampel
    //
    // Im Dunkeln aufgehellt, sonst leuchten die satten Töne auf dem warmen Anthrazit nicht.
    // Die Werte stammen 1:1 aus LightAppColors/DarkAppColors.

    static let gruen = paar(hell: 0x0D9488, dunkel: 0x2DD4BF)
    static let blau = paar(hell: 0x1D4ED8, dunkel: 0x7CA9FF)
    static let rot = paar(hell: 0xDC2626, dunkel: 0xFB7185)
    static let bernstein = paar(hell: 0xD97706, dunkel: 0xFBBF24)
    static let grau = paar(hell: 0x64748B, dunkel: 0xA99C90)

    /// Der Seitenhintergrund: fast weiss mit einem Stich ins Warme, im Dunkeln warmes Anthrazit.
    ///
    /// Android legt darüber einen dreistufigen Verlauf. Hier ist es eine Fläche: Unter einer
    /// SwiftUI-`List` und in `Form`-Abschnitten wäre der Verlauf ohnehin verdeckt, und ein
    /// Verlauf, den man nur auf einem von fünf Bildschirmen sieht, ist kein Wiedererkennen,
    /// sondern eine Unstimmigkeit.
    static let flaeche = paar(hell: 0xFDF8F6, dunkel: 0x1E1815)

    private static func paar(hell: UInt32, dunkel: UInt32) -> Color {
        Color(uiColor: UIColor { merkmale in
            merkmale.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dunkel))
                : UIColor(Color(hex: hell))
        })
    }
}

extension Color {
    /// Aus `0xRRGGBB`, weil die Vorlage die Farben so notiert. Wer sie vergleichen will, soll
    /// nicht erst drei Fliesskommazahlen zurückrechnen müssen.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Die Kopfkarte der Startseite — das Gegenstück zu `ModernHomeHeroCard`.
///
/// Sie ist der eine Ort, an dem die Marke groß auftritt. Alles andere in dieser App bleibt
/// bewusst iOS: Der Verlauf hier reicht, damit jemand die beiden Fassungen nebeneinander als
/// dasselbe Programm erkennt, ohne dass Apples Bedienung nachgebaut werden müsste.
struct BswKopfkarte: View {
    let teamName: String
    let rolle: String
    let plakate: Int
    let ueberfaellig: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(teamName) · \(rolle)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(plakate == 1 ? "1 Plakat" : "\(plakate) Plakate")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if ueberfaellig > 0 {
                Text(ueberfaellig == 1 ? "1 überfällig" : "\(ueberfaellig) überfällig")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Farben.verlauf[1])
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.94), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.vertical, 20)
        .background(
            LinearGradient(colors: Farben.verlauf, startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        // Der Verlauf ist bunt; ohne diesen Schatten steht weisser Text auf Orange zu dünn da.
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }
}
