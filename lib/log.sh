#!/usr/bin/env sh

# When run at the terminal, the default is to set EFSL_INTERACTIVE to be 1,
# turning on colouring for all calls to the colouring functions contained here.
if [ -t 1 ]; then
    EFSL_INTERACTIVE=${EFSL_INTERACTIVE:-1}
else
    EFSL_INTERACTIVE=${EFSL_INTERACTIVE:-0}
fi

# Verbosity inside the script. One of: error, warn, notice, info, debug or
# trace.
EFSL_VERBOSITY=${EFSL_VERBOSITY:-"info"}

# Store the root directory where the script was found, together with the name of
# the script and the name of the app, e.g. the name of the script without the
# extension.
# shellcheck disable=2034 # Declare this so it can be used in scripts
EFSL_APPDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )
EFSL_CMDNAME=$(basename -- "$0")
EFSL_APPNAME=${EFSL_CMDNAME%.*}

# This should be set from the script with a usage description that will be print
# out from the usage procedure when problems are detected.
EFSL_USAGE=${EFSL_USAGE:-""}

# Colourisation support for logging and output.
_colour() {
  if [ "$EFSL_INTERACTIVE" = "1" ]; then
    # shellcheck disable=SC2086
    printf '\033[1;31;'${1}'m%b\033[0m' "$2"
  else
    printf -- "%b" "$2"
  fi
}
green() { _colour "32" "$1"; }
red() { _colour "31" "$1"; }
yellow() { _colour "33" "$1"; }
blue() { _colour "34" "$1"; }
magenta() { _colour "35" "$1"; }
cyan() { _colour "36" "$1"; }
dark_gray() { _colour "90" "$1"; }
light_gray() { _colour "37" "$1"; }

# Conditional coloured logging
_LOG_LEVELS="error
warn
notice
info
debug
trace"
_log() (
  if at_verbosity "$1"; then
    case "$1" in
      [Ee][Rr][Rr][Oo][Rr])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(magenta ERR)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      [Ww][Aa][Rr][Nn])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(red WRN)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      [Nn][Oo][Tt][Ii][Cc][Ee])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(yellow NTC)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      [Ii][Nn][Ff][Oo])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(blue INF)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      [Dd][Ee][Bb][Uu][Gg])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(light_gray DBG)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      [Tt][Rr][Aa][Cc][Ee])
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "$(dark_gray TRC)" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
      *)
        printf "[%s] [%s] [%s] %s\n" "$(dark_gray "$3")" "log" "$(date +'%Y%m%d-%H%M%S')" "$2" >&2;;
    esac
  fi
)
log_error() { _log error "$1" "${2:-$EFSL_APPNAME}"; }
log_warn() { _log warn "$1" "${2:-$EFSL_APPNAME}"; }
log_notice() { _log notice "$1" "${2:-$EFSL_APPNAME}"; }
log_info() { _log info "$1" "${2:-$EFSL_APPNAME}"; }
log_debug() { _log debug "$1" "${2:-$EFSL_APPNAME}"; }
log_trace() { _log trace "$1" "${2:-$EFSL_APPNAME}"; }
log() { log_info "$@"; } # For the lazy ones...
die() { log_error "$1"; exit 1; }

at_verbosity() (
  passed=$(printf %s\\n "$_LOG_LEVELS" | sed -n "/${1}/=" | tr "[:lower:]" "[:upper:]")
  current=$(printf %s\\n "$_LOG_LEVELS" | sed -n "/${EFSL_VERBOSITY}/=" | tr "[:lower:]" "[:upper:]")
  test "$passed" -le "$current"
)
check_verbosity() {
  printf %s\\n "$_LOG_LEVELS" | grep -qi "${1:-$EFSL_VERBOSITY}"
}

usage() {
  [ "$#" -gt "1" ] && printf %s\\n "$2" >&2
  if [ -z "$EFSL_USAGE" ]; then
    printf %s\\n "$EFSL_CMDNAME was called with erroneous options!" >&2
  else
    printf %s\\n "$EFSL_USAGE" >&2
  fi
  exit "${1:-1}"
}