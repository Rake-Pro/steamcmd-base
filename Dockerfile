FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# steamcmd is a 32-bit binary and needs the i386 arch enabled for its
# runtime libs.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      lib32gcc-s1 \
      lib32stdc++6 \
      ca-certificates \
      curl \
      procps \
      locales \
      gosu \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 steam \
 && useradd -m -u 1000 -g 1000 -d /home/steam -s /bin/bash steam

COPY scripts/functions.sh /opt/scripts/functions.sh
RUN sed -i 's/\r$//' /opt/scripts/functions.sh \
 && chmod 644 /opt/scripts/functions.sh

LABEL org.opencontainers.image.source="https://github.com/Rake-Pro/steamcmd-base" \
      org.opencontainers.image.title="steamcmd-base" \
      org.opencontainers.image.description="Base image for self-owned steamcmd game server images (rake.pro homelab)"

USER steam
WORKDIR /home/steam

# Install steamcmd as the steam user (no root involvement) and pre-run it
# once so it self-updates and lays down its linux32 runtime at build time,
# not on every downstream container's first boot.
RUN mkdir -p /home/steam/steamcmd \
 && curl -sSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      -o /tmp/steamcmd_linux.tar.gz \
 && tar -xzf /tmp/steamcmd_linux.tar.gz -C /home/steam/steamcmd \
 && rm -f /tmp/steamcmd_linux.tar.gz \
 && /home/steam/steamcmd/steamcmd.sh +quit

CMD ["bash"]
