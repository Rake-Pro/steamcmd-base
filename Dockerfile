FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# steamcmd itself is a 32-bit binary: lib32gcc-s1 / lib32stdc++6 (amd64
# multilib packages) cover it. The i386 architecture is enabled so downstream
# images can apt-get install :i386 libraries some game servers still need
# (e.g. libsdl2-2.0-0:i386); nothing :i386 is installed here.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get upgrade -y \
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

# Fallback for servers that dlopen steamclient.so by bare name instead of via
# ~/.steam/sdk64 (dangling until steamcmd is installed below).
RUN ln -s /home/steam/steamcmd/linux64/steamclient.so /usr/lib/x86_64-linux-gnu/steamclient.so

LABEL org.opencontainers.image.source="https://github.com/Rake-Pro/steamcmd-base" \
      org.opencontainers.image.title="steamcmd-base" \
      org.opencontainers.image.description="Base image for self-owned steamcmd game server images (rake.pro homelab)"

USER steam
WORKDIR /home/steam

# Install steamcmd as the steam user (no root involvement) and pre-run it
# once so it self-updates and lays down its linux32 runtime at build time,
# not on every downstream container's first boot.
# Then lay down the symlinks Valve's wiki and the common steamcmd images
# expect: ~/.steam/sdk{32,64}/steamclient.so (fixes "[S_API FAIL]
# SteamAPI_Init() failed" in Steamworks-linked servers) and the steam.sh /
# steam binary aliases some launchers look for.
RUN mkdir -p /home/steam/steamcmd \
 && curl -fsSL "https://client-update.steamstatic.com/installer/steamcmd_linux.tar.gz" \
      -o /tmp/steamcmd_linux.tar.gz \
 && tar -xzf /tmp/steamcmd_linux.tar.gz -C /home/steam/steamcmd \
 && rm -f /tmp/steamcmd_linux.tar.gz \
 && /home/steam/steamcmd/steamcmd.sh +quit \
 && mkdir -p /home/steam/.steam/sdk32 /home/steam/.steam/sdk64 \
 && ln -s /home/steam/steamcmd/linux32/steamclient.so /home/steam/.steam/sdk32/steamclient.so \
 && ln -s /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so \
 && ln -s /home/steam/steamcmd/linux32/steamclient.so /home/steam/steamcmd/steamservice.so \
 && ln -s /home/steam/steamcmd/linux32/steamcmd /home/steam/steamcmd/linux32/steam \
 && ln -s /home/steam/steamcmd/linux64/steamcmd /home/steam/steamcmd/linux64/steam \
 && ln -s /home/steam/steamcmd/steamcmd.sh /home/steam/steamcmd/steam.sh \
 && rm -rf /tmp/dumps

CMD ["bash"]
