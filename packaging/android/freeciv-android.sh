#!/bin/bash
# Cross-compile freeciv-server 3.2.6 for Android arm64 (static deps) with NDK 28.
set -euo pipefail
W=~/goc-android/fcbuild; mkdir -p $W/src $W/prefix; cd $W/src
NDK=~/Android/Sdk/ndk/28.1.13356709; API=28
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
export CC=$TC/aarch64-linux-android$API-clang CXX=$TC/aarch64-linux-android$API-clang++ AR=$TC/llvm-ar RANLIB=$TC/llvm-ranlib STRIP=$TC/llvm-strip
P=$W/prefix; HOST=aarch64-linux-android
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig PKG_CONFIG_PATH=$P/lib/pkgconfig
J=24
step(){ echo "=== $1 $(date +%T)"; }

if [ ! -f $P/lib/libsqlite3.a ]; then
step sqlite
[ -f sqlite.tgz ] || curl -fsSL -o sqlite.tgz https://www.sqlite.org/2024/sqlite-autoconf-3460100.tar.gz
rm -rf sqlite-autoconf-3460100; tar xf sqlite.tgz; cd sqlite-autoconf-3460100
./configure --host=$HOST --prefix=$P --disable-shared --enable-static --disable-readline >/dev/null
make -j$J >/dev/null && make install >/dev/null; cd ..
fi

if [ ! -f $P/lib/libcurl.a ]; then
step curl
[ -f curl.tgz ] || curl -fsSL -o curl.tgz https://curl.se/download/curl-8.10.1.tar.gz
rm -rf curl-8.10.1; tar xf curl.tgz; cd curl-8.10.1
./configure --host=$HOST --prefix=$P --disable-shared --enable-static --without-ssl --without-libpsl --without-zstd --without-brotli --without-nghttp2 --without-libidn2 --disable-ldap --disable-manual >/dev/null
make -j$J >/dev/null && make install >/dev/null; cd ..
fi

if [ ! -f $P/lib/libzstd.a ]; then
step zstd
[ -f zstd.tgz ] || curl -fsSL -o zstd.tgz https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz
rm -rf zstd-1.5.6; tar xf zstd.tgz; cd zstd-1.5.6/lib
make -j$J libzstd.a CC=$CC AR=$AR >/dev/null && make install-static install-includes install-pc PREFIX=$P >/dev/null; cd ../..
fi

if [ ! -f $P/lib/libicuuc.a ]; then
step icu-host
[ -f icu.tgz ] || curl -fsSL -o icu.tgz https://github.com/unicode-org/icu/releases/download/release-75-1/icu4c-75_1-src.tgz
rm -rf icu icu-host icu-android; tar xf icu.tgz
mkdir icu-host; (cd icu-host && env CC=gcc CXX=g++ AR=ar RANLIB=ranlib ../icu/source/runConfigureICU Linux --disable-tests --disable-samples >/dev/null && make -j$J >/dev/null)
step icu-android
mkdir icu-android; cd icu-android
../icu/source/configure --host=$HOST --prefix=$P --with-cross-build=$W/src/icu-host --disable-shared --enable-static --disable-tests --disable-samples --disable-tools --disable-extras --with-data-packaging=static >/dev/null
make -j$J >/dev/null && make install >/dev/null; cd ..
fi

step freeciv
rm -rf freeciv-3.2.6; tar xf ~/goc-android/fc.tar.xz; cd freeciv-3.2.6
export LIBS="-licudata -lc++_static -lc++abi -lm" LDFLAGS="-L$P/lib" CPPFLAGS="-I$P/include"
./configure --build=x86_64-pc-linux-gnu --host=$HOST --prefix=$P/fc --disable-client --enable-fcmp=no --disable-nls --without-readline --without-libbz2 --without-liblzma --with-libzstd --enable-static --disable-shared --with-sqlite3-prefix=$P > ../fc-configure.log 2>&1 || { tail -30 ../fc-configure.log; exit 1; }
make -j$J > ../fc-make.log 2>&1 || { grep -m20 -B2 -A5 "error" ../fc-make.log; exit 1; }
cp server/freeciv-server $W/freeciv-server.arm64; $STRIP $W/freeciv-server.arm64
file $W/freeciv-server.arm64; ls -la $W/freeciv-server.arm64
step done
