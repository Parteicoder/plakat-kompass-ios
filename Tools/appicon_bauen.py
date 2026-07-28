#!/usr/bin/env python3
"""Erzeugt das iOS-App-Icon aus dem Android-Launcher-Icon.

    python3 Tools/appicon_bauen.py ../plakat-radar-intern/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png

Warum es dieses Skript gibt und nicht nur die fertige PNG-Datei: Die Umrechnung ist nicht
offensichtlich, und ohne sie stuende im Repo ein Bild, von dem niemand mehr weiss, wie es
entstanden ist.

Drei Schritte, jeder mit einem Grund:

1. **Die weissen Ecken fluten.** Das Android-Icon bringt seine abgerundeten Ecken als Grafik
   mit. iOS legt spaeter seine eigene Maske darueber - blieben die weissen Ecken stehen, saehe
   man nach dem Maskieren einen hellen Rand um die cremefarbene Flaeche. Geflutet wird von den
   vier Ecken aus, damit die weissen Stellen INNERHALB des Kompasses (der Ring um die Mitte)
   unberuehrt bleiben.
2. **Auf 1024x1024 vergroessern.** Das verlangt der App Store, und ab Xcode 15 genuegt diese
   eine Groesse; alle kleineren rechnet Xcode selbst aus.
3. **Ohne Alphakanal speichern.** Ein App-Icon mit Transparenz weist der App Store zurueck.

ACHTUNG, das ist die Schwachstelle: Die groesste im Android-Repo vorhandene Fassung des
Kompass-Motivs ist 192x192. Auf 1024 hochgerechnet ist das ein Faktor von gut fuenf, und das
sieht man. Fuer Entwicklung und TestFlight reicht es, fuer eine Veroeffentlichung nicht. Sobald
die Originaldatei auftaucht, gehoert sie hier hinein - dann faellt der Vergroesserungsschritt
weg und der Rest bleibt.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ZIEL = Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

# Wie weit eine Farbe vom Weiss der Ecke abweichen darf, um noch mitgeflutet zu werden.
# Der cremefarbene Koerper liegt rund 16 davon entfernt, also muss die Schwelle darunter
# bleiben, sonst frisst die Flut das ganze Icon.
FLUT_SCHWELLE = 12

# Zwischenfarbe, mit der geflutet wird, bevor der Grundton eingesetzt wird.
#
# Ohne diesen Umweg tut die Flut nichts: PIL bricht sofort ab, wenn die Fuellfarbe dem
# Startpixel aehnlicher ist als die Schwelle - und Creme auf Weiss ist genau dieser Fall. Der
# Fehler ist still, das Bild kommt unveraendert zurueck. Mit einer Farbe, die weit weg von
# allem im Bild liegt, kann das nicht passieren.
MARKIERUNG = (255, 0, 255)


def baue(quelle: Path) -> Image.Image:
    bild = Image.open(quelle).convert("RGB")
    breite, hoehe = bild.size

    creme = bild.getpixel((breite // 2, 6))
    for ecke in [(0, 0), (breite - 1, 0), (0, hoehe - 1), (breite - 1, hoehe - 1)]:
        # Zweimal fluten: erst die Ecke markieren, dann die Markierung durch den Grundton
        # ersetzen. Beim zweiten Durchgang ist das Startpixel die Markierung und damit weit
        # von Creme entfernt, also greift der Abbruch nicht mehr.
        ImageDraw.floodfill(bild, ecke, MARKIERUNG, thresh=FLUT_SCHWELLE)
        ImageDraw.floodfill(bild, ecke, creme, thresh=0)

    if bild.size != (1024, 1024):
        bild = bild.resize((1024, 1024), Image.LANCZOS)
    return bild


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    quelle = Path(sys.argv[1])
    if not quelle.is_file():
        print(f"Quelle nicht gefunden: {quelle}")
        return 1

    bild = baue(quelle)

    # Gegenprobe statt Vertrauen: Ecken cremefarben, Kompassmitte noch rot, kein Alphakanal.
    ecken = [bild.getpixel(p) for p in [(0, 0), (1023, 0), (0, 1023), (1023, 1023)]]
    assert len(set(ecken)) == 1, f"Ecken nicht einheitlich: {ecken}"
    mitte = bild.getpixel((512, 512))
    assert mitte[0] > 120 and mitte[1] < 80, f"Kompassmitte sieht falsch aus: {mitte}"
    assert bild.mode == "RGB", f"Alphakanal uebrig: {bild.mode}"

    ZIEL.parent.mkdir(parents=True, exist_ok=True)
    bild.save(ZIEL, "PNG", optimize=True)
    print(f"{ZIEL} geschrieben, Grundton {ecken[0]}, aus {quelle} ({Image.open(quelle).size[0]} px)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
