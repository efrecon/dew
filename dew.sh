#!/usr/bin/env sh

# If editing from Windows. Choose LF as line-ending

set -eu

# Find out where dependent modules are and load them at once before doing
# anything. This is to be able to use their services as soon as possible.

# Build a default colon separated INSTALL_LIBPATH using the root directory to
# look for modules that we depend on. INSTALL_LIBPATH can be set from the outside
# to facilitate location.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )
INSTALL_LIBPATH=${INSTALL_LIBPATH:-${INSTALL_ROOTDIR}/lib}

# Look for modules passed as parameters in the INSTALL_LIBPATH and source them.
# Modules are required so fail as soon as it was not possible to load a module
module() {
  for module in "$@"; do
    OIFS=$IFS
    IFS=:
    for d in $INSTALL_LIBPATH; do
      if [ -f "${d}/${module}.sh" ]; then
        # shellcheck disable=SC1090
        . "${d}/${module}.sh"
        IFS=$OIFS
        break
      fi
    done
    if [ "$IFS" = ":" ]; then
      echo "Cannot find module $module in $INSTALL_LIBPATH !" >& 2
      exit 1
    fi
  done
}

# Source in all relevant modules. This is where most of the "stuff" will occur.
module log

DEW_SOCK=${DEW_SOCK:-/var/run/docker.sock}

DEW_BLACKLIST=${DEW_BLACKLIST:-SSH_AUTH_SOCK,TMPDIR,PATH}

DEW_IMPERSONATE=${DEW_IMPERSONATE:-1}

DEW_DOCKER=${DEW_DOCKER:-0}

DEW_NAME=${DEW_NAME:-}

DEW_INJECT=${DEW_INJECT:-0}

DEW_DOCKER_VERSION=20.10.6

# shellcheck disable=2034 # Usage string is used by log module on errors
EFSL_USAGE="
Synopsis:
  Kick-start a Docker-based environment from the current directory

Usage:
  $EFSL_CMDNAME [-option arg] [--] img args...
  where all dash-led single options are as follows:
    -r | --root      Do not inpersonate user in container
    -v | --verbosity One of: error, warn, notice, info, debug or trace

  The name of a docker image is a mandatory argument. When only a
  name is passed, the best possible interactive shell will be
  provided.
"

# Parse options
while [ $# -gt 0 ]; do
  case "$1" in
    -r | --root)
      DEW_IMPERSONATE=0; shift;;

    -d | --docker)
      DEW_DOCKER=1; shift;;

    --inject)
      DEW_INJECT=1; shift;;

    --name)
      DEW_NAME=$2; shift 2;;
    --name=*)
      DEW_NAME="${1#*=}"; shift 1;;

    -v | --verbosity | --verbose)
      EFSL_VERBOSITY=$2; shift 2;;
    --verbosity=* | --verbose=*)
      # shellcheck disable=2034 # Comes from log module
      EFSL_VERBOSITY="${1#*=}"; shift 1;;

    -\? | -h | --help)
      usage 0;;
    --)
      shift; break;;
    -*)
      usage 1 "Unknown option: $1 !";;
    *)
      break;
  esac
done

[ -z "$DEW_NAME" ] && DEW_NAME="dew_$$"

if [ "$DEW_INJECT" = "1" ]; then
  while true; do
    if docker ps --format '{{.Names}}'|grep -q "$DEW_NAME"; then
      break
    fi
    log_trace "Still waiting for $DEW_NAME container to be created"
    sleep 1
  done

  tmpdir=$(docker exec -u 0 "$DEW_NAME" mktemp -d)
  log_debug "Downloading Docker v$DEW_DOCKER_VERSION in $tmpdir and installing at /usr/local/bin"
  docker exec -u 0 "$DEW_NAME" wget -q -O "${tmpdir}/docker.tgz" https://download.docker.com/linux/static/stable/x86_64/docker-$DEW_DOCKER_VERSION.tgz
  docker exec -u 0 "$DEW_NAME" tar -C "$tmpdir" -xf "${tmpdir}/docker.tgz"
  docker exec -u 0 "$DEW_NAME" mv "${tmpdir}/docker/docker" /usr/local/bin/
  docker exec -u 0 "$DEW_NAME" rm -rf "$tmpdir"
  exit
fi

if [ "$#" = 0 ]; then
  die "You must at least provide the name of an image"
fi

cmd="docker run \
      --rm \
      --init \
      -v "${DEW_SOCK}:${DEW_SOCK}" \
      -v $(pwd):$(pwd) \
      -w $(pwd) \
      --network host \
      --name $DEW_NAME"

if [ "$DEW_IMPERSONATE" = "1" ]; then
  cmd="$cmd --user $(id -u):$(id -g)"
  vars=$(env | grep -oE '^[A-Z][A-Z0-9_]*=' | sed 's/=$//g')
  for v in $vars; do
    if printf %s\\n "$DEW_BLACKLIST" | grep -q "$v"; then
      log_trace "Ignoring environment variable $v from blacklist"
    else
      cmd="$cmd --env ${v}=\"\$$v\""
    fi
  done
fi

if [ "$#" -gt 1 ]; then
  cmd="$cmd $*"
else
  cmd="$cmd \
        -it \
        -a stdin -a stdout -a stderr \
        --entrypoint /bin/sh \
        $1 -c 'bash || ash || sh; exit'"
fi

if [ "$DEW_DOCKER" = "1" ]; then
  log_notice "Scheduling Docker client injection in the background"
  "$0" --name "$DEW_NAME" --inject --verbose "$EFSL_VERBOSITY" &
fi
eval "$cmd"
