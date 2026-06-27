#!/bin/bash

# BeamMP Launcher builder for Linux (works on general systems, uses distrobox)
#
# What this does:
#   1. Makes sure distrobox is available, creating an Arch distrobox if needed.
#   2. Builds the BeamMP Launcher inside that distrobox (all deps stay inside it).
#   3. Instead of a BeamMP.sh script, it installs a "BeamMP" .desktop entry that
#      launches the launcher and reuses BeamNG.drive's icon, so you can start it
#      straight from your application menu, just like on Windows.
#
# Because the launcher is built inside the Arch distrobox and dynamically links
# against that container's libraries, the .desktop entry runs it back inside the
# distrobox. That is what makes it work on any distro instead of only Bazzite.

DISTROBOX_NAME="arch"
BEAMNG_APPID=284160

# --- helpers ---------------------------------------------------------------

# GUI notifications with a plain-terminal fallback (zenity is optional).
notify_info() {
    if command -v zenity >/dev/null 2>&1; then
        zenity --info --text="$1" 2>/dev/null || echo "$1"
    else
        echo "$1"
    fi
}

notify_error() {
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --text="$1" 2>/dev/null || echo "ERROR: $1" >&2
    else
        echo "ERROR: $1" >&2
    fi
}

# Locate BeamNG.drive's Steam icon and copy it to a stable path, printing that
# path. Handles native/Flatpak/Snap Steam installs and both the old (flat) and
# new (per-appid folder) librarycache layouts. Falls back to the themed icon
# name "steam_icon_<appid>" if no cached image can be found.
find_beamng_icon() {
    local dest_dir="$HOME/.local/share/icons"
    local roots=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )
    local r lc f ext oext
    mkdir -p "$dest_dir" 2>/dev/null || true

    for r in "${roots[@]}"; do
        lc="$r/appcache/librarycache"
        [ -d "$lc" ] || continue

        # (A) Old flat layout: <appid>_icon.jpg / .png
        for ext in jpg png; do
            f="$lc/${BEAMNG_APPID}_icon.$ext"
            if [ -f "$f" ] && cp -f "$f" "$dest_dir/beammp.$ext" 2>/dev/null; then
                echo "$dest_dir/beammp.$ext"
                return 0
            fi
        done

        # (B) New per-appid folder with hash-named files: the app icon is the
        #     smallest image in the folder, so pick that.
        if [ -d "$lc/$BEAMNG_APPID" ]; then
            f=$(find "$lc/$BEAMNG_APPID" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) \
                  -printf '%s %p\n' 2>/dev/null | sort -n | head -n1 | cut -d' ' -f2-) || f=""
            if [ -n "$f" ] && [ -f "$f" ]; then
                oext="${f##*.}"
                if cp -f "$f" "$dest_dir/beammp.$oext" 2>/dev/null; then
                    echo "$dest_dir/beammp.$oext"
                    return 0
                fi
            fi
        fi
    done

    # (C) If Steam installed hicolor theme icons (from a desktop shortcut),
    #     just reference the themed name so the DE picks the best size.
    # (D) Fallback to the same themed name even if it is not present yet.
    echo "steam_icon_${BEAMNG_APPID}"
    return 0
}

# --- prerequisites ---------------------------------------------------------

if command -v distrobox >/dev/null 2>&1; then
    echo "distrobox is installed."
else
    notify_error "distrobox is not installed. Please install it first (https://distrobox.it)."
    exit 1
fi

set -e  # Exit on any error from here on

# --- distrobox -------------------------------------------------------------

echo "Checking for existing Arch distrobox..."

if distrobox list | grep -q "^${DISTROBOX_NAME}\b"; then
    echo "Arch distrobox '${DISTROBOX_NAME}' already exists."
else
    echo "Creating new Arch distrobox '${DISTROBOX_NAME}'..."
    distrobox create --name "${DISTROBOX_NAME}" --image archlinux:latest
    echo "Arch distrobox created successfully."
fi

echo "Entering distrobox and building BeamMP Launcher..."
cd

# Execute the build commands inside the distrobox
distrobox enter "${DISTROBOX_NAME}" -- bash -c "
    set -e
    echo 'Installing dependencies...'
    sudo pacman -Syu libnewt base-devel git curl zip unzip tar cmake ninja --noconfirm

    echo 'Cloning and setting up vcpkg...'
    if [ ! -d \"vcpkg\" ]; then
        git clone https://github.com/microsoft/vcpkg.git
    fi
    cd vcpkg
    ./bootstrap-vcpkg.sh --disableMetrics
    export VCPKG_ROOT=\"\$HOME/vcpkg\"
    export PATH=\"\$VCPKG_ROOT:\$PATH\"

    echo 'Cloning BeamMP Launcher...'
    cd \$HOME
    if [ ! -d \"BeamMP-Launcher\" ]; then
        git clone --recurse-submodules https://github.com/BeamMP/BeamMP-Launcher.git
    fi

    echo 'Building BeamMP Launcher...'
    cd BeamMP-Launcher
    cmake -DCMAKE_BUILD_TYPE=Release . -B bin -DCMAKE_TOOLCHAIN_FILE=\"\$HOME/vcpkg/scripts/buildsystems/vcpkg.cmake\" -DVCPKG_TARGET_TRIPLET=x64-linux
    cmake --build bin --parallel --config Release

    echo 'Build completed successfully!'
"

# --- desktop launcher ------------------------------------------------------

APPS_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/beammp-launch.sh"
DESKTOP_FILE="$APPS_DIR/beammp.desktop"

mkdir -p "$APPS_DIR" "$BIN_DIR"

# The app menu may not have distrobox on its PATH, so resolve it now.
DISTROBOX_BIN="$(command -v distrobox || echo distrobox)"

# Wrapper that runs the launcher INSIDE the distrobox it was built in, so its
# libraries are present regardless of the host distro. Keeping the real command
# in a wrapper also avoids .desktop Exec= quoting pitfalls.
cat > "$WRAPPER" <<EOF
#!/bin/bash
exec "${DISTROBOX_BIN}" enter --name "${DISTROBOX_NAME}" -- bash -lc 'cd "\$HOME/BeamMP-Launcher/bin" && exec ./BeamMP-Launcher'
EOF
chmod +x "$WRAPPER"

# Reuse BeamNG.drive's icon (or fall back to the themed Steam icon name).
ICON_VALUE="$(find_beamng_icon)"

# Desktop entry: shows up in the application menu as "BeamMP" with BeamNG's icon.
# Terminal=true because the launcher is a console app that must stay open while
# you play.
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=BeamMP
GenericName=BeamMP Multiplayer Launcher
Comment=Launch BeamMP multiplayer for BeamNG.drive (runs in a distrobox)
Exec=${WRAPPER}
Icon=${ICON_VALUE}
Terminal=true
Categories=Game;Simulation;
Keywords=BeamMP;BeamNG;Multiplayer;
StartupNotify=false
EOF
chmod +x "$DESKTOP_FILE"

# Refresh the application menu database (best effort).
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

notify_info "BeamMP has been built successfully! You can now launch it from your application menu (search for \"BeamMP\"). Make sure BeamNG.drive is installed via Steam first."
