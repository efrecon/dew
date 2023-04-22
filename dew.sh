#!/bin/sh

# If editing from Windows. Choose LF as line-ending

set -eu

# Find out where dependent modules are and load them at once before doing
# anything. This is to be able to use their services as soon as possible.

# This is a readlink -f implementation so this script can (perhaps) run on MacOS
abspath() {
  is_abspath() {
    case "$1" in
      /* | ~*) true;;
      *) false;;
    esac
  }

  if [ -d "$1" ]; then
    ( cd -P -- "$1" && pwd -P )
  elif [ -L "$1" ]; then
    if is_abspath "$(readlink "$1")"; then
      abspath "$(readlink "$1")"
    else
      abspath "$(dirname "$1")/$(readlink "$1")"
    fi
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
module log locals options text portability date

# Arrange so we know where XDG directories are on this system.
XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME}/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-${HOME}/.local/state}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/${USER}}

# Location of the directories where we can store shortcut to environments that
# are important to us. The default is the config directory under this
# repository, and the dew directory under the XDG configuration directory.
DEW_CONFIG_PATH=${DEW_CONFIG_PATH:-"$(pwd)/.dew.d:${XDG_CONFIG_HOME}/dew:${DEW_ROOTDIR}/config"}

# Location of the docker socket. When empty, it will not be passed further
DEW_SOCK=${DEW_SOCK:-/var/run/docker.sock}

# Comma separated list of environment variable names that will automatically be
# ignored in the destination container.
DEW_BLACKLIST=${DEW_BLACKLIST:-SSH_AUTH_SOCK,TMPDIR,PATH,LC_TIME,LC_CTYPE,LANG}

# Should we impersonate the user in the container, i.e. run with the same user
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

# Number of levels up in the directory hierarchy, starting from current
# directory, that we should mount into the container. Setting this to a negative
# number will disable the function. When this is 0, the default, the current
# directory will only be made available. When set to 1, its parent directory
# will be made available, etc. When doing this, it is usually a good idea to
# impersonate the user to arrange for file permissions to be right.
DEW_MOUNT=${DEW_MOUNT:-0}

# Additional options blindly passed to the docker run command.
DEW_OPTS=${DEW_OPTS:-}

# Shell to execute for interactive command. When empty, the default, several
# shells will be tried in turns.
DEW_SHELL=${DEW_SHELL:-}

# Number of seconds after which we should check for new versions of download
# binaries at GitHub. Default is 3 days.
DEW_BINCACHE_VERCHECK=${DEW_BINCACHE_VERCHECK:-"259200"}

# Version of the docker client to download
DEW_DOCKER_VERSION=${DEW_DOCKER_VERSION:-""}

# Version of the fixuid binary to download
DEW_FIXUID_VERSION=${DEW_FIXUID_VERSION:-""}

# List of features that all containers will have. Features are in uppercase, and
# each feature is defined by a variable from the file pointed at by
# $DEW_FEATURE_CONFIG
DEW_FEATURES=${DEW_FEATURES:-"AUTORM INIT HOSTNET LOCALTIME"}

# Path to file containing feature descriptions. See $DEW_FEATURES
DEW_FEATURES_CONFIG=${DEW_FEATURES_CONFIG:-"${DEW_ROOTDIR%/}/etc/features.env"}

# Installation directory inside containers where we will inject stuff, whenever
# relevant and necessary.
DEW_INSTALLDIR=${DEW_INSTALLDIR:-/usr/local/bin}

# Rebase image on the following one before running it.
DEW_REBASE=${DEW_REBASE:-}

# Path to rebasing script to execute
DEW_REBASER=${DEW_REBASER:-"${DEW_ROOTDIR%/}/libexec/docker-rebase/rebase.sh"}

# Comment to print out before running
DEW_COMMENT=${DEW_COMMENT:-""}

# List of path specifications (at host) to create before starting the container.
# Use this, for example, to create directory to store tool-specific
# configuration. Each specification colon-separated: name of path, type of path
# (d for a directory, f for a file (the default))
DEW_PATHS=${DEW_PATHS:-""}

# Should we just list available configs
DEW_LIST=${DEW_LIST:-"0"}

# List of runtimes to try when runtime is empty, in this order, first match will
# be used.
DEW_RUNTIMES=${DEW_RUNTIMES:-"docker podman nerdctl"}

# Runtime to use, when empty, the default, runtimes from DEW_RUNTIMES will be
# used (first match).
DEW_RUNTIME=${DEW_RUNTIME:-""}

# Inject following command into a raw container based on the same image, then
# use that image for the remaining of the setup. This is almost the same as
# creating a Dockerfile based on the same image, with the `RUN` command in it.
DEW_INJECT=${DEW_INJECT:-""}

# Prefix to add to MD5 sum when generating tags for injected images. There are
# few reasons to change this...
DEW_INJECT_TAG_PREFIX=${DEW_INJECT_TAG_PREFIX:-"dew_"}

# Should we cleanup old injected images?
DEW_INJECT_CLEANUP=${DEW_INJECT_CLEANUP:-"1"}

# Arguments to injection script
DEW_INJECT_ARGS=${DEW_INJECT_ARGS:-""}

# Root GitHub home page
DEW_GITHUB=${DEW_GITHUB:-"https://github.com/"}

# Namespace under which to root target Dockerfiles. This should be compatible
# with what Docker uses, but not a proper Docker registry.
DEW_NAMESPACE=${DEW_NAMESPACE:-"github.com/efrecon/dew"}

# The number of significant digits to pick from sha256 sum for the digest.
DEW_DIGEST=${DEW_DIGEST:-7}

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
    j,inject OPTION INJECT - "Inject this command (can be an executable script) into the original image, then run from the resulting image. This is a poorman's (Dockerfile) RUN." \
    inject-args OPTION INJECT_ARGS - "Arguments to the injection command" \
    f,features OPTION FEATURES - "List of features given to each container, features are defined in $DEW_FEATURES_CONFIG" \
    p,path,paths OPTION PATHS - "Space-separated list of colon-separated path specifications to enforce presence/access of files/directories" \
    comment OPTION COMMENT - "Print out this message before running the Docker comment" \
    t,runtime OPTION RUNTIME - "Runtime to use, when empty, pick first from $DEW_RUNTIMES" \
    m,mount OPTION MOUNT - "Hierarchy levels up from current dir to mount into container, -1 to disable." \
    l,list FLAG LIST - "Print out list of known configs and exit" \
    h,help FLAG @HELP - "Print this help and exit" \
  -- "$@"

# shellcheck disable=SC2154  # Var is set by parseopts
shift "$_begin"

# Store all our vars
_ENV=$(set | grep -E '^(DEW_|MG_)')

if [ "$#" = 0 ] && [ "$DEW_LIST" = "0" ]; then
  die "You must at least provide the name of an image"
fi

# Read our internal modules, not all independent
MG_LIBPATH=${DEW_ROOTDIR}/libexec:${MG_LIBPATH}
module installer xdg vars inject mkpath user

# Directory where internal scripts are stored and used when setting up
# containers.
DEW_BINDIR=${DEW_ROOTDIR}/bin

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

dockerfile() {
  for d in $(printf %s\\n "$DEW_CONFIG_PATH" | awk '{split($1,DIRS,/:/); for ( D in DIRS ) {printf "%s\n", DIRS[D];} }'); do
    log_trace "Looking for $1 in $d"
    if [ -d "$d" ]; then
      for f in "${d}/${1}.Dockerfile" "${d}/Dockerfile.${1}" "${d}/${1}.df" ; do
        if [ -f "$f" ]; then
          if grep -q '^FROM' "$f"; then
            printf %s\\n "$f"
            return
          else
            log_error "File at $f does not seem to be a Dockerfile"
          fi
        fi
      done
    fi
  done
}

# Print out summary info for configuration file passed as a parameter
summary() {
  printf %s\\n "$(basename "$1")" | sed -E -e 's/.env$//'
  wrap "$(sed -E '/DEW_/q' "$1" | grep -E '^#' | sed -E 's/^#[[:space:]]*//g' | tr '
' ' ')" "  "
  printf \\n
}

wrap() {
  stack_let max=
  stack_let l_indent=
  stack_let wrap="${3:-80}"

  #shellcheck disable=SC2034 # We USE l_indent to compute wrapping max!
  l_lindent=${#2}
  #shellcheck disable=SC2154 # We USE l_indent to compute wrapping max!
  max=$((wrap - l_indent))
  printf "%s\n" "$1" |fold -s -w "$max"|sed -E "s/^(.*)$/$2\\1/g"
  stack_unlet max l_indent wrap
}


# Reverse order of lines (tac emulation, tac is cat in reverse)
# shellcheck disable=SC2120  # no args==take from stdin
tac() {
  awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' "$@"
}

# Start by taking care of the specical case of configuration listing first.
if [ "$DEW_LIST" = "1" ]; then
  if [ "$#" = "0" ]; then
    for d in $(printf %s\\n "$DEW_CONFIG_PATH" | awk '{split($1,DIRS,/:/); for ( D in DIRS ) {printf "%s\n", DIRS[D];} }'); do
      if [ -d "$d" ]; then
        for f in "${d}"/*; do
          if [ -f "$f" ]; then
            if check_config "$f"; then
              summary "$f"
            fi
          fi
        done
      fi
    done
  else
    for i in "$@"; do
      f=$(config "$i")
      if [ -n "$f" ]; then
        summary "$f"
      else
        log_error "$i is not a known configuration"
      fi
    done
  fi
  exit
fi

# Pick a runtime
if [ -z "$DEW_RUNTIME" ]; then
  for r in $DEW_RUNTIMES; do
    if command -v "$r" >/dev/null 2>&1; then
      DEW_RUNTIME=$r
      log_debug "Using $DEW_RUNTIME as runtime"
      break
    fi
  done
  if [ -z "$DEW_RUNTIME" ]; then
    die "Cannot find a container runtime, tried: $DEW_RUNTIMES"
  fi
fi

# Cut out the possible tag/sha256 at the end of the image name and extract the
# main name to be used as part of the automatically generated container name.
# ^((((((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)*(xn--)?([a-z0-9][a-z0-9\-]{0,60}|[a-z0-9-]{1,30}\.[a-z]{2,}))(((:[0-9]+)?)\/?))?)([a-z0-9](\-*[a-z0-9])*(\/[a-z0-9](\-*[a-z0-9])*)*)((:([a-z0-9\_]([\-\.\_a-z0-9])*))|(@sha256:[a-f0-9]{64}))?$
bn=$(basename "$(printf %s\\n "$1" |
                 sed -E 's~((:([a-z0-9_.-]+))|(@sha256:[a-f0-9]{64}))?$~~')")
[ -z "$DEW_NAME" ] && DEW_NAME="dew_${bn}_$$"
DEW_IMAGE=$1
shift; # Jump to the arguments

# Build Docker image, if relevant and collect configuration for name of image
# passed as $1 earlier. We do this in one sweep to be able to override a
# Dockerfile with some dew-specific configuration. This is unlikely to be
# necessary, but maybe of interest anyhow.
DEW_DOCKERFILE=$(dockerfile "$DEW_IMAGE")
if [ -n "$DEW_DOCKERFILE" ]; then
  # Compare digest of dockerfile against digest stored in resulting image and
  # (re-)build if necessary. When building, store the current digest of the
  # Dockerfile.
  digest=$(sha256sum "$DEW_DOCKERFILE"|cut -c "1-$DEW_DIGEST")
  img_digest=$("$DEW_RUNTIME" image inspect --format "{{index .Config.Labels \"${DEW_NAMESPACE%/}/digest\"}}" "${DEW_NAMESPACE%/}/$DEW_IMAGE" || true)
  if ! [ "$digest" = "$img_digest" ]; then
    "$DEW_RUNTIME" image build \
      --file "$DEW_DOCKERFILE" \
      --label "${DEW_NAMESPACE%/}/source=$DEW_DOCKERFILE" \
      --label "${DEW_NAMESPACE%/}/name=$DEW_IMAGE" \
      --label "${DEW_NAMESPACE%/}/digest=$digest" \
      --tag "${DEW_NAMESPACE%/}/$DEW_IMAGE" \
      "$(dirname "$DEW_DOCKERFILE")"
  fi
  DEW_CONFIG=$(config "$DEW_IMAGE")
  DEW_IMAGE="${DEW_NAMESPACE%/}/$DEW_IMAGE"
else
  DEW_CONFIG=$(config "$DEW_IMAGE")
fi


# Read configuration file for the first parameter
DEW_CONFIGDIR=
if [ -n "$DEW_CONFIG" ]; then
  log_info "Reading configuration for $DEW_IMAGE from $DEW_CONFIG"
  # shellcheck disable=SC1090 # The whole point is to have it dynamic!
  . "${DEW_CONFIG}"
  # Restore the variables that were forced through the options
  for v in $_OPTS; do
    eval "$(printf %s\\n "$_ENV" | grep "^${v}=")"
  done
  # shellcheck disable=SC2034 # We will make this available for resolution
  DEW_CONFIGDIR=$(dirname "$DEW_CONFIG")
fi

# Resolve %-enclosed strings (with variable names) in some of our variable
# values. We want to avoid this as much as possible, but this is necessary to
# write configuration files more easily. It is an expensive operation, so we
# only do it if necessary (as it won't be in most cases).
log_trace "Resolving selected vars"
if printf %s\\n "$DEW_OPTS" | grep -Fq '%DEW_'; then
  DEW_OPTS=$(printf %s\\n "$DEW_OPTS"|resolve DEW_)
fi
if printf %s\\n "$DEW_INJECT" | grep -Fq '%DEW_'; then
  DEW_INJECT=$(printf %s\\n "$DEW_INJECT"|resolve DEW_)
fi
if printf %s\\n "$DEW_INJECT_ARGS" | grep -Fq '%DEW_'; then
  DEW_INJECT_ARGS=$(printf %s\\n "$DEW_INJECT_ARGS"|resolve DEW_)
fi
log_trace "Resolved selected vars"

# Rebase (or not) image
if [ -n "$DEW_REBASE" ]; then
  rebased=$("$DEW_REBASER" --verbose notice --base "$DEW_REBASE" --dry-run -- "$DEW_IMAGE")
  if "$DEW_RUNTIME" image inspect "$rebased" >/dev/null 2>&1; then
    log_debug "Rebasing to $rebased already performed, skipping"
    DEW_IMAGE=$rebased
  else
    log_notice "Rebasing $DEW_IMAGE on top of $DEW_REBASE"
    DEW_IMAGE=$("$DEW_REBASER" \
                  --verbose notice \
                  --base "$DEW_REBASE" \
                  -- \
                    "$DEW_IMAGE")
  fi
fi

# Perform injection
if [ -n "$DEW_INJECT" ]; then
  inject "$DEW_INJECT" "$DEW_INJECT_ARGS"
fi

# Download Docker client at the version specified by DEW_DOCKER_VERSION into the
# XDG cache so that it can be injected into the container.
if [ "$DEW_DOCKER" = "1" ]; then
  DEW_DOCKER_VERSION=$(install_docker "$DEW_DOCKER_VERSION")
fi

# Create files/directories prior to starting up the container. This can be used
# to generate (empty) RC files and similar. Format is any number of
# specifications, fields separated by colon sign in order:
# - (full) path to file/directory
# - Type of path to create f or - (or empty, default): file, d: directory
# - Path to template for initial content
# - chmod access, i.e. 0700 or ug+rw. When empty, will be as default
# - Name/Id of owner for path
# - Name/Id of group for path
if [ -n "$DEW_PATHS" ]; then
  for spec in $DEW_PATHS; do
    mkpath "$spec"
  done
fi

log_info "Kickstarting a transient container based on $DEW_IMAGE"

# Remember number of arguments we had after the name of the image.
__DEW_NB_ARGS="$#"

# Pull early so we have something to inspect and reason about as soon as
# necessary.
if ! "$DEW_RUNTIME" image inspect "$DEW_IMAGE" >/dev/null 2>&1; then
  log_debug "Pulling image $DEW_IMAGE"
  "$DEW_RUNTIME" image pull "$DEW_IMAGE"
fi

# When we are using minimal impersonation, we will become our current user
# inside the container. We will use fixuid to map the id of the user:group that
# exists inside the image into our values.
if [ "$DEW_IMPERSONATE" = "minimal" ]; then
  DEW_FIXUID_VERSION=$(install_fixuid "$DEW_FIXUID_VERSION");
  IFS=: read -r __DEW_TARGET_USER __DEW_TARGET_GROUP <<EOF
$(image_user "$DEW_IMAGE")
EOF
  log_debug "Target user and group: ${__DEW_TARGET_USER}:${__DEW_TARGET_GROUP}"
  inject \
    "${DEW_BINDIR}/fixuid.sh" \
    "-u $__DEW_TARGET_USER -g $__DEW_TARGET_GROUP -i /tmp/fixuid_${DEW_FIXUID_VERSION}" \
    -v "${XDG_CACHE_HOME}/dew/fixuid_${DEW_FIXUID_VERSION}:/tmp/fixuid_${DEW_FIXUID_VERSION}:ro"
fi

# Arrange for __DEW_TARGET_USER to be the name or id of the target default user
# in the image. root (the default), will always be stored as 0.
if [ "$DEW_IMPERSONATE" = "1" ]; then
  __DEW_TARGET_USER=$(image_user "$DEW_IMAGE" | cut -d: -f1)
  if ! printf %s\\n "$__DEW_TARGET_USER" | grep -qE '[0-9]+'; then
    if [ -z "$__DEW_TARGET_USER" ] || [ "$__DEW_TARGET_USER" = "root" ]; then
      __DEW_TARGET_USER=0
    fi
  fi
fi

# Insert the image's entrypoint (and when relevant command) in front of the
# arguments when we are going to impersonate (which will replace the
# entrypoint).

__DEW_BASEIMAGE=$(baseimage "$DEW_IMAGE")
if { [ "$DEW_IMPERSONATE" = "1" ] || [ "$DEW_IMPERSONATE" = "minimal" ]; } && { [ -z "$DEW_SHELL" ] || [ "$DEW_SHELL" = "-" ]; }; then
  # Inject the command
  if [ "$__DEW_NB_ARGS" = "0" ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] && set -- "$arg" "$@"
    done <<EOF
$(docker image inspect \
      --format '{{ join .Config.Cmd "\n" }}' "$__DEW_BASEIMAGE" |
  tac)
EOF
  fi
  # Inject the entrypoint
  while IFS= read -r arg; do
    [ -n "$arg" ] && set -- "$arg" "$@"
  done <<EOF
$(docker image inspect \
      --format '{{ join .Config.Entrypoint "\n" }}' "$__DEW_BASEIMAGE" |
  tac)
EOF
fi

# Add image at once
set -- "$DEW_IMAGE" "$@"

# Add blindly any options, these will appear last to be able to override
# anything that dew would have added.
if [ -n "$DEW_OPTS" ]; then
  # shellcheck disable=SC2086 # We want expansion here
  set -- $DEW_OPTS "$@"
fi

# Mount UNIX domain docker socket into container, if relevant. Note in most
# case, the user remapped into the container will also have access to the Docker
# socket (you still have provide a CLI through injecting the Docker client with
# -d)
if [ -n "$DEW_SOCK" ]; then
  set -- -v "${DEW_SOCK}:${DEW_SOCK}" "$@"
fi

# Create and mount XDG directories. We don't only create XDG directories when
# they do not exist, but also an extra directory under them, named after the
# value of DEW_XDG. This provides configuration isolation, as, by default, the
# container will only see the XDG configuration that was explicitely passed, but
# not the content of the other XDG directories.
if [ -n "$DEW_XDG" ]; then
  for type in DATA STATE CONFIG CACHE; do
    d=$(xdg "$DEW_XDG" "$type")
    set -- -v "${d}:${d}" "$@"
    export XDG_${type}_HOME
  done

  d=$(xdg "" RUNTIME DIR 1)
  export XDG_RUNTIME_DIR
  chmod 0700 "$d"
  set -- -v "${d}:${d}" "$@"
fi

# Automatically mount the current directory and make it the current directory
# inside the container as well.
if [ "$DEW_MOUNT" -ge "0" ]; then
  # Climb up from current directory as many levels as DEW_MOUNT: In other words,
  # when DEW_MOUNT is 0, don't climb up. When it is 1, pick up the parent
  # directory, and so on.
  mntdir=$(pwd)
  for _ in $(seq 1 "$DEW_MOUNT"); do
    mntdir=$(dirname "$mntdir")
  done

  set -- \
        -v "${mntdir}:${mntdir}" \
        -w "$(pwd)" \
        "$@"
fi

# When impersonating pass all environment variables that should be to the
# container.
if [ "$DEW_IMPERSONATE" != "0" ]; then
  vars=$(env | grep -oE '^[A-Z][A-Z0-9_]*=' | sed 's/=$//g')
  for v in $vars; do
    if printf %s\\n "$DEW_BLACKLIST" | grep -q "$v"; then
      log_trace "Ignoring environment variable $v from blacklist"
    else
      set -- --env "${v}=$(eval "echo \$$v")" "$@"
    fi
  done
fi

# If requested to have the docker client, download it if necessary and mount it
# under /usr/local/bin inside the container so it is accessible at the path and
# the prompt (or other programs).
if [ "$DEW_DOCKER" = "1" ]; then
  if [ -f "${XDG_CACHE_HOME}/dew/docker_$DEW_DOCKER_VERSION" ]; then
    set -- -v "${XDG_CACHE_HOME}/dew/docker_${DEW_DOCKER_VERSION}:${DEW_INSTALLDIR%/}/docker:ro" "$@"
  fi
fi

if is_true "$DEW_INTERACTIVE" || \
    { [ "$(to_lower "$DEW_INTERACTIVE")" = "auto" ] && \
      [ "$__DEW_NB_ARGS" = "0" ]; }; then
  set -- \
        -it \
        -a stdin -a stdout -a stderr \
        "$@"
fi

if [ "$DEW_RUNTIME" = "podman" ]; then
  if [ "$DEW_IMPERSONATE" = "1" ]; then
    if [ "$MG_VERBOSITY" = "trace" ]; then
      set -- -e "DEW_DEBUG=1" "$@"
    fi
    if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
      set -- \
            -e "HOME=$HOME" \
            -e "USER=$USER" \
            --entrypoint "$DEW_SHELL" \
            "$@"
    else
      set -- \
            -e "HOME=$HOME" \
            -e "USER=$USER" \
            "$@"
    fi
  else
    if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
      set -- \
        --entrypoint "$DEW_SHELL" \
        "$@"
    fi
  fi
else
  if [ "$DEW_IMPERSONATE" = "minimal" ]; then
    # Minimal impersonation, we will run container as our user and group
    set -- -u "$(id -u):$(id -g)" "$@"
    # Make sure that whatever would have been requested to be run is run through
    # fixuid. We have to resort to using an entrypoint and a file containing
    # what to execute because it is not possible to use the "exec" form from the
    # command-line docker client --entrypoint.
    cmds=$(mktemp -t "dew_XXXXXX")
    printf 'fixuid\n-q\n' > "$cmds"
    set -- \
          -v "${cmds}:/etc/dew.cmd:ro" \
          -v "${DEW_BINDIR}/entrypoint.sh:/tmp/dew-entrypoint.sh:ro" \
          --entrypoint "/tmp/dew-entrypoint.sh" \
          "$@"
    # When we have to override the entrypoint, push it to the list of commands
    # to execute.
    if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
      printf %s\\n "$DEW_SHELL" >> "$cmds"
    fi
  elif [ "$DEW_IMPERSONATE" = "1" ]; then
    # We will become root to be able to run su.sh and then become "ourselves"
    # inside the container.
    if [ "$__DEW_TARGET_USER" != "0" ]; then
      set -- -u "root" "$@"
    fi
    if [ "$MG_VERBOSITY" = "trace" ]; then
      set -- -e "DEW_DEBUG=1" "$@"
    fi
    if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
      set -- \
            -v "${DEW_BINDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro" \
            -e DEW_UID="$(id -u)" \
            -e DEW_GID="$(id -g)" \
            -e "DEW_SHELL=$DEW_SHELL" \
            -e "HOME=$HOME" \
            -e "USER=$USER" \
            --entrypoint "${DEW_INSTALLDIR%/}/su.sh" \
            "$@"
    else
      # Now inject sh.sh as the entrypoint, it will pick the entrypoint and the
      # command that we have just added.
      set -- \
            -v "${DEW_BINDIR}/su.sh:${DEW_INSTALLDIR%/}/su.sh:ro" \
            -e DEW_UID="$(id -u)" \
            -e DEW_GID="$(id -g)" \
            -e "HOME=$HOME" \
            -e "USER=$USER" \
            --entrypoint "${DEW_INSTALLDIR%/}/su.sh" \
            "$@"
    fi
  else
    if [ -n "$DEW_SHELL" ] && [ "$DEW_SHELL" != "-" ]; then
      set -- \
        --entrypoint "$DEW_SHELL" \
        "$@"
    fi
  fi
fi

# The base command is to arrange for the container to automatically be removed
# once stopped, to add an init system to make sure we can capture signals and to
# share the host network.
for feature in $DEW_FEATURES; do
  impl=$(value_of "$feature" < "$DEW_FEATURES_CONFIG")
  if [ -n "$impl" ]; then
    # shellcheck disable=SC2086 # We want word splitting!
    set -- $impl "$@"
  fi
done
set -- --name "$DEW_NAME" "$@"
if [ "$DEW_RUNTIME" = "podman" ]; then
  set -- "$DEW_RUNTIME" run --userns=keep-id "$@"
else
  set -- "$DEW_RUNTIME" run "$@"
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
log_trace "Running: $*"

# Remove all temporary XDG stuff. Done here to avoid sub-shell exiting to
# trigger cleanup.
if [ -z "$DEW_XDG" ]; then
  at_exit rm -rf "${TMPDIR:-/tmp}/tmp-${MG_CMDNAME}-$$-*"
fi

# Now run the docker command
exec "$@"
