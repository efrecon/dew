#!/usr/bin/env sh

# If editing from Windows. Choose LF as line-ending

set -eu

# Find out where dependent modules are and load them at once before doing
# anything. This is to be able to use their services as soon as possible.

# Build a default colon separated DEW_LIBPATH using the root directory to look
# for modules that we depend on. DEW_LIBPATH can be set from the outside to
# facilitate location. Note that this only works when there is support for
# readlink -f, see https://github.com/ko1nksm/readlinkf for a POSIX alternative.
DEW_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )
DEW_LIBPATH=${DEW_LIBPATH:-${DEW_ROOTDIR}/lib}

# Look for modules passed as parameters in the DEW_LIBPATH and source them.
# Modules are required so fail as soon as it was not possible to load a module
module() {
  for module in "$@"; do
    OIFS=$IFS
    IFS=:
    for d in $DEW_LIBPATH; do
      if [ -f "${d}/${module}.sh" ]; then
        # shellcheck disable=SC1090
        . "${d}/${module}.sh"
        IFS=$OIFS
        break
      fi
    done
    if [ "$IFS" = ":" ]; then
      echo "Cannot find module $module in $DEW_LIBPATH !" >& 2
      exit 1
    fi
  done
}

# Source in all relevant modules. This is where most of the "stuff" will occur.
module log

# Arrange so we know where user settings are on this system.
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}

# Arrange so we know where the user cache is on this system.
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}

# Location of the directory where we can store shortcut to environments that are
# important to us.
DEW_CONFIG=${DEW_CONFIG:-${XDG_CONFIG_HOME}/dew}

# Location of the docker socket. When empty, it will not be passed further
DEW_SOCK=${DEW_SOCK:-/var/run/docker.sock}

# Comma separated list of environment variable names that will automatically be
# ignored in the destination container.
DEW_BLACKLIST=${DEW_BLACKLIST:-SSH_AUTH_SOCK,TMPDIR,PATH}

# Should we impersonate the user in the container, i.e. run with the same used
# id (and group).
DEW_IMPERSONATE=${DEW_IMPERSONATE:-1}

# Should we inject the docker client in the destination container
DEW_DOCKER=${DEW_DOCKER:-0}

# This is the name for the container to create, when empty, the default, a name
# will be generated out of the image used for the container to ease recognition.
DEW_NAME=${DEW_NAME:-}

# Should we mount the current directory at the same location inside the
# destination container. In addition, when the mount is created, the working
# directory will be set to the mounted directory. When doing this, it is usually
# a good idea to impersonate the user to arrange for file permissions to be
# right.
DEW_MOUNT=${DEW_MOUNT:-1}

# Additional options blindly passed to the docker run command.
DEW_OPTS=${DEW_OPTS:-}

# Shell to execute for interactive command. When empty, the default, several
# shells will be tried in turns.
DEW_SHELL=${DEW_SHELL:-}

# Version of the docker client to download
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

    --name)
      DEW_NAME=$2; shift 2;;
    --name=*)
      DEW_NAME="${1#*=}"; shift 1;;

    --no-mount)
      DEW_MOUNT=0; shift;;

    -o | --opts | --options)
      DEW_OPTS=$2; shift 2;;
    --opts=* | --options=*)
      # shellcheck disable=2034 # Comes from log module
      DEW_OPTS="${1#*=}"; shift 1;;

    --shell)
      DEW_SHELL=$2; shift 2;;
    --shell=*)
      # shellcheck disable=2034 # Comes from log module
      DEW_SHELL="${1#*=}"; shift 1;;

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

if [ "$#" = 0 ]; then
  die "You must at least provide the name of an image"
fi

download() {
  if command -v curl >/dev/null; then
    curl -sSL -o "${2:-$(basename "$1")}" "$1"
  elif command -v wget >/dev/null; then
    wget -q -O "${2:-$(basename "$1")}" "$1"
  fi
}

if [ "$DEW_DOCKER" = "1" ]; then
  if ! [ -d "${XDG_CACHE_HOME}/dew" ]; then
    log_info "Creating local cache for Docker client binaries"
    mkdir -p "${XDG_CACHE_HOME}/dew"
  fi
  if ! [ -f "${XDG_CACHE_HOME}/dew/docker_$DEW_DOCKER_VERSION" ]; then
    log_notice "Downloading Docker client v$DEW_DOCKER_VERSION"
    tmpdir=$(mktemp -d)
    download \
      "https://download.docker.com/linux/static/stable/x86_64/docker-$DEW_DOCKER_VERSION.tgz" \
      "${tmpdir}/docker.tgz"
    wget -q -O "${tmpdir}/docker.tgz" https://download.docker.com/linux/static/stable/x86_64/docker-$DEW_DOCKER_VERSION.tgz
    tar -C "$tmpdir" -xf "${tmpdir}/docker.tgz"
    mv "${tmpdir}/docker/docker" "${XDG_CACHE_HOME}/dew/docker_$DEW_DOCKER_VERSION"
    rm -rf "$tmpdir"
  fi
