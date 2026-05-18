# Flathub Arcade

A retro quiz game — can you name all GNOME apps from their icons?

![cover](cover.png)

## Gameplay

- **D-pad / Arrow keys** — browse icons
- **A / X / Enter** — reveal the app name
- **B / Z / Space** — jump to a random icon
- **SE / Tab** — toggle CRT effect

Browse app icons one by one or hit (A) for a random app. (B) reveals the app name and author. Treat it like a card memory game or simply enjoy some nice pixelart or an inspiration to take a peek at flathub.org.

## Framework

Built with [LÖVE 2D](https://love2d.org/) (11.5) — a Lua game framework. The game renders to a tiny 128×128 virtual canvas, then scales 5× with nearest-neighbor filtering for a crisp pixel art aesthetic. GPU shaders handle the CRT overlay, transition effects, and glitch distortions.

### Icons

32×32 RGBA PNGs of GNOME application icons, rendered from the [GNOME HIG](https://developer.gnome.org/hig/) icon set. Licensed under CC BY-SA 4.0. Read about [why they exist](https://blog.jimmac.eu/posts/app-pixels/). See more pixelart at [art.jimmac.eu](https://art.jimmac.eu)

## Running

### Desktop (Linux)

```bash
# Install LÖVE via Flatpak
flatpak install --user flathub org.love2d.love2d

# Run from source
flatpak run org.love2d.love2d .

# Or package and run
zip -r gnome-icons.love . -x "*.md" ".git/*" "cover.png" "*.sh"
flatpak run org.love2d.love2d gnome-icons.love
```

### Anbernic / KNULLI / PortMaster

The game runs on ARM handhelds via PortMaster's LÖVE 11.5 runtime.

See `tools/deploy-cubexx.sh` for info on how to deploy to the console over
a microSD card or SMB share on a local area network.

## License

Code: [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html)  
Icons: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 
