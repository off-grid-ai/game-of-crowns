// Runs Node as its own process on Android. nodejs-mobile ships Node as libnode.so, a library,
// and Android only runs programs from the app's native library folder. Ship this as
// lib/arm64-v8a/libnodemain.so beside libnode.so and libc++_shared.so, then start it with
// OS.create_process(<native lib dir>/libnodemain.so, [app.js]). Build (NDK r28, nodejs-mobile 18.20.4):
//   $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang++ -std=c++17 \
//     -Iinclude/node node-launcher.cc -Lbin/arm64-v8a -lnode -Wl,-rpath,'$ORIGIN' -o libnodemain.so
#include "node.h"
int main(int argc, char** argv) { return node::Start(argc, argv); }
