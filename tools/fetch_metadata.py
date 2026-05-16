#!/usr/bin/env python3
"""Fetch appstream metadata from Flathub for all icon PNGs."""

import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

ICONS_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "assets", "meta.lua")

MAX_DESC = 280

# Comprehensive mapping: icon filename -> Flathub app ID
# None = skip (no flathub entry)
APP_IDS = {
    "alpaca": "com.jeffser.Alpaca",
    "amberol": "io.bassi.Amberol",
    "apostrophe": "org.gnome.gitlab.somas.Apostrophe",
    "aria": "com.poppingmoon.aria",
    "atomix": "org.gnome.atomix",
    "audio-sharing": "de.haeckerfelix.AudioSharing",
    "authenticator": "com.belmoussaoui.Authenticator",
    "bazaar": "io.github.kolunmi.Bazaar",
    "bazaar-old": None,
    "biblioteca": "app.drey.Biblioteca",
    "blanket": "com.rafaelmardojai.Blanket",
    "boatswain": "com.feaneron.Boatswain",
    "boxes": "org.gnome.Boxes",
    "brasero": "org.gnome.Brasero",
    "brief": "io.github.shonebinu.Brief",
    "builder": "org.gnome.Builder",
    "calculator": "org.gnome.Calculator",
    "calendar": "org.gnome.Calendar",
    "calls": "org.gnome.Calls",
    "carburetor": "io.frama.tractor.carburetor",
    "cartridges": "page.kramo.Cartridges",
    "characters": "org.gnome.Characters",
    "cheese": "org.gnome.Cheese",
    "chess-clock": "eu.fortysixandtwo.chessclock",
    "citations": "org.gnome.World.Citations",
    "clapper": "com.github.rafostar.Clapper",
    "clocks": "org.gnome.clocks",
    "collision": "dev.geopjr.Collision",
    "color-manager": None,
    "colorcode": "com.oyajun.ColorCode",
    "colorway": "io.github.lainsce.Colorway",
    "commit": "re.sonny.Commit",
    "connections": "org.gnome.Connections",
    "contacts": "org.gnome.Contacts",
    "cozy": "com.github.geigi.cozy",
    "curtail": "com.github.huluti.Curtail",
    "decibels": "org.gnome.Decibels",
    "decoder": "com.belmoussaoui.Decoder",
    "deer": None,
    "dejadup-backups": "org.gnome.DejaDup",
    "dev-toolbox": "me.iepure.devtoolbox",
    "dialect": "app.drey.Dialect",
    "disk-analyzer": "org.gnome.baobab",
    "disks": "org.gnome.DiskUtility",
    "drawing": "com.github.maoschanz.drawing",
    "drum-machine": "io.github.revisto.drum-machine",
    "dspy": "org.gnome.dspy",
    "ear-tag": "app.drey.EarTag",
    "elastic": "app.drey.Elastic",
    "element": "im.riot.Riot",
    "elfin": "cafe.avery.Delfin",
    "emblem": "org.gnome.design.Emblem",
    "errands": "io.github.mrvladus.List",
    "esim": None,
    "evince": "org.gnome.Evince",
    "exchange": "io.github.shonebinu.Exchange",
    "exercise-timer": None,
    "exhibit": "io.github.nokse22.Exhibit",
    "eye-of-gnome": "org.gnome.eog",
    "eyedropper": "com.github.finefindus.eyedropper",
    "file-shredder": None,
    "files": "org.gnome.Nautilus",
    "firmware": "org.gnome.Firmware",
    "fonts": "org.gnome.font-viewer",
    "forgesparks": "com.mardojai.ForgeSparks",
    "fragments": "de.haeckerfelix.Fragments",
    "gameeky": "dev.tchx84.Gameeky",
    "gamepad-mirror": "page.codeberg.vendillah.GamepadMirror",
    "gaphor": "org.gaphor.Gaphor",
    "gelly": "io.m51.Gelly",
    "gimp": "org.gimp.GIMP",
    "gitte": "de.wwwtech.gitte",
    "gnurd": None,
    "health": "dev.Cogitri.Health",
    "help": None,
    "hieroglyphic": "io.github.finefindus.Hieroglyphic",
    "highscore": None,
    "iotas": "org.gnome.World.Iotas",
    "ip-lookup": "io.github.bytezz.IPLookup",
    "jellybean": "garden.turtle.Jellybean",
    "junction": "re.sonny.Junction",
    "kasasa": "io.github.kelvinnovais.Kasasa",
    "keyrack": "app.drey.KeyRack",
    "komikku": "info.febvre.Komikku",
    "kooha": "io.github.seadve.Kooha",
    "kotoba": "net.trowell.kotoba",
    "kuychi": "one.naiara.Kuychi",
    "laser": "nl.andreasknoben.Laser",
    "letterpress": None,
    "letters": "net.codelogistics.letters",
    "lipi": None,
    "logs": "org.gnome.Logs",
    "lorem": "org.gnome.design.Lorem",
    "maps": "org.gnome.Maps",
    "markets": None,
    "mesero": None,
    "metadata-cleaner": "io.gitlab.metadatacleaner.metadatacleaner",
    "metronome": "com.adrienplazas.Metronome",
    "millisecond": "io.github.gaheldev.Millisecond",
    "mixtape": None,
    "mousai": "io.github.seadve.Mousai",
    "mousam": "io.github.amit9838.mousam",
    "music": "org.gnome.Music",
    "mutter-viewer": None,
    "mypaint": "org.mypaint.MyPaint",
    "navigator": None,
    "nucleus": "page.codeberg.lo_vely.Nucleus",
    "obfuscate": "com.belmoussaoui.Obfuscate",
    "os-install": None,
    "paper-clip": None,
    "papers": "org.gnome.Papers",
    "photos": "org.gnome.Photos",
    "piccolo": "art.fatdawlf.Piccolo",
    "pika-backup": "org.gnome.World.PikaBackup",
    "plots": None,
    "podcasts": "org.gnome.Podcasts",
    "polari": "org.gnome.Polari",
    "poliedros": "io.github.kriptolix.Poliedros",
    "quertone": None,
    "reflection": None,
    "resources": "net.nokyan.Resources",
    "reversi": "org.gnome.Reversi",
    "rissole": None,
    "robots": "org.gnome.Robots",
    "rotor": None,
    "screenshot": "org.gnome.Screenshot",
    "scriptorium": "io.github.cgueret.Scriptorium",
    "seahorse": "org.gnome.seahorse.Application",
    "settings": None,
    "shaper": None,
    "share-preview": "com.rafaelmardojai.SharePreview",
    "shortwave": "de.haeckerfelix.Shortwave",
    "showtime": "org.gnome.Showtime",
    "simple-scan": "org.gnome.SimpleScan",
    "sitra": "io.github.sitraorg.sitra",
    "software": None,
    "solanum": "org.gnome.Solanum",
    "sound-recorder": "org.gnome.SoundRecorder",
    "ssh-pilot": "io.github.mfat.sshpilot",
    "stereotype": None,
    "stickynotes": None,
    "sudoku": "org.gnome.Sudoku",
    "system-monitor": "org.gnome.SystemMonitor",
    "tabs": None,
    "tangram": "re.sonny.Tangram",
    "teddybear": None,
    "terminal": "org.gnome.Terminal",
    "text-editor": "org.gnome.TextEditor",
    "text-pieces": "io.gitlab.liferooter.TextPieces",
    "tour": None,
    "transmission": "com.transmissionbt.Transmission",
    "tuba": "dev.geopjr.Tuba",
    "typesetter": "net.trowell.typesetter",
    "valuta": "io.github.idevecore.Valuta",
    "video-trimmer": "org.gnome.gitlab.YaLTeR.VideoTrimmer",
    "videos": "org.gnome.Totem",
    "vinyl": "page.codeberg.M23Snezhok.Vinyl",
    "wallet": None,
    "warp": "app.drey.Warp",
    "weather": "org.gnome.Weather",
    "web": "org.gnome.Epiphany",
    "webfont-kit-generator": "com.rafaelmardojai.WebfontKitGenerator",
    "webkit": None,
    "wifiauth": None,
    "wike": "com.github.hugolabe.Wike",
    "workbench": "re.sonny.Workbench",
}


