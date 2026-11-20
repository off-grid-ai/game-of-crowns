#!/bin/bash
# Build Node (the desktop's version) for Android arm64 with the NDK, using Node's own android-configure.
# Output: ~/goc-android/node26/node (an executable; ship it as lib/arm64-v8a/libnode_exec.so).
set -euo pipefail
V=v26.13.0
W=~/goc-android/node26; mkdir -p $W; cd $W
NDK=~/Android/Sdk/ndk/30.0.16248370
[ -f node.tar.xz ] || curl -fsSL -o node.tar.xz https://nodejs.org/dist/$V/node-$V.tar.xz
rm -rf src; mkdir src; tar xf node.tar.xz -C src --strip-components=1; cd src
echo "=== configure $(date +%T)"
# Node's own Android cross setup: apply its patch, then configure (NDK, API level, arch).
./android-configure patch
# OpenSSL calls android_getCpuFeatures on Android; it lives in the NDK's cpufeatures source, not a library.
CF=$NDK/sources/android/cpufeatures
cp $CF/cpu-features.c $CF/cpu-features.h deps/openssl/
sed -i "0,/'type': '<(library)',/s##'type': '<(library)',\n      'sources': ['cpu-features.c'],#" deps/openssl/openssl.gyp
grep -n "cpu-features" deps/openssl/openssl.gyp
# Build-time tools (torque, mksnapshot...) run here, so they need this machine's compiler,
# not the NDK's (android-configure leaves the host compiler pointing at the NDK).
export CC_host=gcc CXX_host=g++ AR_host=ar LINK_host=g++
./android-configure $NDK 28 arm64 > ../configure.log 2>&1 || { tail -20 ../configure.log; exit 1; }
echo "=== make $(date +%T)"
make -j12 > ../make.log 2>&1 || { grep -m30 -B3 -A3 -E "error:|\*\*\*" ../make.log; exit 1; }
cp out/Release/node $W/node
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip $W/node
file $W/node; ls -la $W/node
echo "=== done $(date +%T)"
