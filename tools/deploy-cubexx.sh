#!/bin/bash
# Deploy Flathub Arcade to Anbernic RG CubeXX via PortMaster (LÖVE 11.5)
#
# Packages the game into a .love bundle and deploys it either to a mounted
# SD card or over the network via KNULLI's Samba share.
#
# Usage:
#   ./tools/deploy-cubexx.sh                  # auto-detect (network or card)
#   ./tools/deploy-cubexx.sh /media/user/TF2  # explicit mount point
#   ./tools/deploy-cubexx.sh --package-only   # just build the .love file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GAME_ID="flathub-arcade"
LOVE_FILE="$GAME_ID.love"
PORTS_DIR="ports"
LAUNCHER="Flathub Arcade.sh"
OLD_GAME_ID="gnome-icons"
OLD_LAUNCHER="GNOME Icons.sh"

# KNULLI network share
SMB_HOST="knulli.local"
SMB_SHARE="share"
GVFS_BASE="/run/user/$(id -u)/gvfs/smb-share:server=${SMB_HOST},share=${SMB_SHARE}"

# Resolve hostname to IPv4 (avahi/mDNS hostnames can resolve to IPv6 link-local
# addresses that smbclient doesn't handle well; prefer plain IPv4).
resolve_ipv4() {
    local host="$1"
    # avahi-resolve is the most reliable for .local names
    if command -v avahi-resolve &>/dev/null; then
        avahi-resolve -4 -n "$host" 2>/dev/null | awk '{print $2}' | head -1
        return
    fi
    # fallback: host command (first A record)
    if command -v host &>/dev/null; then
        host "$host" 2>/dev/null | awk '/has address/{print $4}' | head -1
        return
    fi
}

SMB_HOST_IP=$(resolve_ipv4 "$SMB_HOST")
# Use IP for smbclient if we got one, keeping the hostname for display
SMB_TARGET="${SMB_HOST_IP:-$SMB_HOST}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [mountpoint]

Package and deploy Flathub Arcade to an Anbernic RG CubeXX SD card.

Options:
  --package-only    Build the .love file without deploying
  --dry-run         Show what would be copied without doing it
  -h, --help        Show this help

Arguments:
  mountpoint        Path to the mounted TF2 SD card (auto-detected if omitted)

The script:
  1. Packages the game source into $LOVE_FILE
  2. Finds the device — checks KNULLI Samba share (GVFS or smbclient),
     then falls back to mounted SD cards
  3. Copies $LOVE_FILE to roms/ports/$GAME_ID/
  4. Copies the launcher script to roms/ports/
  5. Copies the cover image for EmulationStation

Prerequisites:
  - PortMaster installed on the device
  - LÖVE 11.5 runtime installed via PortMaster
EOF
    exit 0
}

