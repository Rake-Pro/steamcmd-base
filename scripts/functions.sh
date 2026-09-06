#!/bin/bash
# Shared helpers for steamcmd-base and images built FROM it.
# Source this file: source /opt/scripts/functions.sh
#
# All helpers are safe under `set -euo pipefail`. Helpers that detect a hard
# misconfiguration (require_env) exit the shell; helpers that can fail at
# runtime (steamcmd_update) return nonzero and let the caller decide.

#================
# Log Definitions
#================
export LINE='\n'                        # Line Break
export RESET='\033[0m'                  # Text Reset
export WhiteText='\033[0;37m'           # White

# Bold
export RedBoldText='\033[1;31m'         # Red
export GreenBoldText='\033[1;32m'       # Green
export YellowBoldText='\033[1;33m'      # Yellow
export CyanBoldText='\033[1;36m'        # Cyan
#================
# End Log Definitions
#================

LogInfo() {
  Log "$1" "$WhiteText"
}
LogWarn() {
  Log "$1" "$YellowBoldText"
}
LogError() {
  Log "$1" "$RedBoldText"
}
LogSuccess() {
  Log "$1" "$GreenBoldText"
}
LogAction() {
  Log "$1" "$CyanBoldText" "====" "===="
}
Log() {
  local message="$1"
  local color="$2"
  # prefix/suffix are optional (only LogAction passes them); default them so
  # callers running under `set -u` don't die here.
  local prefix="${3:-}"
  local suffix="${4:-}"
  printf "$color%s$RESET$LINE" "$prefix$message$suffix"
}

# require_env <VAR> - error and exit if the named environment variable is
# unset or empty.
require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    LogError "Required environment variable $var_name is not set"
    exit 1
  fi
}

# steamcmd_installed <appid> - true when the app manifest under $INSTALL_DIR
# reports StateFlags 4 (fully installed). steamcmd's exit code is unreliable
# (it can exit 0 after "state is 0x6" / "Missing configuration"), so the
# manifest is the source of truth for "did the update actually finish".
steamcmd_installed() {
  local appid="${1:-}"
  local manifest="${INSTALL_DIR:-}/steamapps/appmanifest_${appid}.acf"
  [ -n "$appid" ] && [ -f "$manifest" ] \
    && grep -q '"StateFlags"[[:space:]]*"4"' "$manifest"
}

# steamcmd_run <steamcmd args...> - one steamcmd pass as the steam user with
# the common preamble applied. Honours:
#   STEAM_PLATFORM_TYPE  windows|linux|macos - sets +@sSteamCmdForcePlatformType
#                        BEFORE login (needed to pull Windows-only depots for
#                        Wine/Proton servers).
#   STEAM_USER / STEAM_PASSWORD - non-anonymous login (Steam Guard must be
#                        disabled or pre-authorised; see README). Default:
#                        anonymous.
# Callers append their own +app_update / +runscript / +quit arguments.
steamcmd_run() {
  require_env INSTALL_DIR
  local -a pre=()
  if [ -n "${STEAM_PLATFORM_TYPE:-}" ]; then
    pre+=(+@sSteamCmdForcePlatformType "$STEAM_PLATFORM_TYPE")
  fi
  local -a login=(+login anonymous)
  if [ -n "${STEAM_USER:-}" ]; then
    login=(+login "$STEAM_USER")
    if [ -n "${STEAM_PASSWORD:-}" ]; then
      login+=("$STEAM_PASSWORD")
    fi
  fi
  /home/steam/steamcmd/steamcmd.sh \
    "${pre[@]}" \
    +force_install_dir "$INSTALL_DIR" \
    "${login[@]}" \
    "$@"
}

