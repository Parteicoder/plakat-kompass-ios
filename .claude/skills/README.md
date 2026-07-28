# Ponytail

Fremder Code, unverändert übernommen aus
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail), Fassung 4.8.4, MIT-Lizenz
(`LICENSE-ponytail`).

Ponytail erzwingt beim Programmieren die faulste Lösung, die trotzdem trägt: erst fragen, ob die
Aufgabe überhaupt gebraucht wird, dann im vorhandenen Code nachsehen, dann Standardbibliothek,
dann die Plattform selbst, und erst ganz zuletzt eine neue Abhängigkeit oder neuer Code.

Für dieses Repo ist das kein Beiwerk. Der Kern unter `Sources/PlakatKompassCore/` ist eine
Zweitfassung von Code, den es auf Android schon gibt — und Zweitfassungen laufen auseinander,
sobald eine Seite mehr kann als die andere. Je weniger hier steht, desto weniger kann abweichen.

## Aufruf

    /ponytail            # Standard
    /ponytail lite       # zurückhaltend
    /ponytail ultra      # streng
    /ponytail-help       # alle Modi und Befehle
    /ponytail-review     # vorhandenen Code durchsehen
    /ponytail-audit      # ganzes Projekt durchsehen

Die Dateien liegen unter `.claude/skills/`, dem Ort, an dem Claude Code Projekt-Skills sucht. Wer
das Repo klont, hat sie damit ohne Einrichtung.

**Bewusst nur die Skills, nicht das ganze Plugin.** Upstream bringt zusätzlich Hooks aus
`hooks/*.js` mit, die bei jedem Aufruf mitlaufen würden. Fremder Code, der ungefragt startet,
gehört nicht in ein Repo, in dem der Team-Schlüssel verarbeitet wird. Die Skills sind reiner Text
und tun nichts von allein.

## Auffrischen

    git clone --depth 1 https://github.com/DietrichGebert/ponytail.git /tmp/ponytail
    cp -r /tmp/ponytail/skills/. .claude/skills/
    cp /tmp/ponytail/LICENSE .claude/skills/LICENSE-ponytail
