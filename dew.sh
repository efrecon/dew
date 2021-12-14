#!/usr/bin/env sh

# If editing from Windows. Choose LF as line-ending

set -eu

# Find out where dependent modules are and load them at once before doing
# anything. This is to be able to use their services as soon as possible.

# This is a readlink -f implementation so this script can run on MacOS
abspath() {
  if [ -d "$1" ]; then
    ( cd -P -- "$1" && pwd -P )
  elif [ -L "$1" ]; then
    abspath "$(dirname "$1")/$(stat -c %N "$1" | awk -F ' -> ' '{print $2}' | cut -c 2- | rev | cut -c 2- | rev)"
  else
    printf %s\\n "$(abspath "$(dirname "$1")")/$(basename "$1")"
  fi
}

# Build a default colon separated DEW_LIBPATH using the root directory to look
# for modules that we depend on. DEW_LIBPATH can be set from the outside to
# facilitate location.
DEW_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )
DEW_LIBPATH=${DEW_LIBPATH:-${DEW_ROOTDIR}/libexec/docker-rebase/lib/mg.sh}
# shellcheck source=./libexec/docker-rebase/lib/mg.sh/bootstrap.sh disable=SC1091
. "${DEW_LIBPATH%/}/bootstrap.sh"

# Source in all relevant modules. This is where most of the "stuff" will occur.
module log locals options text

# Arrange so we know where XDG directories are on this system.
XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME}/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-${HOME}/.local/state}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/${USER}}

# Location of the directories where we can store shortcut to environments that
# are important to us. The default is the config directory under this
# repository, and the dew directory under the XDG configuration directory.
DEW_CONFIG_PATH=${DEW_CONFIG_PATH:-"${XDG_CONFIG_HOME}/dew:${DEW_ROOTDIR}/config"}

# Location of the docker socket. When empty, it will not be passed further
DEW_SOCK=${DEW_SOCK:-/var/run/docker.sock}

# Comma separated list of environment variable names that will automatically be
# ignored in the destination container.
DEW_BLACKLIST=${DEW_BLACKLIST:-SSH_AUTH_SOCK,TMPDIR,PATH}

# Should we impersonate the user in the container, i.e. run with the same used
# id (and group).
DEW_IMPERSONATE=${DEW_IMPERSONATE:-1}

# Should we provide for an interactive, terminal inside the container
DEW_INTERACTIVE=${DEW_INTERACTIVE:-"auto"}

# Should we inject the docker client in the destination container
DEW_DOCKER=${DEW_DOCKER:-0}

# This is the name for the container to create, when empty, the default, a name
# will be generated out of the image used for the container to ease recognition.
DEW_NAME=${DEW_NAME:-}

# Should we mount the XDG directories into the container? When this is not
# empty, directories with the content of this variable as their basename will be
# created under this user, then passed to the container.
DEW_XDG=${DEW_XDG:-}

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
DEW_DOCKER_VERSION=${DEW_DOCKER_VERSION:-20.10.6}

# Installation directory inside containers where we will inject stuff, whenever
# relevant and necessary.
DEW_INSTALLDIR=${DEW_INSTALLDIR:-/usr/local/bin}

# Rebase image on the following one before running it.
DEW_REBASE=${DEW_REBASE:-}

# Path to rebasing script to execute
DEW_REBASER=${DEW_REBASER:-"${DEW_ROOTDIR%/}/libexec/docker-rebase/rebase.sh"}

# Comment to print out before running
DEW_COMMENT=${DEW_COMMENT:-""}

DEW_PATHS=${DEW_PATHS:-""}

_OPTS=;   # Will contain list of vars set through the options
parseopts \
  --main \
  --synopsis "Kick-start a Docker-based environment from the current directory" \
  --usage "$MG_CMDNAME [options] -- image args..." \
  --description "The name of a docker image is a mandatory argument. When only a name is passed, the best possible interactive shell will be provided." \
  --prefix "DEW" \
  --shift _begin \
  --vars _OPTS \
  --options \
    r,root FLAG,INVERT IMPERSONATE - "Do not impersonate user in container" \
    d,docker FLAG DOCKER - "Inject Docker client into container" \
    o,opts,options OPTION OPTS - "Options blindly passed to docker run" \
    s,shell OPTION SHELL - "Shell to run interactively, default is empty, meaning a good guess. Set to - to leave the entrypoint unchanged." \
    rebase OPTION REBASE - "Rebase image on top of this one before running it (a copy will be made). Can be handy to inject a shell and other utilities in barebone images." \
    xdg OPTION XDG - "Create, then mount XDG directories with that name as the basename into container" \
    i,interactive OPTION INTERACTIVE - "Provide (a positive boolean), do not provide (a negative boolean) or guess (when auto) for interaction with -it run option" \
    p,path,paths OPTION PATHS - "Space-separated list of colon-separated path specifications to enforce presence/access of files/directories" \
    comment OPTION COMMENT - "Print out this message before running the Docker comment" \
    h,help FLAG @HELP - "Print this help and exit" \
  -- "$@"

