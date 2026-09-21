# AgentRL image: Ubuntu 22.04 + IBM Velox libvelox.so + Gluten C++ + OpenCode.
# Publishes as ghcr.io/frankcyh/agentrl-image.

FROM ubuntu:22.04

LABEL org.opencontainers.image.source=https://github.com/FrankCyh/agentrl-image
LABEL org.opencontainers.image.description="Velox + Gluten C++ + OpenCode for Agent RL"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND="noninteractive"
ARG tz="Etc/UTC"
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND} \
    TZ=${tz} \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_INSTALL_DIR=/usr/local/bin

RUN apt-get update && \
    apt-get install -y sudo lsb-release pip python3 curl ca-certificates git patchelf && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    dpkg --print-architecture | grep -qx arm64

ARG VELOX_GIT_URL=https://github.com/IBM/velox.git
ARG VELOX_GIT_TAG=gluten-1.7.0-dft
RUN git clone --depth 1 --branch "${VELOX_GIT_TAG}" "${VELOX_GIT_URL}" /velox

WORKDIR /velox
# gcc-11 + generic march (not gcc-12 / SVE). Shared Folly so Gluten links
# PIC gflags. glog 0.6 from source, never jammy 0.4.
ENV ARM_BUILD_TARGET=generic \
    PROMPT_ALWAYS_RESPOND=n \
    CCACHE_DISABLE=1 \
    VELOX_BUILD_SHARED=ON \
    LD_LIBRARY_PATH=/usr/local/lib
RUN sed -i '/^if lscpu | grep -q "sve"; then$/,/^fi$/d' /velox/scripts/setup-ubuntu.sh

# Velox setup-ubuntu.sh, but apt glog 0.4 is omitted and install_glog (0.6)
# runs before Folly/fizz. install_arrow is not called (bundled Arrow EP).
RUN /velox/scripts/setup-ubuntu.sh install_build_prerequisites && \
    apt-get install -y \
      libc-ares-dev \
      libcurl4-openssl-dev \
      libssl-dev \
      libicu-dev \
      libdouble-conversion-dev \
      libbz2-dev \
      libgflags-dev \
      libgtest-dev \
      libgmock-dev \
      libevent-dev \
      liblz4-dev \
      libzstd-dev \
      libre2-dev \
      libsnappy-dev \
      libsodium-dev \
      libelf-dev \
      libdwarf-dev \
      bison \
      flex \
      libfl-dev \
      tzdata \
      libxxhash-dev && \
    /velox/scripts/setup-ubuntu.sh \
      install_fmt \
      install_protobuf \
      install_grpc \
      install_boost \
      install_fast_float \
      install_glog \
      install_folly \
      install_fizz \
      install_wangle \
      install_mvfst \
      install_fbthrift \
      install_conda \
      install_duckdb \
      install_stemmer \
      install_xsimd \
      install_simdjson \
      install_geos \
      install_s2geometry \
      install_faiss && \
    ldconfig && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    test -s /usr/local/lib/libglog.so && \
    test -s /usr/local/lib/libfolly.so && \
    test -s /usr/local/lib/libfizz.a && \
    ! nm -C /usr/local/lib/libfizz.a | grep -q kLogSiteUninitialized

ENV VELOX_DEPENDENCY_SOURCE=BUNDLED \
    Boost_SOURCE=SYSTEM \
    ICU_SOURCE=SYSTEM \
    folly_SOURCE=SYSTEM \
    gflags_SOURCE=SYSTEM \
    glog_SOURCE=SYSTEM \
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

ARG NUM_THREADS=20
ARG MAX_LINK_JOBS=12
ENV NUM_THREADS=${NUM_THREADS} MAX_LINK_JOBS=${MAX_LINK_JOBS}

# Bundled Arrow EP: Gluten needs parquet + filesystem headers.
RUN sed -i \
      -e 's/-DARROW_DEPENDENCY_SOURCE=AUTO/-DARROW_DEPENDENCY_SOURCE=BUNDLED/' \
      -e 's/-DARROW_PARQUET=OFF/-DARROW_PARQUET=ON\n      -DARROW_FILESYSTEM=ON/' \
      CMake/resolve_dependency_modules/arrow/CMakeLists.txt && \
    make release NUM_THREADS="${NUM_THREADS}" MAX_LINK_JOBS="${MAX_LINK_JOBS}" \
      VELOX_BUILD_TESTING=OFF \
      TREAT_WARNINGS_AS_ERRORS=0 \
      EXTRA_CMAKE_FLAGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DVELOX_BUILD_SHARED=ON -DVELOX_ENABLE_ARROW=ON -DArrow_SOURCE=BUNDLED" && \
    test -s /velox/_build/release/lib/libvelox.so && \
    test -f /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/include/arrow/filesystem/filesystem.h && \
    { test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib/libarrow_bundled_dependencies.a || \
      test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib64/libarrow_bundled_dependencies.a; } && \
    python3 -c 'import ctypes; ctypes.CDLL("/velox/_build/release/lib/libvelox.so")'

ENV VELOX_HOME=/velox \
    VELOX_BUILD_DIR=/velox/_build/release \
    VELOX_LIB_DIR=/velox/_build/release/lib \
    GLUTEN_HOME=/opt/gluten-1.7.0 \
    GLUTEN_INCLUDE_DIR=/opt/gluten-1.7.0/cpp/velox \
    GLUTEN_LIB_DIR=/opt/gluten-1.7.0/cpp/build/releases \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64 \
    LD_LIBRARY_PATH=/velox/_build/release/lib:/opt/gluten-1.7.0/cpp/build/releases:/usr/local/lib

RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-11-jdk nlohmann-json3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    test -x "${JAVA_HOME}/bin/java"

ARG GLUTEN_TARBALL_URL=https://github.com/apache/gluten/archive/refs/tags/v1.7.0.tar.gz
RUN curl -fL --retry 5 --retry-delay 2 -o /tmp/gluten-1.7.0.tar.gz "${GLUTEN_TARBALL_URL}" && \
    mkdir -p /opt/gluten-1.7.0 && \
    tar -xzf /tmp/gluten-1.7.0.tar.gz --strip-components=1 -C /opt/gluten-1.7.0 && \
    rm -f /tmp/gluten-1.7.0.tar.gz && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/Udf.h && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/Udaf.h && \
    test -f /opt/gluten-1.7.0/cpp/velox/udf/examples/UdfCommon.h

# Gluten CMake imports libvelox.a; this image builds a shared IBM engine.
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

# Backend file stays …/releases/libvelox.so (Gluten JNI path). Distinct SONAME
# so DT_NEEDED libvelox.so resolves to the IBM engine.
RUN patchelf --set-soname libgluten_velox.so \
      /opt/gluten-1.7.0/cpp/build/releases/libvelox.so && \
    ln -s libvelox.so /opt/gluten-1.7.0/cpp/build/releases/libgluten_velox.so

WORKDIR /velox
CMD ["/bin/bash"]