fi

# Cut out the possible tag/sha256 at the end of the image name and extract the
# main name to be used as part of the automatically generated container name.
# ^((((((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)*(xn--)?([a-z0-9][a-z0-9\-]{0,60}|[a-z0-9-]{1,30}\.[a-z]{2,}))(((:[0-9]+)?)\/?))?)([a-z0-9](\-*[a-z0-9])*(\/[a-z0-9](\-*[a-z0-9])*)*)((:([a-z0-9\_]([\-\.\_a-z0-9])*))|(@sha256:[a-f0-9]{64}))?$
bn=$(basename "$(printf %s\\n "$1" | sed -E 's~((:([a-z0-9\_]([\-\.\_a-z0-9])*))|(@sha256:[a-f0-9]{64}))?$~~')")
[ -z "$DEW_NAME" ] && DEW_NAME="dew_${bn}_$$"
DEW_IMAGE=$1

# Read configuration file for the first parameter
if [ -d "$DEW_CONFIG" ]; then
  if [ -f "${DEW_CONFIG}/$1" ]; then
    if [ -n "$(grep -Ev '^DEW_[A-Z_]+=' "${DEW_CONFIG}/$1" | grep -Ev '^[[:space:]]*$' | grep -Ev '^#')" ]; then
      log_error "Configuration file at ${DEW_CONFIG}/$1 contains more than dew-specific configuration"
    else
      # shellcheck disable=SC1090 # The whole point is to have it dynamic!
      . "${DEW_CONFIG}/$1"
    fi
  fi
fi

log_trace "Kickstarting a container based on $DEW_IMAGE"

# The base command is to arrange for the container to automatically be removed
# once stopped, to add an init system to make sure we can capture signals and to
# share the host network.
cmd="docker run \
      --rm \
      --init \
      --network host \
      -v /etc/localtime:/etc/localtime:ro \
      --name $DEW_NAME"

# Mount UNIX domain docker socket into container, if relevant
if [ -n "$DEW_SOCK" ]; then
  cmd="$cmd -v "${DEW_SOCK}:${DEW_SOCK}""
fi

# Automatically mount the current directory and make it the current directory
# inside the container as well.
if [ "$DEW_MOUNT" = "1" ]; then
  cmd="$cmd \
        -v $(pwd):$(pwd) \
        -w $(pwd)"
fi

# Add blindly any options
if [ -n "$DEW_OPTS" ]; then
  cmd="$cmd $DEW_OPTS"
fi

# When impersonating the user arrange for the container to be running with the
# same user and group id, and pass all environment variables that should be.
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

# If requested to have the docker client, download it if necessary and mount it
# under /usr/local/bin inside the container.
if [ "$DEW_DOCKER" = "1" ]; then
  if [ -f "${XDG_CACHE_HOME}/dew/docker_$DEW_DOCKER_VERSION" ]; then
    cmd="$cmd -v ${XDG_CACHE_HOME}/dew/docker_${DEW_DOCKER_VERSION}:/usr/local/bin/docker:ro"
  else
    log_notice "Scheduling Docker client injection in the background"
    "$0" --name "$DEW_NAME" --inject &
  fi
fi

if [ "$#" -gt 1 ]; then
  shift
  cmd="$cmd $DEW_IMAGE $*"
elif [ -n "$DEW_SHELL" ]; then
  if [ "$DEW_SHELL" = "-" ]; then
    cmd="$cmd \
          -it \
          -a stdin -a stdout -a stderr \
          $DEW_IMAGE"
  else
    cmd="$cmd \
          -it \
          -a stdin -a stdout -a stderr \
          --entrypoint ${DEW_SHELL} \
          $DEW_IMAGE"
  fi
else
  cmd="$cmd \
        -it \
        -a stdin -a stdout -a stderr \
        --entrypoint /bin/sh \
        $DEW_IMAGE -c '{ bash && exit; } || { ash && exit; } || { sh && exit; }'"
fi

log_trace "Running: $cmd"
eval "$cmd"
