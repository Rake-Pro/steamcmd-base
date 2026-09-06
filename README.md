# steamcmd-base

Minimal, nonroot Debian base image with SteamCMD pre-installed, for building
Steam dedicated game server containers.

```
ghcr.io/rake-pro/steamcmd-base:latest
ghcr.io/rake-pro/steamcmd-base:1.1          # tracks the latest 1.1.x
ghcr.io/rake-pro/steamcmd-base:1.1.0        # exact release
```

- Built for the rake.pro homelab, usable by anyone: no homelab-specific
  assumptions are baked in.
- One place for the steam user, SteamCMD, its runtime symlinks, and a small
  set of bash helpers, so each game image only has to describe the game.
- `linux/amd64` only. SteamCMD and Steam dedicated servers are x86 binaries.

## What is in the image

| Item | Value |
| --- | --- |
| Base | `debian:trixie-slim`, single stage, apt security upgrades applied at build |
| User | `steam`, UID/GID `1000`, home `/home/steam`, shell `/bin/bash`. Default `USER` is `steam` |
| SteamCMD | `/home/steam/steamcmd/steamcmd.sh`, owned by `steam`, already self-updated at build time |
| Symlinks | `~/.steam/sdk32/steamclient.so`, `~/.steam/sdk64/steamclient.so`, `/usr/lib/x86_64-linux-gnu/steamclient.so`, `steamcmd/steamservice.so`, `steamcmd/steam.sh`, `linux32/steam`, `linux64/steam` |
| Packages | `lib32gcc-s1`, `lib32stdc++6`, `ca-certificates`, `curl`, `procps`, `locales`, `gosu` |
| Multiarch | `i386` architecture enabled in dpkg (nothing `:i386` installed). `apt-get update` first, then `apt-get install foo:i386` |
| Locale | `LANG=C.UTF-8` (built into glibc, nothing to generate). `locales` is present if a game needs `en_US.UTF-8`: `sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen` |
| Helpers | `/opt/scripts/functions.sh`, see below |
| Entrypoint | None. `CMD ["bash"]`. Each game image sets its own `ENTRYPOINT` |
| Healthcheck / stop signal | None. Each game image defines them (see recipes) |

## Quick start

Dockerfile:

```
FROM ghcr.io/rake-pro/steamcmd-base:1.1

ENV INSTALL_DIR=/game \
    STEAMAPPID=<appid> \
    SKIPUPDATE=false

COPY --chown=steam:steam scripts /home/steam/server/
RUN chmod +x /home/steam/server/*.sh

WORKDIR /home/steam/server
HEALTHCHECK --start-period=5m CMD pgrep -f <server-binary> > /dev/null
ENTRYPOINT ["/home/steam/server/init.sh"]
```

`scripts/init.sh`:

```
#!/bin/bash
set -euo pipefail
source /opt/scripts/functions.sh

require_env INSTALL_DIR
require_env STEAMAPPID

if [ "${SKIPUPDATE:-false}" != "true" ] || ! steamcmd_installed "$STEAMAPPID"; then
    steamcmd_update "$STEAMAPPID" validate || LogError "Update failed, starting the last installed build"
fi

term_handler() {
    LogAction "SIGTERM received, stopping server"
    kill -TERM "$server_pid"
    wait "$server_pid"
}
trap term_handler SIGTERM

LogAction "Starting server"
"$INSTALL_DIR"/<server-binary> <args> &
server_pid=$!
wait "$server_pid"
```

- Run as `steam` by default. Use `USER root` only for apt layers, then
  switch back with `USER steam` before the entrypoint.
- Keep `set -euo pipefail` in entrypoints. All helpers are safe under it.
- Mount `$INSTALL_DIR` as a volume so updates are incremental across restarts.

## Helpers (`/opt/scripts/functions.sh`)

Source it once at the top of the entrypoint. Runs as `steam` unless stated.