# shellcheck disable=SC2154  # Var is set by parseopts
shift "$_begin"

# Store all our vars
_ENV=$(set | grep -E '^(DEW_|MG_)')

if [ "$#" = 0 ]; then
  die "You must at least provide the name of an image"
fi

# Get the value of the variable passed as a parameter, without running eval.
value_of() {
  set |
    grep -E "^${1}\s*=" |
    sed -E -e "s/^${1}\s*=\s*//" -e "s/^'//" -e "s/'\$//"
}

# Create the XDG directory of type $2 for the tool named $1.
xdg() (
  if [ -z "${1:-}" ]; then
    d=$(value_of "XDG_${2}_${3:-HOME}")
  else
    d=$(value_of "XDG_${2}_${3:-HOME}")/$1
  fi
  if ! [ -d "$d" ]; then
    if mkdir -p "$d" 2>/dev/null; then
      log_info "Created XDG $(to_lower "$2") directory at $d"
    elif [ "${4:-0}" = "1" ]; then
      if [ -z "${1:-}" ]; then
        d=$(mktemp -dt "tmp-${MG_CMDNAME}-$$-$(to_lower "$2").XXXXXX")
      else
        d=$(mktemp -dt "tmp-${MG_CMDNAME}-$$-$(to_lower "$2")-${1}.XXXXXX")
      fi
      log_info "Created temporary XDG $(to_lower "$2") directory at $d, this is not XDG compliant and might have unknown side-effects"
    fi
  fi

  if [ -d "$d" ]; then
    printf %s\\n "$d"
  fi
)

# Download the url passed as the first argument to the destination path passed
# as a second argument. The destination will be the same as the basename of the
# URL, in the current directory, if omitted.
download() {
  if command -v curl >/dev/null; then
    curl -sSL -o "${2:-$(basename "$1")}" "$1"
  elif command -v wget >/dev/null; then
    wget -q -O "${2:-$(basename "$1")}" "$1"
  fi
}

# Checks that the configuration file passed as an argument is valid.
check_config() {
  test -z "$(grep -Ev '^DEW_[A-Z_]+=' "$1" | grep -Ev '^[[:space:]]*$' | grep -Ev '^#')"
}

# Output the path to the configuration file that should be used for the
# container passed as argument if it exists and is valid. Empty string
# otherwise.
config() {
  for d in $(printf %s\\n "$DEW_CONFIG_PATH" | awk '{split($1,DIRS,/:/); for ( D in DIRS ) {printf "%s\n", DIRS[D];} }'); do
    log_trace "Looking for $1 in $d"
    if [ -d "$d" ]; then
      for f in "${d}/$1" "${d}/${1}.env"; do
        if [ -f "$f" ]; then
          if check_config "$f"; then
            printf %s\\n "$f"
            return
          else
            log_error "Configuration file at $f contains more than dew-specific configuration"
          fi
        fi
      done
    fi
  done
}

# Cut out the possible tag/sha256 at the end of the image name and extract the
# main name to be used as part of the automatically generated container name.
# ^((((((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)*(xn--)?([a-z0-9][a-z0-9\-]{0,60}|[a-z0-9-]{1,30}\.[a-z]{2,}))(((:[0-9]+)?)\/?))?)([a-z0-9](\-*[a-z0-9])*(\/[a-z0-9](\-*[a-z0-9])*)*)((:([a-z0-9\_]([\-\.\_a-z0-9])*))|(@sha256:[a-f0-9]{64}))?$
bn=$(basename "$(printf %s\\n "$1" | sed -E 's~((:([a-z0-9\_]([\-\.\_a-z0-9])*))|(@sha256:[a-f0-9]{64}))?$~~')")
[ -z "$DEW_NAME" ] && DEW_NAME="dew_${bn}_$$"
DEW_IMAGE=$1
shift; # Jump to the arguments

# Read configuration file for the first parameter
DEW_CONFIG=$(config "$DEW_IMAGE")
if [ -n "$DEW_CONFIG" ]; then
  log_info "Reading configuration for $DEW_IMAGE from $DEW_CONFIG"
  # shellcheck disable=SC1090 # The whole point is to have it dynamic!
  . "${DEW_CONFIG}"
  # Restore the variables that were forced through the options
  for v in $_OPTS; do
    eval "$(printf %s\\n "$_ENV" | grep "^${v}=")"
  done
