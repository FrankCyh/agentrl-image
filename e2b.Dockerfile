FROM harbor:443/e2b-orchestration/agentrl-image:7a19ab58f9450c0430b502ecda35caa4eef52116

USER root

# E2B's provisioner expects these packages to exist in the base image.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        openssh-server \
        sudo \
        chrony \
        linuxptp \
        socat \
        curl \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
