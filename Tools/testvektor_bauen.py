#!/usr/bin/env python3
"""
Erzeugt den Testvektor, gegen den Android und iOS geprueft werden.

Der Punkt dieses Skripts ist seine Unabhaengigkeit: Der Vektor entsteht weder mit dem
Kotlin- noch mit dem Swift-Code. Wuerde eine der beiden Seiten ihn erzeugen, wuerde der
Test nur bestaetigen, dass diese Seite mit sich selbst uebereinstimmt. So muessen beide
gegen etwas Drittes bestehen.

Alles ist fest verdrahtet, auch der IV. Ein Sync-Paket im Betrieb bekommt selbstverstaendlich
einen frischen Zufalls-IV; fuer einen Vektor waere das nutzlos, weil die Datei sich bei jedem
Lauf aendern wuerde.

    python3 Tools/testvektor_bauen.py

Schreibt nach Tests/Vektoren/.
"""

import hashlib
import io
import json
import os
import zipfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

HIER = os.path.dirname(os.path.abspath(__file__))
ZIEL = os.path.join(HIER, "..", "Tests", "Vektoren")

MAGIC = b"PRSYNC2\n"
TEAM_SECRET = "testvektor-team-geheimnis-0123456789abcdef"
IV = bytes(range(12))  # fest, siehe oben
FOTO_NAME = "poster-testvektor-0001.jpg"

TEAM_ID = "11111111-2222-3333-4444-555555555555"
GERAET_A = "aaaaaaaa-0000-0000-0000-000000000001"
GERAET_B = "bbbbbbbb-0000-0000-0000-000000000002"


def snapshot() -> dict:
    hash_hex = hashlib.sha256(TEAM_SECRET.encode("utf-8")).hexdigest()
    return {
        "schemaVersion": 2,
        "teamId": TEAM_ID,
        "teamName": "Testvektor-Team",
        "senderDeviceId": GERAET_A,
        "senderName": "Android-Testgeraet",
        "teamSecretHash": hash_hex,
        "devices": [
            {
                "deviceId": GERAET_A,
                "displayName": "Android-Testgeraet",
                "role": "LEADER",
                "joinedAt": 1700000000000,
                "approved": True,
                "blocked": False,
            },
            {
                "deviceId": GERAET_B,
                "displayName": "iPhone-Testgeraet",
                "role": "MEMBER",
                "joinedAt": 1700000100000,
                "approved": True,
                "blocked": False,
            },
        ],
        "posters": [
            {
                "id": "poster-0001",
                "teamId": TEAM_ID,
                "latitude": 51.4600,
                "longitude": 12.6330,
                "addressHint": "Bahnhofstrasse 1",
                "type": "LAMP_POST",
                "status": "HANGING",
                "localPhotoFileName": FOTO_NAME,
                "createdByDeviceId": GERAET_A,
                "createdByName": "Android-Testgeraet",
                "createdAt": 1700000200000,
                "updatedAt": 1700000200000,
                "plannedRemovalAt": 1701209800000,
                "officialNote": "Umlaut-Probe: Grosse Strasse, Aeschylos, weiss",
                "internalNote": "",
            },
            {
                # Ohne Foto und ohne Abnahmefrist: Beide Felder muessen null vertragen.
                "id": "poster-0002",
                "teamId": TEAM_ID,
                "latitude": 51.4610,
                "longitude": 12.6340,
                "addressHint": "",
                "type": "TRIANGLE_STAND",
                "status": "DAMAGED",
                "localPhotoFileName": "",
                "createdByDeviceId": GERAET_B,
                "createdByName": "iPhone-Testgeraet",
                "createdAt": 1700000300000,
                "updatedAt": 1700000400000,
                "plannedRemovalAt": None,
                "officialNote": "",
                "internalNote": "nur intern",
            },
        ],
        "deletedPosters": [
            {
                "posterId": "poster-0003",
                "teamId": TEAM_ID,
                "deletedByDeviceId": GERAET_A,
                "deletedByName": "Android-Testgeraet",
                "deletedAt": 1700000500000,
            }
        ],
        "events": [
            {
                "id": "event-0001",
                "posterId": "poster-0001",
                "teamId": TEAM_ID,
                "actorDeviceId": GERAET_A,
                "actorName": "Android-Testgeraet",
                "action": "erfasst",
                "createdAt": 1700000200000,
            }
        ],
        "flyerTours": [
            {
                "id": "tour-0001",
                "teamId": TEAM_ID,
                "name": "Testtour",
                "status": "FINISHED",
                "points": [
                    {"latitude": 51.4600, "longitude": 12.6330, "createdAt": 1700000600000},
                    {"latitude": 51.4605, "longitude": 12.6335, "createdAt": 1700000660000},
                ],
                "createdByDeviceId": GERAET_A,
                "createdByName": "Android-Testgeraet",
                "startedAt": 1700000600000,
                "updatedAt": 1700000700000,
                "finishedAt": 1700000700000,
            }
        ],
        "createdAt": 1700000800000,
    }


