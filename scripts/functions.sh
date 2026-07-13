#!/bin/bash
# Shared helpers for steamcmd-base and images built FROM it.
# Source this file: source /opt/scripts/functions.sh

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

# steamcmd_update <appid> [validate] - install/update a Steam app via
# steamcmd into $INSTALL_DIR. Run as the steam user. Pass "validate" as the
# second argument to force file validation.
steamcmd_update() {
  local appid="${1:-}"
  local validate="${2:-}"

  if [ -z "$appid" ]; then
    LogError "steamcmd_update: appid argument is required"
    exit 1
  fi
  require_env INSTALL_DIR

  local validate_flag=""
  if [ "$validate" = "validate" ]; then
    validate_flag="validate"
  fi

  LogAction "steamcmd: installing/updating app $appid in $INSTALL_DIR"
  /home/steam/steamcmd/steamcmd.sh \
    +force_install_dir "$INSTALL_DIR" \
    +login anonymous \
    +app_update "$appid" $validate_flag \
    +quit
}
