#!/bin/bash

echo "🔧 QUICK FIX: OpenSSL Utils memcpy Error"
echo "========================================"
echo ""

echo "Fixing missing header issue that causes:"
echo "  error: no member named 'memcpy' in namespace 'std'"
echo ""

# Handle sudo execution
if [ -n "$SUDO_USER" ]; then
    OSQUERY_PATH="/home/$SUDO_USER/osquery-build/osquery"
    echo "Detected sudo execution, using: $OSQUERY_PATH"
    cd "$OSQUERY_PATH"
else
    cd ~/osquery-build/osquery
fi

echo "Working directory: $(pwd)"
echo ""

# Find the problematic file
OPENSSL_FILE="osquery/tables/system/posix/openssl_utils.cpp"
echo "🔍 Fixing file: $OPENSSL_FILE"

if [ ! -f "$OPENSSL_FILE" ]; then
    echo "❌ File not found: $OPENSSL_FILE"
    exit 1
fi

echo ""
echo "🔧 Adding missing header..."

# Backup and fix the file
cp "$OPENSSL_FILE" "$OPENSSL_FILE.backup"

# Add the missing header after existing includes
sed -i '/#include.*<string/a #include <cstring>' "$OPENSSL_FILE"

echo "✅ Header fixed!"
echo ""
echo "🔨 Continuing build..."
cd build
make -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build completed successfully!"
else
    echo ""
    echo "❌ Build failed. Check output above for errors."
fi