| Function | Signature | Behaviour |
| --- | --- | --- |
| `LogInfo` `LogWarn` `LogError` `LogSuccess` | `<message>` | Colour-coded line to stdout |
| `LogAction` | `<message>` | Same, wrapped in `====` for phase headings |
| `require_env` | `<VAR>` | Exits 1 with an error if `$VAR` is unset or empty |
| `steamcmd_installed` | `<appid>` | True when `$INSTALL_DIR/steamapps/appmanifest_<appid>.acf` reports `StateFlags 4` (fully installed) |
| `steamcmd_run` | `<steamcmd args...>` | One SteamCMD pass with the standard preamble (`force_install_dir` before login, platform override, credentials). Append `+app_update ...`/`+runscript ...`/`+quit` yourself |
| `steamcmd_update` | `<appid> [validate]` | Install/update into `$INSTALL_DIR` with retries. Returns 0 only when the manifest says fully installed, 1 otherwise |
| `remap_steam_user` | `[dir ...]` | Root only. Re-IDs `steam` to `$PUID`/`$PGID` (re-owning `/home/steam` when the IDs change), then creates and recursively chowns each given dir, including any parents it had to create. Follow with `exec gosu steam <cmd>` |

`steamcmd_update` and `steamcmd_run` read these optional variables:

| Variable | Effect |
| --- | --- |
| `STEAM_BETA` | Beta branch name (`-beta`). `public` or empty = default branch |
| `STEAM_BETA_PASSWORD` | Password for a private beta branch (`-betapassword`) |
| `STEAM_PLATFORM_TYPE` | `windows`, `linux` or `macos`. Sets `+@sSteamCmdForcePlatformType` before login. Needed to pull Windows-only depots for Wine/Proton servers |
| `STEAM_USER` / `STEAM_PASSWORD` | Non-anonymous login for apps that require ownership. Default is `anonymous` |
| `require_env` and the `Log*` helpers | Exit or print in the calling shell. Inside `$( )` an exit only ends the subshell |
| `STEAMCMD_RETRIES` | Attempts before giving up. Default `3` |
| `STEAMCMD_WIPE_ON_FAIL` | `true` = after all retries, delete `$INSTALL_DIR/steamapps` and try one final `validate`. Game files are untouched. Default `false` |