# steamcmd_update <appid> [validate] - install/update a Steam app via
# steamcmd into $INSTALL_DIR, with retries. Run as the steam user. Pass
# "validate" as the second argument to force file validation.
#
# Optional environment:
#   STEAM_BETA            beta branch name (-beta), e.g. "experimental"
#   STEAM_BETA_PASSWORD   password for a private beta branch (-betapassword)
#   STEAM_PLATFORM_TYPE   see steamcmd_run
#   STEAMCMD_RETRIES      attempts before giving up (default 3)
#   STEAMCMD_WIPE_ON_FAIL "true" to delete $INSTALL_DIR/steamapps after all
#                         retries fail and make one last validate attempt
#                         (clears stale update state; game files stay in place)
#
# Success = the app manifest reports fully installed (see steamcmd_installed).
# Returns 1 on failure so the caller can choose to abort or boot the last
# good build with a loud warning. Retries happen inside this call on purpose:
# ~/Steam is container-ephemeral, so restarting the container would start
# again from a cold appinfo cache and never get past attempt 1.
steamcmd_update() {
  local appid="${1:-}"
  local validate="${2:-}"

  if [ -z "$appid" ]; then
    LogError "steamcmd_update: appid argument is required"
    exit 1
  fi
  require_env INSTALL_DIR
  mkdir -p "$INSTALL_DIR"

  local -a update=(+app_update "$appid")
  if [ -n "${STEAM_BETA:-}" ] && [ "${STEAM_BETA}" != "public" ]; then
    update+=(-beta "$STEAM_BETA")
    if [ -n "${STEAM_BETA_PASSWORD:-}" ]; then
      update+=(-betapassword "$STEAM_BETA_PASSWORD")
    fi
  fi
  if [ "$validate" = "validate" ]; then
    update+=(validate)
  fi

  local retries="${STEAMCMD_RETRIES:-3}"
  if ! [[ "$retries" =~ ^[1-9][0-9]*$ ]]; then
    LogWarn "steamcmd: STEAMCMD_RETRIES='$retries' is not a positive integer, using 3"
    retries=3
  fi
  local attempt
  LogAction "steamcmd: installing/updating app $appid in $INSTALL_DIR"
  for attempt in $(seq 1 "$retries"); do
    if [ "$attempt" -gt 1 ]; then
      LogWarn "steamcmd: attempt $((attempt - 1)) did not finish; clearing appcache and retrying ($attempt/$retries)"
      rm -rf "${HOME:-/home/steam}/Steam/appcache"
      sleep 10
      steamcmd_run +app_info_update 1 "${update[@]}" +quit || true
    else
      steamcmd_run "${update[@]}" +quit || true
    fi
    if steamcmd_installed "$appid"; then
      LogSuccess "steamcmd: app $appid fully installed (attempt $attempt)"
      return 0
    fi
  done

  if [ "${STEAMCMD_WIPE_ON_FAIL:-false}" = "true" ]; then
    LogWarn "steamcmd: $retries attempts failed; wiping $INSTALL_DIR/steamapps and validating once more"
    rm -rf "${INSTALL_DIR:?}/steamapps"
    if [ "$validate" != "validate" ]; then
      update+=(validate)
    fi
    steamcmd_run "${update[@]}" +quit || true
    if steamcmd_installed "$appid"; then
      LogSuccess "steamcmd: app $appid fully installed after steamapps wipe"
      return 0
    fi
  fi

  LogError "steamcmd: app $appid is NOT fully installed after $retries attempt(s)"
  return 1
}

# remap_steam_user [dir ...] - root-only. Change the steam user's UID/GID to
# $PUID/$PGID (for bind-mounted, host-owned volumes), then create and
# recursively chown each given directory. Parent directories that mkdir -p
# has to create are chowned too, so a path under /home/steam does not leave
# root-owned intermediates behind. /home/steam itself is re-owned only when
# the IDs actually change. Follow it with: exec gosu steam <server command>.
remap_steam_user() {
  if [ "$(id -u)" -ne 0 ]; then
    LogError "remap_steam_user must run as root (image needs USER root before its entrypoint)"
    exit 1
  fi
  local puid="${PUID:-1000}"
  local pgid="${PGID:-1000}"
  if [ "$(id -u steam)" != "$puid" ] || [ "$(id -g steam)" != "$pgid" ]; then
    LogInfo "Remapping steam user to UID $puid / GID $pgid"
    groupmod -o -g "$pgid" steam
    usermod -o -u "$puid" -g "$pgid" steam
    chown -R steam:steam /home/steam
  fi
  local dir parent
  local -a created
  for dir in "$@"; do
    created=()
    parent="$dir"
    while [ "$parent" != "/" ] && [ ! -e "$parent" ]; do
      created+=("$parent")
      parent=$(dirname "$parent")
    done
    mkdir -p "$dir"
    if [ "${#created[@]}" -gt 0 ]; then
      chown steam:steam "${created[@]}"
    fi
    chown -R steam:steam "$dir"
  done
}
