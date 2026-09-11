# AgentRL image: Ubuntu 22.04 + Facebook Velox libvelox.so + Gluten C++ + OpenCode.
# Publishes as ghcr.io/frankcyh/agentrl-image.
#
# VLA SVE1: -march=armv8-a+sve+crc+crypto (no -msve-vector-bits). Do not use make sve_build.
# Facebook VELOX_BUILD_SHARED=ON. Gluten Arrow EP is Velox’s bundled arrow_ep (not system Arrow).
ARG UBUNTU_TZDATA_VERSION=2026c-0ubuntu0.22.04.1
FROM ubuntu:22.04

LABEL org.opencontainers.image.source=https://github.com/FrankCyh/agentrl-image
LABEL org.opencontainers.image.description="Velox VLA SVE1 + Gluten C++ + OpenCode for Agent RL"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy
ARG NO_PROXY=localhost,127.0.0.1,::1
ARG no_proxy=localhost,127.0.0.1,::1
ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    NO_PROXY=${NO_PROXY} \
    no_proxy=${no_proxy}

ARG UBUNTU_TZDATA_VERSION
ARG DEBIAN_FRONTEND=noninteractive
ARG tz=Etc/UTC
ARG APT_MIRROR=
ARG MINICONDA_PREFIX=https://repo.anaconda.com/miniconda
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND} \
    TZ=${tz} \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_INSTALL_DIR=/usr/local/bin

WORKDIR /
RUN dpkg --print-architecture | grep -qx arm64

RUN set -eu; \
    if [ -n "${http_proxy:-${HTTP_PROXY:-}}" ]; then \
      printf 'Acquire::http::Proxy "%s";\n' "${http_proxy:-${HTTP_PROXY}}" > /etc/apt/apt.conf.d/99agentrl-proxy; \
    fi; \
    if [ -n "${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}" ]; then \
      printf 'Acquire::https::Proxy "%s";\n' "${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY}}}}" >> /etc/apt/apt.conf.d/99agentrl-proxy; \
    fi; \
    if [ -n "${APT_MIRROR}" ]; then \
      sed -i -E "s#https?://(ports.ubuntu.com/ubuntu-ports|archive.ubuntu.com/ubuntu|security.ubuntu.com/ubuntu)#${APT_MIRROR}#g" /etc/apt/sources.list; \
    fi; \
    apt-get update; \
    apt-get install -y --allow-downgrades "tzdata=${UBUNTU_TZDATA_VERSION}" || \
      apt-get install -y --allow-downgrades tzdata; \
    apt-get install -y sudo lsb-release pip python3 jq curl ca-certificates wget git binutils; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

ARG VELOX_GIT_URL=https://github.com/facebookincubator/velox.git
ARG VELOX_GIT_TAG=v2026.08.28.00
RUN git clone --depth 1 --branch "${VELOX_GIT_TAG}" "${VELOX_GIT_URL}" /velox && \
    test -f /velox/Makefile && test -f /velox/scripts/setup-ubuntu.sh

RUN cp /velox/CMake/resolve_dependency_modules/arrow/cmake-compatibility.patch / && \
    cp /velox/CMake/resolve_dependency_modules/arrow/arrow-testing-boost.patch / && \
    cp /velox/CMake/resolve_dependency_modules/openzl/openzl-cxx-standard.patch /

ENV VELOX_ARROW_CMAKE_PATCH="/cmake-compatibility.patch /arrow-testing-boost.patch" \
    VELOX_OPENZL_CMAKE_PATCH="/openzl-cxx-standard.patch"

WORKDIR /velox
RUN set -eu; \
    if [ "${MINICONDA_PREFIX}" != "https://repo.anaconda.com/miniconda" ]; then \
      sed -i "s|https://repo.anaconda.com/miniconda|${MINICONDA_PREFIX}|g" /velox/scripts/setup-ubuntu.sh; \
    fi; \
    /bin/bash -o pipefail /velox/scripts/setup-ubuntu.sh; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

RUN mkdir -p /velox/deps-sources && \
    curl -fsSL --retry 5 --retry-delay 2 -o /velox/deps-sources/gflags-v2.3.0.tar.gz \
      https://github.com/gflags/gflags/archive/refs/tags/v2.3.0.tar.gz

# Pin VLA SVE1 for Velox cmake, Gluten’s get_cxx_flags probe, and later CoW rebuilds.
RUN printf '\nfunction get_cxx_flags {\n  echo -n "-march=armv8-a+sve+crc+crypto "\n}\ndetect_sve_flags() {\n  true\n}\n' \
      >> /velox/scripts/setup-helper-functions.sh

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
    VELOX_BUILD_TESTING=OFF \
    VELOX_BUILD_MINIMAL=OFF \
    VELOX_BUILD_SHARED=ON \
    VELOX_MONO_LIBRARY=ON \
    VELOX_ENABLE_ARROW=ON \
    CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    CC=/usr/bin/gcc-12 \
    CXX=/usr/bin/g++-12

ARG NUM_THREADS=16
ARG MAX_LINK_JOBS=8
ENV NUM_THREADS=${NUM_THREADS} MAX_LINK_JOBS=${MAX_LINK_JOBS}