Why retries live inside the helper: `~/Steam` (SteamCMD's own cache) is
container-ephemeral. A container restart is always a cold-cache first attempt,
so a failure that only clears on the second `app_update` never clears by
restarting the pod. The helper clears `$HOME/Steam/appcache`, forces
`+app_info_update 1`, and re-runs within the same boot.

## Environment conventions

The base does not enforce these. The helpers and every rake.pro game image use
them, so following them keeps images interchangeable.

| Variable | Purpose |
| --- | --- |
| `INSTALL_DIR` | Game install directory. Required by `steamcmd_update` and `steamcmd_installed` |
| `STEAMAPPID` | Steam app id of the dedicated server |
| `SKIPUPDATE` | `true` = skip the boot-time update, but still install when the game is missing |
| `PUID` / `PGID` | UID/GID to remap `steam` to when a bind mount is host-owned. Only for images that boot as root and use `remap_steam_user` |
| `STEAM_BETA` | Beta branch (see helpers). Prefer this name over per-game variants |

## Recipes

### Nonroot with a Kubernetes or named volume (default)

- Leave `USER steam`. Set `fsGroup: 1000` (or run the volume's owner as
  1000) so `$INSTALL_DIR` is writable.
- No `PUID`/`PGID` handling needed.

### Host bind mounts with PUID/PGID

```
USER root
ENTRYPOINT ["/home/steam/server/init.sh"]
```

```
#!/bin/bash
set -euo pipefail
source /opt/scripts/functions.sh
remap_steam_user "$INSTALL_DIR" "$SAVED_DIR"
exec gosu steam /home/steam/server/run.sh "$@"
```

- `run.sh` is the normal nonroot entrypoint from the quick start.
- `exec gosu` keeps the game as PID 1's direct child, so SIGTERM reaches it.

### Beta branch

```
STEAM_BETA=experimental steamcmd_update "$STEAMAPPID" validate
```

### Windows-only server under Wine or Proton

```
ENV STEAM_PLATFORM_TYPE=windows
```

- `steamcmd_update` then pulls the Windows depot. Install Wine (WineHQ repo,
  with the i386 half) or Proton in the game image; the base only provides
  SteamCMD.
- Wine servers usually need `xvfb` and `winbind`, and a `wineserver -k` in the
  SIGTERM handler. See `Rake-Pro/palworld-server` for a full example including
  UE4SS mod loading.

### Apps that need a Steam login

- Set `STEAM_USER` and `STEAM_PASSWORD` (as secrets, never in the image).
- Steam Guard must be completed once interactively. The login state lives
  under `/home/steam/Steam` and `/home/steam/steamcmd`, so persist both on a
  volume or the code prompt returns on every boot.

### Extra 32-bit libraries (Source engine and older servers)

```
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      libsdl2-2.0-0:i386 lib32z1 \
 && rm -rf /var/lib/apt/lists/*
USER steam
```

### Healthcheck and graceful shutdown

- `HEALTHCHECK` on the server process name (`pgrep -f`) with a
  `--start-period` long enough for a first install.
- Trap SIGTERM in the entrypoint, forward it to the server, and `wait` on the
  PID so the container exits with the server's status. Prefer an RCON `save`
  and `quit` before the signal when the game offers one.
- Set `STOPSIGNAL` only if the server needs a signal other than SIGTERM.
- Add `tini` (`apt-get install tini`, `ENTRYPOINT ["tini","--","init.sh"]`) if
  the game spawns helper processes that get orphaned, for example Wine.

## Tags, releases, rebuilds

| Tag | Meaning |
| --- | --- |
| `X.Y.Z` | Immutable release, built from git tag `vX.Y.Z` |
| `X.Y` | Latest patch of that minor |
| `latest` | Latest release, re-pushed weekly with fresh Debian security patches (same version number) |
| `sha-<short>` | Commit the image was built from |

- `main` is the integration branch. A promotion PR to `prod` is opened
  automatically. Merging it mints the next patch tag and publishes the image.
- Label the promotion PR `release:minor` or `release:major` to change the bump.
- Every published image is Trivy-scanned. Fixable CRITICAL findings fail the
  workflow.
- Downstream images that `FROM :latest` pick up the weekly rebuild on their
  next build. Pin `X.Y` for repeatable builds.

## Verified behaviour

CI builds the image on every push and PR and checks:

- Runs as `steam` UID/GID 1000 with `/home/steam` as the working directory.
- SteamCMD, `gosu`, `curl`, `procps` are present and the `sdk32`/`sdk64`
  symlinks resolve.
- `functions.sh` passes shellcheck and sources cleanly under `set -euo pipefail`.
- A real anonymous SteamCMD round trip: `steamcmd_update 1007` (Steamworks SDK
  redistributable) ends with the manifest fully installed.

## Gotchas

- SteamCMD's exit code is not trustworthy. It can exit 0 after
  `state is 0x6 after update job` or `Missing configuration`. Judge success by
  the app manifest (`steamcmd_installed`), which the helper already does.
- `force_install_dir` must come before `login`. `steamcmd_run` enforces the
  order.
- The first pull of a platform-forced (Windows) depot fails more often than a
  native one. The retry path in `steamcmd_update` was written for that case.
- `/tmp/dumps` is SteamCMD's minidump folder. It is removed from the image and
  recreated at runtime; harmless.
- SteamCMD writes its `Starting ...` line to stderr. That is not an error.
  With `LANG=C.UTF-8` there is no locale warning either.
- `apt-get` in downstream images needs `apt-get update` first: package lists
  are removed from the base to keep it small.
- Images built `FROM :latest` inherit whatever SteamCMD version the last
  weekly rebuild fetched. SteamCMD also self-updates at runtime on first use
  if Valve shipped a newer client since.

## Images built on this base

| Repo | Server | Notes |
| --- | --- | --- |
| `Rake-Pro/palworld-server` | Palworld (Windows build) | Wine + UE4SS, `STEAM_PLATFORM_TYPE=windows` |
| `Rake-Pro/rust-server` | Rust | Oxide/Carbon, beta branches |
| `Rake-Pro/satisfactory-server` | Satisfactory | ficsit-cli mods, PUID/PGID |
| `Rake-Pro/project-zomboid-server` | Project Zomboid | RCON-driven save on shutdown, PUID/PGID |

## Layout

```
Dockerfile                 image definition
scripts/functions.sh       helpers copied to /opt/scripts/functions.sh
.github/workflows/ci.yml   build + contract smoke tests on main and PRs
.github/workflows/sync-prod.yml   opens the main -> prod promotion PR
.github/workflows/release.yml     tags, builds, pushes, Trivy-scans a release
.github/workflows/rebuild.yml     weekly re-push of the current release with fresh apt patches
```

## License

MIT, see `LICENSE`.
