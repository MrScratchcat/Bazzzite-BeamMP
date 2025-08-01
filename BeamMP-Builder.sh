#!/bin/bash

# Script to set up BeamMP Launcher in Arch distrobox
# This script checks for an existing Arch distrobox, creates one if needed,
# and builds BeamMP Launcher with all dependencies

if command -v distrobox &> /dev/null; then
    echo "distrobox is installed."
else
    zenity --error --text="distrobox is not installed. Please install it first." || echo "distrobox is not installed. Please install it first."
    exit 1
fi

set -e  # Exit on any error

DISTROBOX_NAME="arch"

echo "Checking for existing Arch distrobox..."

# Check if distrobox exists
if distrobox list | grep -q "^${DISTROBOX_NAME}"; then
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

echo "#!/bin/bash" > ${HOME}/BeamMP.sh
echo "cd ${HOME}/BeamMP-Launcher/bin/ && ./BeamMP-Launcher" >> ${HOME}/BeamMP.sh
chmod +x BeamMP.sh
zenity --info --text="BeamMP Launcher has been built successfully and is ready to use. To launch it, run ${HOME}/BeamMP.sh or go to ${HOME}/BeamMP-Launcher/bin/ and run ./BeamMP-Launcher" || echo "BeamMP Launcher has been built successfully and is ready to use."
