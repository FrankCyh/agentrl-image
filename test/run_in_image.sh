#!/usr/bin/env bash
set -euo pipefail

ENGINE=/velox/_build/release/lib/libvelox.so
GLUTEN=/opt/gluten-1.7.0/cpp/build/releases/libgluten.so
BACKEND=/opt/gluten-1.7.0/cpp/build/releases/libvelox.so
test -s "$ENGINE"
test -s "$GLUTEN"
test -s "$BACKEND"

echo "=== backend must DT_NEED both gluten and IBM velox ==="
patchelf --print-needed "$BACKEND" | grep -qx libgluten.so
patchelf --print-needed "$BACKEND" | grep -qx libvelox.so
patchelf --print-soname "$BACKEND" | grep -qx libgluten_velox.so
patchelf --print-soname "$ENGINE" | grep -qx libvelox.so
ldd "$BACKEND" | grep -q /opt/gluten-1.7.0/cpp/build/releases/libgluten.so
ldd "$BACKEND" | grep -q /velox/_build/release/lib/libvelox.so
echo "PASS ldd backend -> libgluten.so + IBM libvelox.so"

CXXFLAGS="-std=gnu++20 -O2 -DNDEBUG -Wno-error -march=armv8-a+crc+crypto -fPIC"
GLUTEN_INC=/opt/gluten-1.7.0/cpp/velox
GLUTEN_CORE=/opt/gluten-1.7.0/cpp/core
GLUTEN_PROTO=/opt/gluten-1.7.0/cpp/build/core/proto
VELOX_LIB=/velox/_build/release/lib
GLUTEN_LIB=/opt/gluten-1.7.0/cpp/build/releases

echo "=== build hello_udf.so against IBM libvelox.so ==="
g++ $CXXFLAGS -shared \
  -I/velox -I/velox/_build/release -I"$GLUTEN_INC" \
  /test/hello_udf.cc -o /tmp/libhello_udf.so \
  -L"$VELOX_LIB" -lvelox -lfmt \
  -Wl,--allow-shlib-undefined -Wl,-rpath,"$VELOX_LIB"

echo "=== build joint test against gluten backend + gluten + IBM velox ==="
g++ $CXXFLAGS \
  -I/velox -I/velox/_build/release -I"$GLUTEN_INC" -I"$GLUTEN_CORE" -I"$GLUTEN_PROTO" \
  /test/gluten_velox_joint.cc -o /tmp/gluten_velox_joint \
  "$BACKEND" "$GLUTEN" "$ENGINE" -lfmt \
  -Wl,--allow-shlib-undefined \
  -Wl,-rpath,"$VELOX_LIB" -Wl,-rpath,"$GLUTEN_LIB"

echo "=== run ==="
/tmp/gluten_velox_joint /tmp/libhello_udf.so
