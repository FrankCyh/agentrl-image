#!/usr/bin/env bash
# Bind-mount this directory. Not COPY'd into the image.
set -euo pipefail

IMAGE="${IMAGE:-agentrl-image:local}"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

sg docker -c "docker run --rm -v ${TEST_DIR}:/test:ro ${IMAGE} bash /test/run_in_image.sh"
