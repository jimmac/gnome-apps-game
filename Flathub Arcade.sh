#!/bin/bash
# PORTMASTER: flathub-arcade.zip, Flathub Arcade.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Set up love runtime
source "$controlfolder/runtimes/love_11.5/love.txt"

# Variables
GAMEDIR="/$directory/ports/flathub-arcade"

cd $GAMEDIR

# Assign gptokeyb
$GPTOKEYB "$LOVE_GPTK" &

# Run the game
$LOVE_RUN "$GAMEDIR/flathub-arcade.love"

# Cleanup
pm_finish
