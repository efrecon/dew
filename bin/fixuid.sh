#!/bin/sh

FIXUID_USER=${FIXUID_USER:-1000}
FIXUID_GROUP=${FIXUID_GROUP:-1000}

FIXUID_INSTALL=${FIXUID_INSTALL:-}
FIXUID_BIN=${FIXUID_BIN:-fixuid}
FIXUID_CONFIG=${FIXUID_CONFIG:-"/etc/fixuid/config.yml"}

FIXUID_VERBOSE=${FIXUID_VERBOSE:-"0"}

# Preferred path where to put the binary
FIXUID_PATH=${FIXUID_PATH:-"/usr/local/bin:/usr/bin:/bin"}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 installs fixuid targeting proper user and group" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "u:g:i:vh-" opt; do
  case "$opt" in
    u) # Name or identifier of user to target inside image
      FIXUID_USER="$OPTARG";;
    g) # Name or identifier of group to target inside image
      FIXUID_GROUP="$OPTARG";;
    i) # Install fixuid binary from this path
      FIXUID_INSTALL="$OPTARG";;
    v) # Turn on verbosity, will otherwise log on errors/warnings only
      FIXUID_VERBOSE=1;;
    h) # Print help and exit
      usage;;
    -) # End of options, everything after blindly executed
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# PML: Poor Man's Logging
_log() {
    printf '[%s] [%s] [%s] %s\n' \
      "$(basename "$0")" \
      "${2:-LOG}" \
      "$(date +'%Y%m%d-%H%M%S')" \
      "${1:-}" \
      >&2
}
# shellcheck disable=SC2015 # We are fine, this is just to never fail
verbose() { [ "$FIXUID_VERBOSE" = "1" ] && _log "$1" NFO || true ; }
warn() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

db_get() {
  if cmd_exists "getent"; then
    verbose "Getting $2 from entry $1"
    getent "$1" "$2"
  else
    if printf %s\\n "$2" | grep -qE '^[0-9]+$'; then
      field=3
    else
      field=1
    fi
    verbose "Getting $2 from OS file /etc/$1"
    while IFS= read -r line; do
      if [ "$(printf %s\\n "$line" | cut -d: -f"$field")" = "$2" ]; then
        printf %s\\n "$line"
        return
      fi
    done < "/etc/$1"
  fi
}
group_name() { db_get group "$1" | cut -d: -f1; }
user_name() { db_get passwd "$1" | cut -d: -f1; }

# Pick a directory that is in the official PATH, among our preferred locations
# and present on disk.
pick_destination() {
  OFS=$IFS
  IFS=:
  for dir in $FIXUID_PATH; do
    if [ -d "$dir" ] && printf %s\\n "$PATH" | grep -qE "(^|:)$dir(:|\$)"; then
      verbose "Choosing $dir"
      printf %s\\n "$dir"
      break
    fi
  done
  IFS=$OFS
}

# Convert user and group from identifiers to names, if necessary.
FIXUID_USER=$(user_name "$FIXUID_USER")
FIXUID_GROUP=$(user_name "$FIXUID_GROUP")

# Install fixuid into path at a good location
if [ -n "${FIXUID_INSTALL:-}" ]; then
  dir=$(pick_destination)
  verbose "Copying $FIXUID_INSTALL to ${dir%/}/$FIXUID_BIN"
  cp -f "$FIXUID_INSTALL" "${dir%/}/$FIXUID_BIN"
fi

FIXUID_BIN=$(command -v "$FIXUID_BIN")
chown root:root "$FIXUID_BIN"
chmod 4755 "$FIXUID_BIN"
mkdir -p "$(dirname "$FIXUID_CONFIG")"
printf 'user: %s\ngroup: %s\n' "$FIXUID_USER" "$FIXUID_GROUP" > "$FIXUID_CONFIG"

if [ "$#" -gt "0" ]; then
  exec "$@"
fi
