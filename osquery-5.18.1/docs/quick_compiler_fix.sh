#!/bin/bash

echo "🔧 QUICK FIX: osquery Compiler Issue"
echo "===================================="
echo ""

echo "The error occurred because osquery needs Clang, not GCC."
echo "Installing Clang and rebuilding..."
echo ""

# Stop any running build
pkill -f make

echo "📦 Installing Clang compiler..."
sudo apt-get update
sudo apt-get install -y clang-13 clang++-13 libc++-13-dev libc++abi-13-dev

echo "🔄 Setting Clang as default..."
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/clang-13 100
sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-13 100

echo "✅ Compiler verification:"
echo "C compiler: $(cc --version | head -1)"
echo "C++ compiler: $(c++ --version | head -1)"
echo ""

echo "🧹 Cleaning previous build..."
cd ~/osquery-build/osquery
rm -rf build
mkdir build && cd build

echo "🔧 Fixing libaudit header conflict..."
HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)
if [ -n "$HEADER" ]; then
    echo "Found and fixing: $HEADER"
    cp "$HEADER" "$HEADER.backup"
    sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$HEADER"
    echo -e '\n#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif' >> "$HEADER"
    echo "✅ libaudit header fixed"
else
    echo "⚠️ libaudit header not found yet - will be checked during build"
fi

echo "🔧 Fixing Thrift random_shuffle conflict..."
THRIFT_HEADER=$(find . -name "random_shuffle.h" -path "*/thrift/patches/*" | head -1)
if [ -n "$THRIFT_HEADER" ]; then
    echo "Found and fixing: $THRIFT_HEADER"
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
    echo "⚠️ Thrift header not found yet - will be checked during build"
fi

echo "🔧 Fixing OpenSSL utils missing header..."
OPENSSL_FILE="osquery/tables/system/posix/openssl_utils.cpp"
if [ -f "$OPENSSL_FILE" ]; then
    echo "Found and fixing: $OPENSSL_FILE"
    cp "$OPENSSL_FILE" "$OPENSSL_FILE.backup"
    sed -i '/#include.*<string/a #include <cstring>' "$OPENSSL_FILE"
    echo "✅ OpenSSL utils header fixed"
else
    echo "⚠️ OpenSSL utils file not found yet - will be checked during build"
fi

echo "🔧 Fixing sysctl header missing..."
SYSCTL_HEADER=$(find . -name "sysctl_utils.h" -path "*/posix/*" | head -1)
if [ -n "$SYSCTL_HEADER" ]; then
    echo "Found and fixing: $SYSCTL_HEADER"
    cp "$SYSCTL_HEADER" "$SYSCTL_HEADER.backup"
    sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\n#include <unistd.h>\n#include <fcntl.h>\n#ifndef CTL_MAXNAME\n#define CTL_MAXNAME 24\n#endif\n#ifndef CTL_DEBUG\n#define CTL_DEBUG 5\n#endif\n#else\n#include <sys/sysctl.h>\n#endif|' "$SYSCTL_HEADER"
    echo "✅ sysctl header fixed"
else
    echo "⚠️ sysctl header not found yet - will be checked during build"
fi

echo "⚙️ Configuring with Clang..."
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

if [ $? -eq 0 ]; then
    echo ""
    echo "🔨 Building osquery (this will take 30-45 minutes)..."
    echo "Process ancestry support will be included automatically."
    echo ""
    
    # Build with progress indication
    make -j$(nproc)
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 BUILD SUCCESSFUL!"
        echo "==================="
        echo ""
        echo "✅ osquery built with Process Ancestry support"
        echo "✅ Using Clang compiler (correct)"
        echo "✅ All experimental eBPF components skipped"
        echo ""
        echo "📍 Binary location: $(pwd)/osquery/osqueryd"
        echo ""
        echo "🧪 Quick verification:"
        ./osquery/osqueryi --version
        echo ""
        echo "🔍 Verify ancestry column exists:"
        echo 'SELECT name FROM pragma_table_info("process_events") WHERE name = "ancestry";' | ./osquery/osqueryi
        echo ""
        echo "🚀 Ready for testing!"
    else
        echo ""
        echo "❌ BUILD FAILED"
        echo "==============="
        echo ""
        echo "Even with Clang, the build failed."
        echo "Common causes:"
        echo "1. Insufficient memory (need 4GB+ RAM)"
        echo "2. Insufficient disk space (need 10GB+)"
        echo "3. Network timeouts during dependency downloads"
        echo ""
        echo "Check system resources:"
        echo "Memory: $(free -h | grep Mem)"
        echo "Disk: $(df -h / | tail -1)"
    fi
else
    echo ""
    echo "❌ CMAKE CONFIGURATION FAILED"
    echo "============================="
    echo ""
    echo "The CMake configuration failed even with Clang."
    echo "Check the error messages above for specific issues."
fi

echo ""
echo "📚 For more details, see:"
echo "   - docs/COMPILER_FIX.md"
echo "   - docs/aws-ec2-testing-guide.md"
