# AgentRL image: Ubuntu 22.04 + IBM Velox libvelox.so + Gluten C++ + OpenCode.
# Publishes as ghcr.io/frankcyh/agentrl-image.

FROM ubuntu:22.04

LABEL org.opencontainers.image.source=https://github.com/FrankCyh/agentrl-image
LABEL org.opencontainers.image.description="Velox + Gluten C++ + OpenCode for Agent RL"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

#
# Bootstrap
# git/curl to fetch Velox. DEBIAN_FRONTEND and TZ stop tzdata from prompting.
# uv paths match Velox’s ubuntu-22.04-cpp.dockerfile so setup-ubuntu.sh installs cmake on PATH.
#
ARG DEBIAN_FRONTEND="noninteractive"
ARG tz="Etc/UTC"
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND} \
    TZ=${tz} \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_INSTALL_DIR=/usr/local/bin

RUN apt-get update && \
    apt-get install -y sudo lsb-release pip python3 curl ca-certificates git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    dpkg --print-architecture | grep -qx arm64

#
# IBM Velox gluten-1.7.0-dft at /velox.
# Arrow cmake patches live in-tree; Gluten Arrow EP uses that tree (not setup-ubuntu install_arrow).
#
ARG VELOX_GIT_URL=https://github.com/IBM/velox.git
ARG VELOX_GIT_TAG=gluten-1.7.0-dft
RUN git clone --depth 1 --branch "${VELOX_GIT_TAG}" "${VELOX_GIT_URL}" /velox

WORKDIR /velox
# Spark CPUs advertise SVE. setup-ubuntu.sh then apt-installs gcc-12 before
# apt update (and this image uses system gcc-11 / make release, not gcc-12).
# get-velox.sh also drops install_arrow so Gluten uses Velox’s bundled arrow_ep.
# ARM_BUILD_TARGET skips Grace sve2 in get_cxx_flags (no make sve_build).
ENV ARM_BUILD_TARGET=generic \
    PROMPT_ALWAYS_RESPOND=n
RUN python3 <<'PY'
from pathlib import Path

p = Path("/velox/scripts/setup-ubuntu.sh")
t = p.read_text()
old = """if lscpu | grep -q "sve"; then
  $SUDO apt install -y gcc-12 g++-12
fi
"""
if old not in t:
    raise SystemExit("sve gcc-12 block not found")
t = t.replace(old, "", 1)
arrow = "  run_and_time install_arrow\n"
if arrow not in t:
    raise SystemExit("install_arrow line not found")
t = t.replace(arrow, "", 1)
p.write_text(t)
PY

RUN /bin/bash -o pipefail /velox/scripts/setup-ubuntu.sh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Stash gflags so bundled CMake does not download it at configure time (same as upstream).
RUN mkdir -p /velox/deps-sources && \
    curl -fsSL --retry 5 --retry-delay 2 -o /velox/deps-sources/gflags-v2.3.0.tar.gz \
      https://github.com/gflags/gflags/archive/refs/tags/v2.3.0.tar.gz

#
# IBM Velox (default make release, plus shared + Arrow EP)
# System gcc (11 on Jammy). *_SOURCE=SYSTEM for libs setup-ubuntu.sh already
# installed; Arrow stays BUNDLED so Gluten finds libarrow_bundled_dependencies.a under
# _build/release/CMake/resolve_dependency_modules/arrow/arrow_ep.
#
ENV VELOX_DEPENDENCY_SOURCE=BUNDLED \
    Boost_SOURCE=SYSTEM \
    ICU_SOURCE=SYSTEM \
    folly_SOURCE=SYSTEM \
    fmt_SOURCE=SYSTEM \
    simdjson_SOURCE=SYSTEM \
    xsimd_SOURCE=SYSTEM \
    stemmer_SOURCE=SYSTEM \
    DuckDB_SOURCE=SYSTEM \
    faiss_SOURCE=SYSTEM \
    Arrow_SOURCE=BUNDLED \
    geos_SOURCE=SYSTEM \
    s2geometry_SOURCE=SYSTEM \
    Protobuf_SOURCE=SYSTEM \
    CMAKE_POLICY_VERSION_MINIMUM=3.5