def fetch_appstream(app_id):
    """Fetch appstream data for an app ID."""
    url = f"https://flathub.org/api/v2/appstream/{app_id}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"  Fetch error for '{app_id}': {e}", file=sys.stderr)
    return None


def clean_html(text):
    """Strip HTML tags and collapse whitespace."""
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def truncate_desc(text, max_len=MAX_DESC):
    """Truncate to max_len at word boundary."""
    if len(text) <= max_len:
        return text
    truncated = text[:max_len]
    last_space = truncated.rfind(" ")
    if last_space > max_len // 2:
        truncated = truncated[:last_space]
    return truncated.rstrip(".,;:!? ") + "."


def to_ascii(s):
    """Normalize unicode to ASCII (strip accents, fix special chars)."""
    import unicodedata
    # Manual replacements for non-decomposable chars
    s = s.replace('\u0142', 'l').replace('\u0141', 'L')  # ł Ł
    s = s.replace('\u00f8', 'o').replace('\u00d8', 'O')  # ø Ø
    s = s.replace('\u2013', '-').replace('\u2014', '-')   # en/em dash
    s = s.replace('\u2018', "'").replace('\u2019', "'")   # smart quotes
    s = s.replace('\u201c', '"').replace('\u201d', '"')
    nfkd = unicodedata.normalize('NFKD', s)
    return nfkd.encode('ascii', 'ignore').decode('ascii')