fi

# Rebase (or not) image
if [ -n "$DEW_REBASE" ]; then
  rebased=$("$DEW_REBASER" --verbose notice --base "$DEW_REBASE" --dry-run -- "$DEW_IMAGE")
  if docker image inspect "$rebased" >/dev/null 2>&1; then
    log_debug "Rebasing to $rebased already performed, skipping"
    DEW_IMAGE=$rebased
  else
    log_notice "Rebasing $DEW_IMAGE on top of $DEW_REBASE"
    DEW_IMAGE=$("$DEW_REBASER" --verbose notice --base "$DEW_REBASE" -- "$DEW_IMAGE")
  fi
fi

# Download Docker client at the version specified by DEW_DOCKER_VERSION into the
# XDG cache so that it can be injected into the container.
if [ "$DEW_DOCKER" = "1" ]; then
  xdg dew CACHE > /dev/null
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

# Create files/directories prior to starting up the container. This can be used
# to generate (empty) RC files and similar. Format is any number of
# specifications, fields separated by colon sign in order:
# - (full) path to file/directory
# - Type of path to create f or - (or empty, default): file, d: directory
# - chmod access, i.e. 0700 or ug+rw. When empty, will be as default
# - Name/Id of owner for path
# - Name/Id of group for path
if [ -n "$DEW_PATHS" ]; then
  for spec in $DEW_PATHS; do
    path=$(printf %s:::::\\n "$spec" | cut -d: -f1)
    if [ -n "$path" ]; then
      type=$(printf %s:::::\\n "$spec" | cut -d: -f2)
      case "$type" in
        f | - | "")
          log_debug "Creating file: $path"
          touch "$path";;
        d )
          log_debug "Creating directory: $path"
          mkdir -p "$path";;
        * )
          log_warn "$type is not a recognised path type!";;
      esac

      if [ -f "$path" ] || [ -d "$path" ]; then
        chmod=$(printf %s:::::\\n "$spec" | cut -d: -f3)
        if [ -n "$chmod" ]; then
          chmod "$chmod" "$path"
        fi
        owner=$(printf %s:::::\\n "$spec" | cut -d: -f4)
        group=$(printf %s:::::\\n "$spec" | cut -d: -f5)
        if [ -n "$owner" ] && [ -n "$group" ]; then
          chown "${owner}:${group}" "$path"
        elif [ -n "$owner" ]; then
          chown "${owner}" "$path"
        elif [ -n "$group" ]; then
          chgrp "${group}" "$path"
        fi
      else
        log_error "Could not create path $path"
      fi
    fi
  done
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

# Mount UNIX domain docker socket into container, if relevant. Note in most
# case, the user remapped into the container will also have access to the Docker
# socket (you still have provide a CLI through injecting the Docker client with
# -d)
if [ -n "$DEW_SOCK" ]; then
  cmd="$cmd -v \"${DEW_SOCK}:${DEW_SOCK}\""
fi

# Create and mount XDG directories. We don't only create XDG directories when
# they do not exist, but also an extra directory under them, named after the
# value of DEW_XDG. This provides configuration isolation, as, by default, the
# container will only see the XDG configuration that was explicitely passed, but
# not the content of the other XDG directories.
if [ -n "$DEW_XDG" ]; then
  for type in DATA STATE CONFIG CACHE; do
    d=$(xdg "$DEW_XDG" "$type")
    cmd="$cmd -v \"${d}:${d}\""
    export XDG_${type}_HOME
  done

  d=$(xdg "" RUNTIME DIR 1)
  export XDG_RUNTIME_DIR
  chmod 0700 "$d"
  cmd="$cmd -v \"${d}:${d}\""
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

# When impersonating pass all environment variables that should be to the
# container.
if [ "$DEW_IMPERSONATE" = "1" ]; then
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
# under /usr/local/bin inside the container so it is accessible at the path and
# the prompt (or other programs).
if [ "$DEW_DOCKER" = "1" ]; then
  if [ -f "${XDG_CACHE_HOME}/dew/docker_$DEW_DOCKER_VERSION" ]; then
    cmd="$cmd -v ${XDG_CACHE_HOME}/dew/docker_${DEW_DOCKER_VERSION}:${DEW_INSTALLDIR%/}/docker:ro"
  fi
fi

if is_true "$DEW_INTERACTIVE" || { [ "$(to_lower "$DEW_INTERACTIVE")" = "auto" ] && [ "$#" = "0" ]; }; then
  cmd="$cmd \
        -it \
        -a stdin -a stdout -a stderr"
fi

