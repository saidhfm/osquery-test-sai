#!/bin/bash

echo "🔧 FIXING OSQUERY BUILD FOR PROCESS ANCESTRY"
echo "============================================="
echo ""

echo "The error occurred because CMake tried to build eBPF components."
echo "Our implementation uses audit + /proc + caching (NOT eBPF)."
echo ""

echo "📋 Step 1: Clean previous build..."
cd ~/osquery-build/osquery
rm -rf build
mkdir build && cd build

echo "✅ Build directory cleaned"
echo ""

echo "📋 Step 2: Fix libaudit header conflict..."
HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)
if [ -n "$HEADER" ]; then
    echo "Found and fixing libaudit header: $HEADER"
    cp "$HEADER" "$HEADER.backup"
    sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$HEADER"
    echo -e '\n#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif' >> "$HEADER"
    echo "✅ libaudit header fixed"
else
    echo "⚠️ libaudit header not found - may not be needed"
fi

echo ""
echo "📋 Step 3: Fix Thrift random_shuffle conflict..."
THRIFT_HEADER=$(find . -name "random_shuffle.h" -path "*/thrift/patches/*" | head -1)
if [ -n "$THRIFT_HEADER" ]; then
    echo "Found and fixing Thrift header: $THRIFT_HEADER"
    cp "$THRIFT_HEADER" "$THRIFT_HEADER.backup"
    cat > "$THRIFT_HEADER" << 'THRIFT_FIX_EOF'
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
THRIFT_FIX_EOF
    echo "✅ Thrift header fixed"
else
    echo "⚠️ Thrift header not found - will be checked during build"
fi

echo ""
echo "📋 Step 4: Fix OpenSSL utils missing header..."
OPENSSL_FILE="osquery/tables/system/posix/openssl_utils.cpp"
if [ -f "$OPENSSL_FILE" ]; then
    echo "Found and fixing OpenSSL file: $OPENSSL_FILE"
    cp "$OPENSSL_FILE" "$OPENSSL_FILE.backup"
    sed -i '/#include.*<string/a #include <cstring>' "$OPENSSL_FILE"
    echo "✅ OpenSSL utils header fixed"
else
    echo "⚠️ OpenSSL utils file not found - will be checked during build"
fi

echo ""
echo "📋 Step 5: Fix sysctl header missing..."
SYSCTL_HEADER=$(find . -name "sysctl_utils.h" -path "*/posix/*" | head -1)
if [ -n "$SYSCTL_HEADER" ]; then
    echo "Found and fixing sysctl header: $SYSCTL_HEADER"
    cp "$SYSCTL_HEADER" "$SYSCTL_HEADER.backup"
    sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\n#include <unistd.h>\n#include <fcntl.h>\n#ifndef CTL_MAXNAME\n#define CTL_MAXNAME 24\n#endif\n#ifndef CTL_DEBUG\n#define CTL_DEBUG 5\n#endif\n#else\n#include <sys/sysctl.h>\n#endif|' "$SYSCTL_HEADER"
    echo "✅ sysctl header fixed"
else
    echo "⚠️ sysctl header not found - will be checked during build"
fi

echo ""
echo "📋 Step 6: Configure CMake WITHOUT eBPF..."
cmake \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_BPF=OFF \
  -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=ON \
  -DOSQUERY_BUILD_DPKG=ON \
  ..

if [ $? -ne 0 ]; then
    echo "❌ CMake configuration failed"
    exit 1
fi

echo "✅ CMake configured successfully (eBPF disabled, Clang enabled)"
echo ""

echo "📋 Step 7: Building osquery (this may take 30-45 minutes)..."
echo "Our process ancestry code will be included automatically."
echo ""

make -j$(nproc)

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "==================="
    echo ""
    echo "✅ osquery built with Process Ancestry support"
    echo "✅ eBPF components skipped (not needed)"
    echo "✅ Audit + /proc + caching implementation included"
    echo ""
    echo "📍 Binary location: $(pwd)/osquery/osqueryd"
    echo ""
    echo "🧪 Quick test:"
    echo "./osquery/osqueryi --version"
    echo ""
    echo "🔍 Verify ancestry column exists:"
    echo "./osquery/osqueryi \"SELECT name FROM pragma_table_info('process_events') WHERE name = 'ancestry';\""
    echo ""
    echo "🚀 Ready for testing!"
else
    echo ""
    echo "❌ BUILD FAILED"
    echo "==============="
    echo ""
    echo "Please check the error messages above."
    echo "Most common issues:"
    echo "1. Missing development packages"
    echo "2. Insufficient disk space"
    echo "3. Memory constraints"
    echo ""
    echo "Try: sudo apt-get install -y build-essential cmake git"
    exit 1
fi