# Build the .love zip bundle
package_love() {
    info "Packaging $LOVE_FILE..."
    cd "$PROJECT_DIR"

    # Remove old bundle
    rm -f "$LOVE_FILE"

    # Package everything except dev files
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

# Try to mount KNULLI's Samba share via GVFS (nautilus/Files auto-mount)
find_knulli_gvfs() {
    if [ -d "$GVFS_BASE/roms" ]; then
        echo "$GVFS_BASE"
        return 0
    fi

    # Try to trigger GVFS mount via gio
    if command -v gio &>/dev/null; then
        gio mount "smb://$SMB_HOST/$SMB_SHARE" 2>/dev/null || true
        sleep 1
        if [ -d "$GVFS_BASE/roms" ]; then
            echo "$GVFS_BASE"
            return 0
        fi
    fi

    return 1
}

# Deploy via smbclient (fallback when GVFS is unavailable)
deploy_smbclient() {
    local dry_run="${1:-false}"
    local smb_url="//$SMB_TARGET/$SMB_SHARE"
    local remote_ports="roms/ports"
    local remote_game="$remote_ports/$GAME_ID"

    if [ "$dry_run" = "true" ]; then
        info "Dry run — would deploy via smbclient to $smb_url:"
        echo "  $remote_game/$LOVE_FILE"
        echo "  $remote_ports/$LAUNCHER"
        [ -f "$PROJECT_DIR/cover.png" ] && echo "  $remote_game/cover.png"
        return
    fi

    info "Deploying via smbclient to $smb_url..."

    local local_gamelist
    local_gamelist=$(mktemp)
    
    # 1. Try to fetch existing gamelist.xml
    smbclient "$smb_url" -N -s /dev/null -c "get roms/ports/gamelist.xml $local_gamelist" 2>/dev/null || true

    # 2. Update it locally
    update_gamelist_file "$local_gamelist"

    # 3. Build smbclient batch commands — remove old game first
    local batch
    batch=$(mktemp)
    cat > "$batch" <<SMBBATCH
cd roms\\ports
mask ""
del $OLD_GAME_ID\\*
rmdir $OLD_GAME_ID
del "$OLD_LAUNCHER"
mkdir $GAME_ID
cd $GAME_ID
lcd $PROJECT_DIR
put $LOVE_FILE
SMBBATCH

    if [ -f "$PROJECT_DIR/cover.png" ]; then
        echo "put cover.png" >> "$batch"
    fi

    # Launcher and updated gamelist go into roms/ports/
    cat >> "$batch" <<SMBBATCH
cd /roms\\ports
lcd $PROJECT_DIR
put "$LAUNCHER"
lcd $(dirname "$local_gamelist")
put $(basename "$local_gamelist") gamelist.xml
SMBBATCH

    smbclient "$smb_url" -N -s /dev/null -b 65520 < "$batch"
    local rc=$?
    rm -f "$batch" "$local_gamelist"

    if [ $rc -ne 0 ]; then
        error "smbclient failed (exit $rc). Is KNULLI powered on and on the network?"
    fi

    echo ""
    info "Deployment complete! (method: smbclient → $SMB_HOST)"
    info "Refresh gamelists in EmulationStation to see the game."
}

# Auto-detect: KNULLI network share first, then mounted SD cards
find_target() {
    # 1. GVFS-mounted Samba share (nautilus/Files auto-mount)
    info "Looking for KNULLI GVFS mount..." >&2
    local gvfs
    gvfs=$(find_knulli_gvfs 2>/dev/null) || true
    if [ -n "$gvfs" ]; then
        info "Found KNULLI via GVFS: $gvfs" >&2
        echo "gvfs:$gvfs"
        return 0
    fi
    warn "No GVFS mount found." >&2

    # 2. smbclient (direct network, no mount needed)
    if command -v smbclient &>/dev/null; then
        info "Trying smbclient to $SMB_HOST ($SMB_TARGET)..." >&2
        if smbclient -N -L "$SMB_TARGET" &>/dev/null; then
            info "Found KNULLI via Samba at $SMB_HOST" >&2
            echo "smb:"
            return 0
        fi
        warn "Could not reach $SMB_HOST via smbclient." >&2
    else
        warn "smbclient not installed, skipping network deploy." >&2
    fi

    # 3. Mounted SD card
    info "Scanning for mounted SD cards..." >&2
    local candidates=()
    for base in /media/$USER /run/media/$USER /mnt; do
        if [ -d "$base" ]; then
            for dir in "$base"/*/; do
                [ -d "$dir" ] || continue
                if [ -d "${dir}roms" ] || [ -d "${dir}Roms" ] || [ -d "${dir}ports" ]; then
                    candidates+=("${dir%/}")
                fi
            done
        fi
    done

    if [ ${#candidates[@]} -eq 1 ]; then
        echo "local:${candidates[0]}"
        return 0
    elif [ ${#candidates[@]} -gt 1 ]; then
        warn "Multiple SD cards detected:"
        for i in "${!candidates[@]}"; do
            echo "  [$((i+1))] ${candidates[$i]}"
        done
        read -rp "Select card [1-${#candidates[@]}]: " choice
        local idx=$((choice - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#candidates[@]} ]; then
            echo "local:${candidates[$idx]}"
            return 0
        fi
    fi
    warn "No mounted SD cards with a roms/ directory found." >&2

    return 1
}

# Update or insert gamelist.xml entry for EmulationStation
update_gamelist_file() {
    local gamelist="$1"

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

if os.path.exists(path) and os.path.getsize(path) > 0:
    tree = ET.parse(path)
    root = tree.getroot()
else:
    root = ET.Element("gameList")
    tree = ET.ElementTree(root)

# Find or create entry
game = None
for g in root.findall("game"):
    p = g.find("path")
    if p is not None and p.text == entry_path:
        game = g
        break

if game is None:
    game = ET.SubElement(root, "game")
    ET.SubElement(game, "path").text = entry_path

# Update fields (preserve playcount, lastplayed, gametime)
for key, val in meta.items():
    el = game.find(key)
    if el is None:
        el = ET.SubElement(game, key)
    el.text = val

ET.indent(tree, space="\t")
tree.write(path, encoding="unicode", xml_declaration=True)
PYEOF
}

# Find the roms directory (case-insensitive)
find_roms_dir() {
    local mount="$1"
    if [ -d "$mount/roms" ]; then
        echo "$mount/roms"
    elif [ -d "$mount/Roms" ]; then
        echo "$mount/Roms"
    else
        echo "$mount/roms"  # default, will be created
    fi
}

# Deploy to a local path (SD card or GVFS mount)
deploy_local() {
    local mountpoint="$1"
    local dry_run="${2:-false}"

    local roms_dir
    roms_dir=$(find_roms_dir "$mountpoint")
    local ports_path="$roms_dir/$PORTS_DIR"
    local game_path="$ports_path/$GAME_ID"

    if [ "$dry_run" = "true" ]; then
        info "Dry run — would deploy to:"
        echo "  $game_path/$LOVE_FILE"
        echo "  $ports_path/$LAUNCHER"
        [ -f "$PROJECT_DIR/cover.png" ] && echo "  $game_path/cover.png"
        return
    fi

    info "Deploying to $mountpoint..."

    # Remove old game if present
    local old_game_path="$ports_path/$OLD_GAME_ID"
    local old_launcher_path="$ports_path/$OLD_LAUNCHER"
    if [ -d "$old_game_path" ] || [ -f "$old_launcher_path" ]; then
        info "Removing old game ($OLD_GAME_ID)..."
        rm -rf "$old_game_path"
        rm -f "$old_launcher_path"
    fi

    # Create directory structure
    mkdir -p "$game_path"

    # Copy .love bundle
    cp "$PROJECT_DIR/$LOVE_FILE" "$game_path/$LOVE_FILE"
    info "Copied $LOVE_FILE → $game_path/"

    # Copy launcher script
    cp "$PROJECT_DIR/$LAUNCHER" "$ports_path/$LAUNCHER"
    chmod +x "$ports_path/$LAUNCHER" 2>/dev/null || true  # chmod may fail on SMB
    info "Copied launcher → $ports_path/"

    # Copy cover art for EmulationStation
    if [ -f "$PROJECT_DIR/cover.png" ]; then
        cp "$PROJECT_DIR/cover.png" "$game_path/cover.png"
        info "Copied cover.png → $game_path/"
    fi

    # Update gamelist.xml for EmulationStation
    update_gamelist_file "$ports_path/gamelist.xml"
    info "Updated gamelist.xml"

    # Sync to ensure writes are flushed
    sync 2>/dev/null || true

    echo ""
    info "Deployment complete! (method: ${DEPLOY_METHOD:-local SD card})"
    info "Game path: $game_path"
    info "Refresh gamelists in EmulationStation to see the game."
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

# Always package first
package_love

if [ "$PACKAGE_ONLY" = "true" ]; then
    info "Package-only mode — skipping deployment."
    exit 0
fi

# Find target and deploy
if [ -n "$MOUNTPOINT" ]; then
    # Explicit path provided — use it directly
    [ -d "$MOUNTPOINT" ] || error "Mount point does not exist: $MOUNTPOINT"
    deploy_local "$MOUNTPOINT" "$DRY_RUN"
else
    # Auto-detect: network share or SD card
    TARGET=$(find_target) || error "No deploy target found. Try one of:
  - Open Files and browse to smb://knulli.local (GVFS auto-mount)
  - Install smbclient for direct network deploy
  - Mount the TF2 SD card
  - Pass an explicit path: $(basename "$0") /path/to/card
  - Just package: $(basename "$0") --package-only"

    case "$TARGET" in
        gvfs:*)
            DEPLOY_METHOD="network via GVFS (smb://$SMB_HOST/$SMB_SHARE)"
            deploy_local "${TARGET#gvfs:}" "$DRY_RUN"
            ;;
        smb:*)
            deploy_smbclient "$DRY_RUN"
            ;;
        local:*)
            DEPLOY_METHOD="local SD card"
            deploy_local "${TARGET#local:}" "$DRY_RUN"
            ;;
    esac
fi