if [ "$#" -gt 0 ]; then
  if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
    # We have specified a "shell", we understand this as specifying a different
    # entrypoint. If impersonation is on, then we behave more or less as when
    # running interactively. Otherwise, just run the image with specified
    # arguments, but with a different entrypoint.
    if [ "$DEW_IMPERSONATE" = "1" ]; then
      if [ "$MG_VERBOSITY" = "trace" ]; then
        cmd="$cmd -e DEW_DEBUG=1"
      fi
      cmd="$cmd \
            -v ${DEW_ROOTDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro \
            -e DEW_UID=$(id -u) \
            -e DEW_GID=$(id -g) \
            -e DEW_SHELL=$DEW_SHELL \
            -e HOME=$HOME \
            -e USER=$USER \
            --entrypoint ${DEW_INSTALLDIR%/}/su.sh \
            $DEW_IMAGE $*"
    else
      cmd="$cmd --entrypoint \"$DEW_SHELL\" $DEW_IMAGE $*"
    fi
  else
    # When we have specified arguments at the command line, we expect to be
    # calling a program in a non-interactive manner. Elevate to the user if
    # necessary and run
    if [ "$DEW_IMPERSONATE" = "1" ]; then
      cmd="$cmd --user $(id -u):$(id -g)"
    fi
    cmd="$cmd $DEW_IMAGE $*"
  fi
elif [ -n "$DEW_SHELL" ]; then
  # If we have no other argument than a Docker image (or a configured argument),
  # we behave a little differently when a specific shell is provided. When the
  # shell is '-', then this is understood as "do as little modification as
  # possible", so we just elevate to the user and run the image, with all
  # default arguments (as in the combination of the entrypoint and the default
  # set of arguments from the command).
  if [ "$DEW_SHELL" = "-" ]; then
    if [ "$DEW_IMPERSONATE" = "1" ]; then
      cmd="$cmd --user $(id -u):$(id -g)"
    fi
    cmd="$cmd $DEW_IMAGE"
  else
    # If the shell was specified, we understand this as trying to override the
    # entrypoint. We become the same user as the one running dew, after having
    # setup a minimial environment. This will run the specified shell with the
    # proper privieges.
    if [ "$MG_VERBOSITY" = "trace" ]; then
      cmd="$cmd -e DEW_DEBUG=1"
    fi
    if [ "$DEW_IMPERSONATE" = "1" ]; then
      cmd="$cmd \
            -v ${DEW_ROOTDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro \
            -e DEW_UID=$(id -u) \
            -e DEW_GID=$(id -g) \
            -e DEW_SHELL=$DEW_SHELL \
            -e HOME=$HOME \
            -e USER=$USER \
            --entrypoint ${DEW_INSTALLDIR%/}/su.sh \
            $DEW_IMAGE"
    else
      cmd="$cmd \
            -v ${DEW_ROOTDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro \
            -e DEW_SHELL=$DEW_SHELL \
            --entrypoint ${DEW_INSTALLDIR%/}/su.sh \
            $DEW_IMAGE"
    fi
  fi
else
  # If nothing at all was specified, we will run a shell under the proper
  # privileges, i.e. inside an encapsulated environment, minimally mimicing the
  # current user.
  if [ "$MG_VERBOSITY" = "trace" ]; then
    cmd="$cmd -e DEW_DEBUG=1"
  fi
  if [ "$DEW_IMPERSONATE" = "1" ]; then
    cmd="$cmd \
          -v ${DEW_ROOTDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro \
          -e DEW_UID=$(id -u) \
          -e DEW_GID=$(id -g) \
          -e HOME=$HOME \
          -e USER=$USER \
          --entrypoint ${DEW_INSTALLDIR%/}/su.sh \
          $DEW_IMAGE"
  else
    cmd="$cmd \
          -v ${DEW_ROOTDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro \
          --entrypoint ${DEW_INSTALLDIR%/}/su.sh \
          $DEW_IMAGE"
  fi
fi

# Print out comment (same destination as logging, i.e. stderr)
if [ -n "$DEW_COMMENT" ]; then
  printf \\n%s\\n\\n "$DEW_COMMENT" >&2
fi

# Trace the entire set of variables that were used for taking decisions,
# together with the Docker command that we are going to execute.
set | grep "^DEW_" | while IFS= read -r line; do
  log_trace "$line"
done
log_trace "Running: $cmd"

# Remove all temporary XDG stuff. Done here to avoid sub-shell exiting to
# trigger cleanup.
if [ -z "$DEW_XDG" ]; then
  at_exit rm -rf "${TMPDIR:-/tmp}/tmp-${MG_CMDNAME}-$$-*"
fi

# Now run the docker command. We evaluate to be able to replace variables by
# their values.
eval "$cmd"
