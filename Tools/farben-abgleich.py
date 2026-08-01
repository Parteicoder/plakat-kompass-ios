#!/usr/bin/env python3
"""Stimmen die Farben mit der Android-Vorgabe überein?

Die verbindliche Quelle ist `ui/theme/AppColors.kt` im Android-Repo. Dieses Skript liest sie
und `App/Farben.swift`, stellt beide gegenüber und schlägt an, sobald ein Wert abweicht.

**Warum ein Skript und kein Test.** Der Test läge in diesem Repo, die Vorgabe aber im anderen.
Ein Test kann sie nicht sehen; er würde einen abgeschriebenen Wert gegen sich selbst prüfen und
wäre damit tautologisch — genau die Sorte grüner Haken, die nichts beweist.

    python3 Tools/farben-abgleich.py ../plakat-radar-intern

Ohne Pfad wird `../plakat-radar-intern` angenommen. Rückgabe 0, wenn alles passt.

**Die Textfarben stehen bewusst nicht in der Liste.** Auf iOS erledigen `.primary` und
`.secondary` diese Aufgabe und folgen dabei auch „Kontrast erhöhen" aus den Bedienungshilfen.
Sie fest zu verdrahten sähe genauso aus wie drüben und ignorierte jemanden, der sie braucht.
Wer das anders entscheidet, trägt sie unten ein — dann prüft das Skript sie mit.
"""
import re
import sys
from pathlib import Path

# iOS-Name -> Android-Token. Nur, was auf beiden Seiten dieselbe Aufgabe hat.
PAARE = {
    "gruen": "statusGreen",
    "blau": "statusBlue",
    "rot": "statusRed",
    "bernstein": "statusAmber",
    "grau": "statusGray",
    "flaeche": "screenGradientTop",
    "karte": "card",
    "flaecheAlt": "surfaceAlt",
    "leiste": "navBar",
    "rahmen": "border",
}

# Der Markenverlauf steht auf Android in BswGradient.kt, nicht in AppColors.kt.
VERLAUF_ERWARTET = ["8A1A5B", "E5005A", "FF8A00"]


def android_palette(text: str, name: str) -> dict[str, str]:
    # Auf "\n)" trennen, nicht auf ")": Jedes Color(0xFF...) enthaelt selbst eine Klammer.
    block = text.split(f"val {name} = AppColors(")[1].split("\n)")[0]
    return {k: v.upper() for k, v in re.findall(r"(\w+)\s*=\s*Color\(0xFF([0-9A-Fa-f]{6})\)", block)}


def main() -> int:
    wurzel = Path(sys.argv[1] if len(sys.argv) > 1 else "../plakat-radar-intern")
    farben_kt = wurzel / "app/src/main/java/de/bsw/plakatradar/ui/theme/AppColors.kt"
    verlauf_kt = wurzel / "app/src/main/java/de/bsw/plakatradar/ui/components/BswGradient.kt"
    farben_swift = Path("App/Farben.swift")

    for pfad in (farben_kt, verlauf_kt, farben_swift):
        if not pfad.exists():
            print(f"Nicht gefunden: {pfad}")
            print("Pfad zum Android-Repo als Argument angeben.")
            return 2

    kt = farben_kt.read_text()
    hell = android_palette(kt, "LightAppColors")
    dunkel = android_palette(kt, "DarkAppColors")
    if not hell or not dunkel:
        print("Die Paletten liessen sich nicht lesen — hat sich AppColors.kt umgebaut?")
        return 2

    swift = farben_swift.read_text()
    ios = {
        n: (h.upper(), d.upper())
        for n, h, d in re.findall(
            r"static let (\w+) = paar\(hell: 0x([0-9A-Fa-f]{6}), dunkel: 0x([0-9A-Fa-f]{6})\)",
            swift,
        )
    }

    fehler = 0
    print(f"{'iOS':<12}{'Android':<20}{'hell':<20}dunkel")
    for ios_name, kt_name in PAARE.items():
        ih, idk = ios.get(ios_name, ("fehlt", "fehlt"))
        ah, adk = hell.get(kt_name, "?"), dunkel.get(kt_name, "?")
        ok = ih == ah and idk == adk
        fehler += 0 if ok else 1
        print(f"{ios_name:<12}{kt_name:<20}{'OK' if ih == ah else 'XX'} {ih}/{ah:<12}"
              f"{'OK' if idk == adk else 'XX'} {idk}/{adk}")

    verlauf = [w.upper() for w in re.findall(r"Color\(0xFF([0-9A-Fa-f]{6})\)", verlauf_kt.read_text())]
    if verlauf[:3] != VERLAUF_ERWARTET:
        print(f"\nXX Markenverlauf drüben geändert: {verlauf[:3]} statt {VERLAUF_ERWARTET}")
        fehler += 1
    ios_verlauf = [w.upper() for w in re.findall(r"Color\(hex: 0x([0-9A-Fa-f]{6})\)", swift)][:3]
    if ios_verlauf != VERLAUF_ERWARTET:
        print(f"\nXX Markenverlauf hier abweichend: {ios_verlauf} statt {VERLAUF_ERWARTET}")
        fehler += 1

    offen = [t for t in hell if t not in PAARE.values()]
    if offen:
        print("\nAndroid-Token ohne Entsprechung (bewusst, siehe Kopf dieser Datei):")
        for t in sorted(offen):
            print(f"   {t:<22} hell #{hell[t]}  dunkel #{dunkel.get(t, '?')}")

    print()
    print("Alles gleich." if fehler == 0 else f"{fehler} Abweichung(en).")
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
