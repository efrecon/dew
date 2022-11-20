#!/bin/sh

PREFUSER_DEFS=${PREFUSER_DEFS:-"/etc/login.defs"}
PREFUSER_UID_MIN=${PREFUSER_UID_MIN:-1000}
PREFUSER_UID_MAX=${PREFUSER_UID_MAX:-60000}
PREFUSER_GID_MIN=${PREFUSER_GID_MIN:-1000}
PREFUSER_GID_MAX=${PREFUSER_GID_MAX:-60000}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 guess id and group of first real user" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "u:g:d:h-" opt; do
  case "$opt" in
    h) # Print help and exit
      usage;;
    u) # Default user ID min:max when definitions cannot be found
      PREFUSER_UID_MIN=$(printf %s\\"$OPTARG"|cut -d: -f1)
      PREFUSER_UID_MAX=$(printf %s\\"$OPTARG"|cut -d: -f2)
      ;;
    g) # Default group ID min:max when definitions cannot be found
      PREFUSER_GID_MIN=$(printf %s\\"$OPTARG"|cut -d: -f1)
      PREFUSER_GID_MAX=$(printf %s\\"$OPTARG"|cut -d: -f2)
      ;;
    d) # Path to system-wide definitions
      PREFUSER_DEFS="$OPTARG";;
    -) # End of options, everything after user ids or names to resolve
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

db_get() {
  if cmd_exists "getent"; then
    getent "$1"
  else
    cat "/etc/$1"
  fi
}

prefs() {
  grep -E "^$1" "$PREFUSER_DEFS" | awk '{print $2}'
}

# Read uid/gid min and max from preferences file when it exist. Defaults to good
# defaults on errors.
if [ -f "$PREFUSER_DEFS" ]; then
  p=$(prefs "UID_MIN")
  if [ -n "$p" ]; then PREFUSER_UID_MIN=$p; fi
  p=$(prefs "UID_MAX")
  if [ -n "$p" ]; then PREFUSER_UID_MAX=$p; fi
  p=$(prefs "GID_MIN")
  if [ -n "$p" ]; then PREFUSER_GID_MIN=$p; fi
  p=$(prefs "GID_MAX")
  if [ -n "$p" ]; then PREFUSER_GID_MAX=$p; fi
fi

# Read the password file and return the first "real" user, i.e. user with at
# least an identifier of UID_MIN, or the one matching the argument
lookup() {
  while IFS=: read -r username password uid gid gecos home shell; do
    if [ "$uid" -ge "$PREFUSER_UID_MIN" ] && [ "$uid" -le "$PREFUSER_UID_MAX" ]; then
      if [ -z "${1:-}" ]; then
        printf '%s:%s\n' "$uid" "$gid"
        break
      elif printf %s\\n "${1:-}" | grep -Eq '^[0-9]+$' && [ "$uid" = "${1:-}" ]; then
        printf '%s:%s\n' "$uid" "$gid"
        break
      elif [ "$username" = "${1:-}" ]; then
        printf '%s:%s\n' "$uid" "$gid"
        break
      fi
    fi
  done<<EOF
$(db_get passwd | sort -g -t : -k 3 -r)
EOF
}

if [ "$#" -gt 0 ]; then
  for uid in "$@"; do
    lookup "$uid"
  done
else
  lookup
fi