ARG NUM_THREADS=16
ARG MAX_LINK_JOBS=8
ENV NUM_THREADS=${NUM_THREADS} MAX_LINK_JOBS=${MAX_LINK_JOBS}

RUN if ! grep -q 'CMAKE_POLICY_VERSION_MINIMUM' CMake/resolve_dependency_modules/glog.cmake; then \
      sed -i '/message(STATUS "Building glog from source")/i set(CMAKE_POLICY_VERSION_MINIMUM 3.5)' \
        CMake/resolve_dependency_modules/glog.cmake; \
    fi && \
    sed -i 's/-DARROW_DEPENDENCY_SOURCE=AUTO/-DARROW_DEPENDENCY_SOURCE=BUNDLED/' \
      CMake/resolve_dependency_modules/arrow/CMakeLists.txt && \
    make release NUM_THREADS="${NUM_THREADS}" MAX_LINK_JOBS="${MAX_LINK_JOBS}" \
      VELOX_BUILD_TESTING=OFF \
      TREAT_WARNINGS_AS_ERRORS=0 \
      EXTRA_CMAKE_FLAGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DVELOX_BUILD_SHARED=ON -DVELOX_ENABLE_ARROW=ON -DArrow_SOURCE=BUNDLED" && \
    test -s /velox/_build/release/lib/libvelox.so && \
    { test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib/libarrow_bundled_dependencies.a || \
      test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib64/libarrow_bundled_dependencies.a; }

# IBM Arrow EP defaults ARROW_FILESYSTEM=OFF / ARROW_PARQUET=OFF. Gluten's
# VeloxParquetDataSource.h includes arrow/filesystem/filesystem.h.
RUN python3 <<'PY'
from pathlib import Path

p = Path("/velox/CMake/resolve_dependency_modules/arrow/CMakeLists.txt")
t = p.read_text()
old = "-DARROW_PARQUET=OFF"
new = "-DARROW_PARQUET=ON\n      -DARROW_FILESYSTEM=ON"
if old not in t:
    raise SystemExit("ARROW_PARQUET=OFF not found")
p.write_text(t.replace(old, new, 1))
PY
RUN cmake /velox/_build/release && \
    cmake --build /velox/_build/release --target arrow_ep -j "${NUM_THREADS}" && \
    test -f /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/include/arrow/filesystem/filesystem.h

ENV VELOX_HOME=/velox \
    VELOX_BUILD_DIR=/velox/_build/release \
    VELOX_LIB_DIR=/velox/_build/release/lib \
    GLUTEN_HOME=/opt/gluten-1.7.0 \
    GLUTEN_INCLUDE_DIR=/opt/gluten-1.7.0/cpp/velox \
    GLUTEN_LIB_DIR=/opt/gluten-1.7.0/cpp/build/releases \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64 \
    LD_LIBRARY_PATH=/velox/_build/release/lib:/opt/gluten-1.7.0/cpp/build/releases:/usr/local/lib

#
# JDK 11 + nlohmann (UDFHello_test). JNI for Gluten cmake.
#
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-11-jdk nlohmann-json3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    test -x "${JAVA_HOME}/bin/java"

#
# Gluten v1.7.0 C++ (libgluten.so + backend libvelox.so)
# Import IBM engine libvelox.so instead of libvelox.a. No Spark-API rewriter.
#
ARG GLUTEN_TARBALL_URL=https://github.com/apache/gluten/archive/refs/tags/v1.7.0.tar.gz
RUN curl -fL --retry 5 --retry-delay 2 -o /tmp/gluten-1.7.0.tar.gz "${GLUTEN_TARBALL_URL}" && \
    mkdir -p /opt/gluten-1.7.0 && \
    tar -xzf /tmp/gluten-1.7.0.tar.gz --strip-components=1 -C /opt/gluten-1.7.0 && \
    rm -f /tmp/gluten-1.7.0.tar.gz && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/Udf.h && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/Udaf.h && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/examples/UdfCommon.h
