#!/bin/bash
# Deploy Flathub Arcade to Anbernic R35S via PortMaster (LÖVE 11.5)
#
# The R35S runs ROCKNIX. When the SD card is inserted, it shows up as two
# partitions: ROCKNIX (system) and STORAGE (data). Ports live under:
#   STORAGE/games-internal/roms/ports/
#
# Usage:
#   ./tools/deploy-r35s.sh                        # auto-detect mounted card
#   ./tools/deploy-r35s.sh /run/media/user/STORAGE # explicit mount point
#   ./tools/deploy-r35s.sh --package-only          # just build the .love file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GAME_ID="flathub-arcade"
LOVE_FILE="$GAME_ID.love"
PORTS_SUBDIR="games-internal/roms/ports"
LAUNCHER="Flathub Arcade.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [mountpoint]

Package and deploy Flathub Arcade to an Anbernic R35S SD card (ROCKNIX).

Options:
  --package-only    Build the .love file without deploying
  --dry-run         Show what would be copied without doing it
  -h, --help        Show this help

Arguments:
  mountpoint        Path to the mounted STORAGE partition (auto-detected if omitted)

The STORAGE partition typically mounts at:
  /run/media/\$USER/STORAGE   (systemd automount / udisks2)
  /media/\$USER/STORAGE

Ports live at: <mountpoint>/games-internal/roms/ports/
EOF
    exit 0
}

# Build the .love zip bundle (same logic as deploy-cubexx.sh)
package_love() {
    info "Packaging $LOVE_FILE..."
    cd "$PROJECT_DIR"
    rm -f "$LOVE_FILE"
    zip -9 -r "$LOVE_FILE" . \
        -x "*.md" \
        -x ".git/*" \
        -x ".gitignore" \
        -x "cover.png" \
        -x "*.sh" \
        -x "tools/*" \
        -x "TODO*" \
        -x "*.love"
    local size
    size=$(du -h "$LOVE_FILE" | cut -f1)
    info "Built $LOVE_FILE ($size)"
}

# Auto-detect the STORAGE partition by label or by presence of games-internal/
find_storage() {
    local candidates=()
    for base in "/run/media/$USER" "/run/media/$(whoami)" "/media/$USER" /mnt; do
        [ -d "$base" ] || continue
        for dir in "$base"/*/; do
            [ -d "$dir" ] || continue
            # ROCKNIX data partition has games-internal/
            if [ -d "${dir}games-internal" ]; then
                candidates+=("${dir%/}")
            fi
        done
    done

    if [ ${#candidates[@]} -eq 1 ]; then
        echo "${candidates[0]}"
        return 0
    elif [ ${#candidates[@]} -gt 1 ]; then
        warn "Multiple ROCKNIX STORAGE partitions found:"
        for i in "${!candidates[@]}"; do
            echo "  [$((i+1))] ${candidates[$i]}"
        done
        read -rp "Select [1-${#candidates[@]}]: " choice
        local idx=$((choice - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#candidates[@]} ]; then
            echo "${candidates[$idx]}"
            return 0
        fi
        error "Invalid selection."
    fi

    return 1
}

# Update or insert gamelist.xml entry for EmulationStation
update_gamelist() {
    local ports_path="$1"
    local gamelist="$ports_path/gamelist.xml"

    python3 - "$gamelist" <<'PYEOF'
import xml.etree.ElementTree as ET
import os, sys

path = sys.argv[1]
entry_path = "./Flathub Arcade.sh"

meta = {
    "name": "Flathub Arcade",
    "desc": "Guess the app name from its icon.",
    "image": "./flathub-arcade/cover.png",
    "developer": "jimmac.eu",
    "genre": "Quiz",
}

if os.path.exists(path):
    tree = ET.parse(path)
    root = tree.getroot()
else:
    root = ET.Element("gameList")
    tree = ET.ElementTree(root)

game = None
for g in root.findall("game"):
    p = g.find("path")
    if p is not None and p.text == entry_path:
        game = g
        break

if game is None:
    game = ET.SubElement(root, "game")
    ET.SubElement(game, "path").text = entry_path

for key, val in meta.items():
    el = game.find(key)
    if el is None:
        el = ET.SubElement(game, key)
    el.text = val

ET.indent(tree, space="\t")
tree.write(path, encoding="unicode", xml_declaration=True)
PYEOF
}

# If the ext4 STORAGE partition is mounted read-only (common with this
# card's recurring bitmap errors), unmount, fsck, and remount it rw.
ensure_rw() {
    local mountpoint="$1"
    if mount | grep -q "${mountpoint}.*\bro\b"; then
        warn "Filesystem is read-only — running e2fsck..."
        local dev
        dev=$(mount | grep "${mountpoint}" | awk '{print $1}')
        udisksctl unmount --block-device "$dev" 2>/dev/null || true
        pkexec e2fsck -y "$dev" 2>&1 | tail -3
        udisksctl mount --block-device "$dev"
        info "Remounted read-write."
    fi
}

deploy() {
    local mountpoint="$1"
    local dry_run="${2:-false}"

    ensure_rw "$mountpoint"

    local ports_path="$mountpoint/$PORTS_SUBDIR"
    local game_path="$ports_path/$GAME_ID"

    if [ "$dry_run" = "true" ]; then
        info "Dry run — would deploy to:"
        echo "  $game_path/$LOVE_FILE"
        echo "  $ports_path/$LAUNCHER"
        [ -f "$PROJECT_DIR/cover.png" ] && echo "  $game_path/cover.png"
        return
    fi

    [ -d "$ports_path" ] || error "Ports directory not found: $ports_path\nIs this the right mount point?"

    info "Deploying to $mountpoint..."
    mkdir -p "$game_path"

    cp "$PROJECT_DIR/$LOVE_FILE" "$game_path/$LOVE_FILE"
    info "Copied $LOVE_FILE → $game_path/"

    cp "$PROJECT_DIR/$LAUNCHER" "$ports_path/$LAUNCHER"
    chmod +x "$ports_path/$LAUNCHER" 2>/dev/null || true
    info "Copied launcher → $ports_path/"

    if [ -f "$PROJECT_DIR/cover.png" ]; then
        cp "$PROJECT_DIR/cover.png" "$game_path/cover.png"
        info "Copied cover.png → $game_path/"
    fi

    update_gamelist "$ports_path"
    info "Updated gamelist.xml"

    sync 2>/dev/null || true

    echo ""
    info "Deployment complete!"
    info "Game path: $game_path"
    info "Restart EmulationStation on the R35S to see the game."
}

# --- Main ---

PACKAGE_ONLY=false
DRY_RUN=false
MOUNTPOINT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --package-only) PACKAGE_ONLY=true ;;
        --dry-run)      DRY_RUN=true ;;
        -h|--help)      usage ;;
        -*)             error "Unknown option: $1" ;;
        *)              MOUNTPOINT="$1" ;;
    esac
    shift
done

package_love

if [ "$PACKAGE_ONLY" = "true" ]; then
    info "Package-only mode — skipping deployment."
    exit 0
fi

if [ -n "$MOUNTPOINT" ]; then
    [ -d "$MOUNTPOINT" ] || error "Mount point does not exist: $MOUNTPOINT"
    deploy "$MOUNTPOINT" "$DRY_RUN"
else
    info "Auto-detecting ROCKNIX STORAGE partition..."
    MOUNTPOINT=$(find_storage) || error "Could not find ROCKNIX STORAGE partition.
Try: $(basename "$0") /run/media/$USER/STORAGE"
    info "Found: $MOUNTPOINT"
    deploy "$MOUNTPOINT" "$DRY_RUN"
fi