def foto_bytes() -> bytes:
    """Ein 'Foto' von 2 KiB. Muss ueber MIN_VALID_PHOTO_BYTES (1 KiB) liegen, sonst weisen
    beide Seiten es zu Recht ab."""
    return bytes((i * 7 + 11) % 256 for i in range(2048))


def baue() -> bytes:
    puffer = io.BytesIO()
    with zipfile.ZipFile(puffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("snapshot.json", json.dumps(snapshot(), indent=2, ensure_ascii=False))
        zf.writestr(f"photos/{FOTO_NAME}", foto_bytes())
    klartext = puffer.getvalue()

    schluessel = hashlib.sha256(TEAM_SECRET.encode("utf-8")).digest()  # ROHE 32 Byte
    chiffrat = AESGCM(schluessel).encrypt(IV, klartext, MAGIC)  # Tag haengt hinten dran
    return MAGIC + IV + chiffrat


def pruefe(paket: bytes) -> None:
    """Ein Vektor, den niemand gegengelesen hat, ist keiner."""
    assert paket[:8] == MAGIC, "Magic stimmt nicht"
    schluessel = hashlib.sha256(TEAM_SECRET.encode("utf-8")).digest()
    klartext = AESGCM(schluessel).decrypt(paket[8:20], paket[20:], MAGIC)
    with zipfile.ZipFile(io.BytesIO(klartext)) as zf:
        namen = sorted(zf.namelist())
        assert namen == ["photos/" + FOTO_NAME, "snapshot.json"], namen
        wieder = json.loads(zf.read("snapshot.json"))
        assert wieder == snapshot(), "Snapshot kam nicht unveraendert zurueck"
        assert zf.read("photos/" + FOTO_NAME) == foto_bytes()

    # Falscher Schluessel MUSS scheitern - sonst prueft das Format gar nichts.
    falsch = hashlib.sha256(b"falsches-geheimnis").digest()
    try:
        AESGCM(falsch).decrypt(paket[8:20], paket[20:], MAGIC)
        raise AssertionError("Falscher Schluessel wurde akzeptiert")
    except Exception as fehler:
        if isinstance(fehler, AssertionError):
            raise

    # Veraendertes Byte MUSS scheitern.
    kaputt = bytearray(paket)
    kaputt[-1] ^= 0x01
    try:
        AESGCM(schluessel).decrypt(bytes(kaputt[8:20]), bytes(kaputt[20:]), MAGIC)
        raise AssertionError("Veraendertes Paket wurde akzeptiert")
    except Exception as fehler:
        if isinstance(fehler, AssertionError):
            raise


def main() -> None:
    os.makedirs(ZIEL, exist_ok=True)
    paket = baue()
    pruefe(paket)

    with open(os.path.join(ZIEL, "sync-vektor-1.prsync"), "wb") as f:
        f.write(paket)
    with open(os.path.join(ZIEL, "sync-vektor-1.json"), "w", encoding="utf-8") as f:
        json.dump(snapshot(), f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(ZIEL, "sync-vektor-1.txt"), "w", encoding="utf-8") as f:
        f.write(
            "Testvektor fuer PRSYNC2\n"
            "=======================\n\n"
            f"Team-Geheimnis : {TEAM_SECRET}\n"
            f"Schluessel     : SHA-256 davon, die ROHEN 32 Byte\n"
            f"IV             : {IV.hex()}  (fest, damit die Datei reproduzierbar ist)\n"
            f"AAD            : die 8 Magic-Bytes\n"
            f"Paketgroesse   : {len(paket)} Byte\n"
            f"SHA-256 Paket  : {hashlib.sha256(paket).hexdigest()}\n\n"
            "Erzeugt von Tools/testvektor_bauen.py - absichtlich weder von der Kotlin-\n"
            "noch von der Swift-Seite, damit beide gegen etwas Drittes bestehen muessen.\n"
        )

    print(f"geschrieben: {len(paket)} Byte")
    print(f"sha256: {hashlib.sha256(paket).hexdigest()}")


if __name__ == "__main__":
    main()
