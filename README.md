# steamcmd-base

Base image for self-owned steamcmd game server images in the rake.pro
homelab (org `Rake-Pro` on GHCR). Downstream images `FROM` this instead of
repeating steamcmd/steam-user setup per game.

```
ghcr.io/rake-pro/steamcmd-base
```

## Contract

Downstream images can rely on:

| What | Value |
| --- | --- |
| Base | `debian:bookworm-slim`, single stage, `linux/amd64` |
| User | `steam`, UID/GID `1000`, home `/home/steam` |
| Default user | `steam` (nonroot). Override `USER root` only if a downstream image must run as root. |
| steamcmd | `/home/steam/steamcmd/steamcmd.sh`, owned by `steam`, fully runnable as `steam` with no root involvement. Pre-run once at build time (self-update + linux32 runtime already laid down). |
| Helpers | `/opt/scripts/functions.sh` - source it: `LogInfo`, `LogWarn`, `LogError`, `LogSuccess`, `LogAction`, `steamcmd_update <appid> [validate]`, `require_env <VAR>` |
| `gosu` | Installed, for legacy images that still boot as root and need a root -> steam privilege drop |
| Entrypoint | None beyond `CMD ["bash"]` - each downstream image defines its own `ENTRYPOINT`/`CMD` |

## Env-var conventions

Not enforced by this base image, but expected by `functions.sh` and used
consistently across rake.pro steamcmd images:

| Variable | Purpose |
| --- | --- |
| `INSTALL_DIR` | Game install directory. Required by `steamcmd_update`. |
| `SKIPUPDATE` | `true`/`false` - downstream entrypoints should skip the steamcmd update on boot when set, but still install if the game binary is missing. |
| `PUID` / `PGID` | UID/GID to remap the `steam` user to at container start, for images that bind-mount host-owned volumes. Only relevant for images that boot as root and drop to `steam` via `gosu`. |

## Building a new game image on top of this

```
FROM ghcr.io/rake-pro/steamcmd-base

ENV INSTALL_DIR=/game \
    STEAMAPPID=<appid> \
    SKIPUPDATE=false

COPY --chown=steam:steam scripts /home/steam/server/
RUN chmod +x /home/steam/server/*.sh

WORKDIR /home/steam/server
ENTRYPOINT ["/home/steam/server/init.sh"]
```

In `init.sh`:

```
#!/bin/bash
source /opt/scripts/functions.sh

require_env INSTALL_DIR
mkdir -p "$INSTALL_DIR"

if [ "$SKIPUPDATE" != "true" ]; then
    steamcmd_update "$STEAMAPPID" validate
fi

LogAction "Starting server"
exec ./run-server-binary
```

Images that must boot as root (e.g. to `chown` a bind-mounted volume based
on `PUID`/`PGID` before dropping privileges) should set `USER root`, do that
work, then run the actual server as `gosu steam <command>`.
