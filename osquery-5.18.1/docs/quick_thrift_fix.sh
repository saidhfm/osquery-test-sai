#!/bin/bash

echo "🔧 QUICK FIX: Thrift random_shuffle Conflict"
echo "============================================="
echo ""

echo "Fixing Thrift header conflict that causes:"
echo "  error: redefinition of 'random_shuffle'"
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

# Find the Thrift header
echo "🔍 Finding Thrift header..."
THRIFT_HEADER=$(find . -name "random_shuffle.h" -path "*/thrift/patches/*" | head -1)
echo "Found: $THRIFT_HEADER"

if [ -z "$THRIFT_HEADER" ]; then
    echo "❌ Thrift header not found!"
    echo "Make sure you've run cmake first to generate the build files."
    exit 1
fi

echo ""
echo "🔧 Applying the fix..."

# Backup and apply the fix
cp "$THRIFT_HEADER" "$THRIFT_HEADER.backup"
cat > "$THRIFT_HEADER" << 'EOF'
#pragma once
#ifndef OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#define OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#include <algorithm>
#include <random>
#if __cplusplus >= 201703L || !defined(__GLIBCXX__)
template<class RandomIt>
void random_shuffle(RandomIt first, RandomIt last) {
    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(first, last, g);
}
#endif
#endif
EOF

echo "✅ Thrift header fixed!"
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