WORKDIR /velox
RUN set -eu; \
    if ! grep -q 'CMAKE_POLICY_VERSION_MINIMUM' CMake/resolve_dependency_modules/glog.cmake; then \
      sed -i '/message(STATUS "Building glog from source")/i set(CMAKE_POLICY_VERSION_MINIMUM 3.5)' \
        CMake/resolve_dependency_modules/glog.cmake; \
    fi; \
    if ! grep -q 'EXTRA_CMAKE_FLAGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5' Makefile; then \
      sed -i 's|EXTRA_CMAKE_FLAGS="-DCMAKE_C_COMPILER=|EXTRA_CMAKE_FLAGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_C_COMPILER=|' Makefile; \
    fi; \
    if ! grep -q -- '-Wno-error=restrict' Makefile; then \
      sed -i 's|-Wno-error=stringop-overflow|-Wno-error=stringop-overflow -Wno-error=restrict|' Makefile; \
    fi; \
    cxx_flags="-march=armv8-a+sve+crc+crypto -Wno-error=stringop-overflow -Wno-error=restrict"; \
    make release NUM_THREADS="${NUM_THREADS}" MAX_LINK_JOBS="${MAX_LINK_JOBS}" \
      VELOX_BUILD_TESTING=OFF VELOX_BUILD_MINIMAL=OFF TREAT_WARNINGS_AS_ERRORS=0 \
      EXTRA_CMAKE_FLAGS="-DCMAKE_C_COMPILER=/usr/bin/gcc-12 -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 -DCMAKE_CXX_FLAGS='\${cxx_flags}' -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DVELOX_BUILD_SHARED=ON -DVELOX_MONO_LIBRARY=ON -DVELOX_ENABLE_ARROW=ON -DArrow_SOURCE=BUNDLED"; \
    test -s /velox/_build/release/lib/libvelox.so; \
    test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib/libarrow_bundled_dependencies.a || \
      test -s /velox/_build/release/CMake/resolve_dependency_modules/arrow/arrow_ep/install/lib64/libarrow_bundled_dependencies.a

ENV VELOX_HOME=/velox \
    VELOX_INCLUDE_DIR=/velox \
    VELOX_BUILD_DIR=/velox/_build/release \
    VELOX_LIB_DIR=/velox/_build/release/lib \
    GLUTEN_HOME=/opt/gluten-1.6.0 \
    GLUTEN_INCLUDE_DIR=/opt/gluten-1.6.0/cpp/velox \
    GLUTEN_LIB_DIR=/opt/gluten-1.6.0/cpp/build/releases \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64

RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-11-jdk nlohmann-json3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    test -x "${JAVA_HOME}/bin/java" && java -version && javac -version

ARG GLUTEN_TARBALL_URL=https://github.com/apache/gluten/archive/refs/tags/v1.6.0.tar.gz
RUN set -eu; \
    archive=/tmp/gluten-1.6.0.tar.gz; \
    curl -fL --retry 5 --retry-delay 2 -o "$archive" "${GLUTEN_TARBALL_URL}"; \
    mkdir -p /opt/gluten-1.6.0; \
    tar -xzf "$archive" --strip-components=1 -C /opt/gluten-1.6.0; \
    rm -f "$archive"; \
    test -f /opt/gluten-1.6.0/cpp/CMakeLists.txt; \
    test -f /opt/gluten-1.6.0/cpp/velox/udf/Udf.h

# Gluten 1.6.0 imports Facebook libvelox.a; this image builds the shared mono library instead.
RUN python3 <<'PY'
from pathlib import Path

p = Path("/opt/gluten-1.6.0/cpp/velox/CMakeLists.txt")
t = p.read_text()
old = "import_library(facebook::velox \${VELOX_BUILD_PATH}/lib/libvelox.a)"
new = """if(NOT EXISTS \${VELOX_BUILD_PATH}/lib/libvelox.so)
  message(FATAL_ERROR "Facebook libvelox.so missing: \${VELOX_BUILD_PATH}/lib/libvelox.so")
endif()
add_library(facebook::velox SHARED IMPORTED)
set_target_properties(facebook::velox PROPERTIES IMPORTED_LOCATION \${VELOX_BUILD_PATH}/lib/libvelox.so)"""
if old not in t:
    raise SystemExit("facebook::velox import line not found")
p.write_text(t.replace(old, new, 1))
PY

WORKDIR /opt/gluten-1.6.0/cpp
RUN set -eu; \
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64 PATH="${JAVA_HOME}/bin:${PATH}"; \
    mkdir -p build; \
    cmake -S . -B build \
      -DBUILD_VELOX_BACKEND=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DVELOX_HOME=/velox \
      -DBUILD_TESTS=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_BENCHMARKS=OFF \
      -DCMAKE_PREFIX_PATH=/usr/local \
      -DCMAKE_C_COMPILER=/usr/bin/gcc-12 \
      -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 \
      -DCMAKE_CXX_FLAGS="-march=armv8-a+sve+crc+crypto"; \
    cmake --build build -j "${NUM_THREADS}"; \
    test -s /opt/gluten-1.6.0/cpp/build/releases/libgluten.so; \
    test -s /opt/gluten-1.6.0/cpp/build/releases/libvelox.so

ARG OPENCODE_VERSION=1.18.23
ARG OPENCODE_SHA256=86d3afaf4e8784f9adab189be2a315c12b27ec40a04b70defbe70595c3cc7c65
ARG OPENCODE_URL=https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-arm64.tar.gz
RUN set -eu; \
    curl -fL --retry 5 --retry-delay 2 -o /tmp/opencode-linux-arm64.tar.gz "${OPENCODE_URL}"; \
    printf '%s  %s\n' "${OPENCODE_SHA256}" /tmp/opencode-linux-arm64.tar.gz | sha256sum -c -; \
    mkdir -p /tmp/opencode; \
    tar -xzf /tmp/opencode-linux-arm64.tar.gz --no-same-owner -C /tmp/opencode opencode; \
    install -m 0755 /tmp/opencode/opencode /usr/local/bin/opencode; \
    opencode --version; \
    rm -rf /tmp/opencode /tmp/opencode-linux-arm64.tar.gz

RUN rm -f /etc/apt/apt.conf.d/*proxy*
ENV HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy=

WORKDIR /velox
CMD ["/bin/bash"]