RUN python3 <<'PY'
from pathlib import Path

p = Path("/opt/gluten-1.7.0/cpp/velox/CMakeLists.txt")
t = p.read_text()
old = "import_library(facebook::velox ${VELOX_BUILD_PATH}/lib/libvelox.a)"
new = """if(NOT EXISTS ${VELOX_BUILD_PATH}/lib/libvelox.so)
  message(FATAL_ERROR "IBM libvelox.so missing: ${VELOX_BUILD_PATH}/lib/libvelox.so")
endif()
add_library(facebook::velox SHARED IMPORTED)
set_target_properties(facebook::velox PROPERTIES IMPORTED_LOCATION ${VELOX_BUILD_PATH}/lib/libvelox.so)"""
if old not in t:
    raise SystemExit("facebook::velox import_library not found")
p.write_text(t.replace(old, new, 1))
PY
RUN cmake -S /opt/gluten-1.7.0/cpp -B /opt/gluten-1.7.0/cpp/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_VELOX_BACKEND=ON \
      -DVELOX_HOME=/velox \
      -DBUILD_TESTS=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_BENCHMARKS=OFF \
      -DENABLE_ENHANCED_FEATURES=OFF && \
    cmake --build /opt/gluten-1.7.0/cpp/build -j "${NUM_THREADS}" && \
    test -s /opt/gluten-1.7.0/cpp/build/releases/libgluten.so && \
    test -s /opt/gluten-1.7.0/cpp/build/releases/libvelox.so

LABEL org.opencontainers.image.description="IBM Velox + Gluten C++ + OpenCode for Agent RL"

#
# OpenCode
# Official linux-arm64 tarball; version and sha256 are build-args.
#
ARG OPENCODE_VERSION=1.18.23
ARG OPENCODE_SHA256=86d3afaf4e8784f9adab189be2a315c12b27ec40a04b70defbe70595c3cc7c65
ARG OPENCODE_URL=https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-arm64.tar.gz
RUN curl -fL --retry 5 --retry-delay 2 -o /tmp/opencode-linux-arm64.tar.gz "${OPENCODE_URL}" && \
    printf '%s  %s\n' "${OPENCODE_SHA256}" /tmp/opencode-linux-arm64.tar.gz | sha256sum -c - && \
    tar -xzf /tmp/opencode-linux-arm64.tar.gz --no-same-owner -C /tmp opencode && \
    install -m 0755 /tmp/opencode /usr/local/bin/opencode && \
    rm -f /tmp/opencode && \
    opencode --version && \
    rm -f /tmp/opencode-linux-arm64.tar.gz

# IBM libvelox.so can DT_NEED system libglog.so.0 and bundled libglog.so.1.
# Bundled glog 0.6 embeds gflags; loading it next to Velox’s static gflags
# aborts on FLAGS_flagfile. Keep system glog 0.4 only.
# Gluten backend is also named libvelox.so; give it a distinct SONAME so
# its DT_NEEDED libvelox.so resolves to the IBM engine.
RUN apt-get update && \
    apt-get install -y --no-install-recommends patchelf && \
    patchelf --remove-needed libglog.so.1 /velox/_build/release/lib/libvelox.so && \
    patchelf --set-soname libgluten_velox.so \
      /opt/gluten-1.7.0/cpp/build/releases/libvelox.so && \
    ln -s libvelox.so /opt/gluten-1.7.0/cpp/build/releases/libgluten_velox.so && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /velox
CMD ["/bin/bash"]
