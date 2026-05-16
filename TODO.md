# TODO

## Goal
Add per-app metadata (name, author, short description) to the icon quiz game, sourced from Flathub appstream data. Animate icon to top on reveal, typewriter-style name + author, word-wrapped description below.

## Constraints
- 128×128 canvas, 5px narrow font, ~29 chars/line, 12 text lines available
- Title line: "APP NAME by Author" — must fit ~29 chars or wrap to 2 lines
- Description: max ~10 lines × 29 chars ≈ 290 chars, manually rewritten to fit
- Metadata as Lua sidecar for easy manual editing

## Tasks

### 1. Fetch Appstream Data from Flathub
- [x] Write `tools/fetch_metadata.py` that:
  - searches Flathub API (`POST /api/v2/search`) for each icon filename
  - fetches appstream data (`GET /api/v2/appstream/{app_id}`)
  - extracts: `name`, `developer_name`, `summary`, `description`
  - outputs `assets/meta.lua` — a Lua table keyed by icon filename
- [x] Run the script to generate initial `meta.lua` for all 166 icons
- [x] Manually review & rewrite descriptions to fit (~90 chars / 3 lines target, max 290)

### 2. Metadata Sidecar Format
- [x] `assets/meta.lua` format:
  ```lua
  return {
    calculator = { name="Calculator", author="GNOME", desc="Solve equations with basic, scientific, financial or programming modes." },
    amberol = { name="Amberol", author="Emmanuele Bassi", desc="Plays music and nothing else." },
    -- ...
  }
  ```
- [x] Load in `love.load()` via `love.filesystem.load()`
- [x] Fallback: if icon not in meta table, use filename as name, empty author, no description

### 3. Reveal Animation
- [x] On reveal (A/x/Enter), animate icon from center position to top (y=3), easing over ~0.3s
- [x] Typewriter effect: reveal name letter-by-letter (~50 chars/sec)
- [x] Play a subtle keystroke/tick sound per character (type.wav, rate-limited to 40ms)
- [x] Show "by Author" on same line (or next line if too long), typed after name
- [x] Word-wrap description below, fade in after typing finishes (0.4s fade)

### 4. Game State Changes
- [x] Add `reveal_anim` state tracking: `{phase, timer, chars_shown, icon_y}`
- [x] Phases: `idle` → `sliding` (icon moves up) → `typing` (name+author) → `desc` (description fades in)
- [x] D-pad left/right during reveal resets to next icon (cancel reveal)
- [x] Adjust counter position to bottom of screen

### 5. Sound Effect
- [x] Generate `assets/sfx/type.wav` — short tick/click for typewriter keystroke
- [x] Play per character during typing phase (rate-limited to 40ms)

### 6. Cleanup & Deploy
- [x] Remove `DepartureMono.otf` from project
- [x] Rebuild `.love` (console deploy when available)
- [ ] Test on hardware (pending console connection)

## Notes
- Flathub search API: `POST https://flathub.org/api/v2/search` with `{"query":"appname"}`
- Flathub appstream: `GET https://flathub.org/api/v2/appstream/{app_id}` (note: some use lowercase like `org.gnome.clocks`)
- Not all icons will match Flathub — some are GNOME core only, some are custom. Script should log misses for manual fixup.
- Description rewrites should be short, punchy, all-caps friendly (no HTML tags)
- The wide font variant is not used for now