def lua_escape(s):
    """Escape a string for Lua."""
    s = to_ascii(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
    icons_dir = ICONS_DIR
    icons = sorted(f.replace(".png", "") for f in os.listdir(icons_dir) if f.endswith(".png"))
    print(f"Found {len(icons)} icons")

    meta = {}
    missed = []
    skipped = []

    for i, icon in enumerate(icons):
        print(f"[{i+1}/{len(icons)}] {icon}...", end=" ", flush=True)

        app_id = APP_IDS.get(icon, "UNMAPPED")

        if app_id == "UNMAPPED":
            print("UNMAPPED")
            missed.append(icon)
            continue

        if app_id is None:
            print("SKIP")
            skipped.append(icon)
            continue

        data = fetch_appstream(app_id)
        if not data or "name" not in data:
            print("NO DATA")
            missed.append(icon)
            continue

        name = data.get("name", icon)
        author = data.get("developer_name", "Unknown")
        summary = data.get("summary", "")
        desc_html = data.get("description", "")
        desc = clean_html(desc_html)

        # Use summary as the short description (it's usually best)
        short_desc = summary if summary else truncate_desc(desc)

        meta[icon] = {
            "name": name,
            "author": author,
            "desc": short_desc,
        }
        print(f"OK - {name} by {author}")
        time.sleep(0.1)

    # Write Lua file
    with open(OUTPUT, "w") as f:
        f.write("-- Auto-generated from Flathub appstream data\n")
        f.write("-- Edit descriptions to fit ~29 chars/line on 128x128 canvas\n")
        f.write("return {\n")
        for icon in sorted(meta.keys()):
            m = meta[icon]
            name = lua_escape(m["name"])
            author = lua_escape(m["author"])
            desc = lua_escape(m["desc"])
            key = f'["{icon}"]' if "-" in icon else icon
            f.write(f'  {key} = {{ name="{name}", author="{author}", desc="{desc}" }},\n')

        # Add skipped/missed entries as stubs for manual filling
        f.write("\n  -- Manual entries (no Flathub data)\n")
        for icon in sorted(skipped + missed):
            label = icon.replace("-", " ").replace("_", " ").title()
            key = f'["{icon}"]' if "-" in icon else icon
            f.write(f'  {key} = {{ name="{lua_escape(label)}", author="Unknown", desc="" }},\n')

        f.write("}\n")

    total = len(meta) + len(skipped) + len(missed)
    print(f"\nWrote {OUTPUT}")
    print(f"  Fetched: {len(meta)}")
    print(f"  Skipped: {len(skipped)}")
    print(f"  Missed:  {len(missed)}")
    print(f"  Total:   {total}")


if __name__ == "__main__":
    main()
