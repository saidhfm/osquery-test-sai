#!/bin/bash

# Complete Build and Package Script for osquery Process Ancestry Sensor
# This script builds osquery and creates a DEB package in one go

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

echo "🚀 Complete osquery Process Ancestry Sensor Build & Package"
echo "==========================================================="

# Check if we're on Ubuntu/Debian
if ! command -v dpkg-deb &> /dev/null; then
    echo "❌ Error: This script requires dpkg-deb (Ubuntu/Debian system)"
    exit 1
fi

# Install build dependencies if needed
echo "📋 Checking build dependencies..."
MISSING_DEPS=()

if ! command -v cmake &> /dev/null; then
    MISSING_DEPS+=("cmake")
fi

if ! command -v clang &> /dev/null; then
    MISSING_DEPS+=("clang")
fi

if ! command -v clang++ &> /dev/null; then
    MISSING_DEPS+=("clang++")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "📦 Installing missing dependencies: ${MISSING_DEPS[*]}"
    sudo apt update
    sudo apt install -y cmake clang clang++ libc++-dev libc++abi-dev build-essential git python3 pkg-config ninja-build
fi

# Build osquery if not already built
if [ ! -f "$BUILD_DIR/osquery/osqueryd" ]; then
    echo "🔨 Building osquery with process ancestry support..."
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with optimized settings
    cmake \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DOSQUERY_BUILD_BPF=OFF \
        -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
        -DOSQUERY_BUILD_TESTS=OFF \
        -DOSQUERY_BUILD_AWS=OFF \
        -DOSQUERY_BUILD_DPKG=ON \
        ..
    
    # Build with all available cores
    make -j$(nproc)
    
    echo "✅ osquery build completed!"
else
    echo "✅ osquery already built, skipping build step"
fi

# Verify binaries exist
if [ ! -f "$BUILD_DIR/osquery/osqueryd" ] || [ ! -f "$BUILD_DIR/osquery/osqueryi" ]; then
    echo "❌ Error: osquery binaries not found after build"
    exit 1
fi

# Strip binaries to reduce size
echo "🪓 Stripping binaries to reduce package size..."
strip "$BUILD_DIR/osquery/osqueryd"
strip "$BUILD_DIR/osquery/osqueryi"

# Create DEB package
echo "📦 Creating DEB package..."
cd "$SCRIPT_DIR"
chmod +x create_deb_package.sh
./create_deb_package.sh

echo ""
echo "🎉 Complete build and packaging finished successfully!"
echo ""
echo "📁 Files created:"
ls -lh packaging/*.deb packaging/*.md5 packaging/*.sha256

echo ""
echo "🧪 Quick Test (optional):"
echo "   sudo dpkg -i packaging/osquery-ancestry-sensor_*.deb"
echo "   sudo cp /etc/osquery/osquery.conf.example /etc/osquery/osquery.conf"
echo "   sudo systemctl start osqueryd"
echo "   sudo osqueryi \"SELECT COUNT(*) FROM process_events;\""
