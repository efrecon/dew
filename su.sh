#!/bin/sh
# Note the shebang MUST be /bin/sh as this is what can be found in busybox,
# where there is no /usr/bin.

# This script will "descend" privileges to the user which name is present in the
# variable "$USER". It is injected in containers from dew in order to establish
# a minimal environment in the form of a HOME folder and an existing user.
set -eu

# Name of the docker group, when arranging for the user to be part of that
# group, so that it can access the UNIX domain socket also injected in the
# container.
DOCKER_GROUP=${DOCKER_GROUP:-docker}

# Path to the UNIX domain socket for communication with the Docker daemon on the
# host. Whenever relevant, the group id carried by the socket will also be given
# to the group being created.
DOCKER_SOCKET=${DOCKER_SOCKET:-/var/run/docker.sock}

# When set, this will print some extra logging around user/group creation and
# shell detection. The variable will be set when verbosity is set to trace.
DEW_DEBUG=${DEW_DEBUG:-0}

# Log the text passed as a paramter whenever DEW_DEBUG is 1
log() { [ "$DEW_DEBUG" = "1" ] && printf %s\\n "$1" >&2 || true; }

silent() {
  if [ "$DEW_DEBUG" = "0" ]; then
    "$@" > /dev/null
  else
    "$@"
  fi

}

# Return the name of the Linux distribution group this is running on, in
# lowercase.
distro() {
  if [ -r "/etc/os-release" ]; then
    if grep -Eq '^ID_LIKE=' /etc/os-release; then
      # shellcheck disable=SC1091 # /etc/os-release is standardised
      lsb_dist=$(. /etc/os-release && printf %s\\n "$ID_LIKE" | awk '{print $1};')
    else
      # shellcheck disable=SC1091 # /etc/os-release is standardised
      lsb_dist=$(. /etc/os-release && printf %s\\n "$ID")
    fi
    printf %s\\n "$lsb_dist" | tr '[:upper:]' '[:lower:]'
  fi
}

# Create a user group called $USER with the identifier $DEW_GID
create_group() {
  if [ -z "$(group_name "$2")" ]; then
    log "Adding group $1 with gid $2"
    case "$DEW_DISTRO" in
      debian*)
        silent addgroup -q --gid "$2" "$1";;
      alpine*)
        silent addgroup -g "$2" "$1";;
      rhel | centos | fedora)
        silent groupadd -g "$2" "$1";;
      *)
        # Go old style, just add an entry to the /etc/group file
        printf "%s:x:%d:\n" "$1" "$2" >> /etc/group;;
    esac
  fi
  group_name "$2"
}

# Make user $1 member of group $2
group_member() {
  if grep -qE "^${2}:" /etc/group; then
    case "$DEW_DISTRO" in
      debian*)
        silent adduser -q "$1" "$2";;
      alpine*)
        silent addgroup "$1" "$2";;
      rhel | centos | fedora)
        silent groupmems -a "$1" -g "$2";;
      *)
        # Go old style, just modify the /etc/group file
        gid=$(grep -E "^${2}:" /etc/group|cut -d: -f3)
        if grep -q "^${2}:" /etc/group | grep -E ':$'; then
          sed -i -e "s/${2}:x:${gid}:/${2}:x:${gid}:${1}/" /etc/group
        else
          sed -iE -e "s/${2}:x:${gid}:(.*)/${2}:x:${gid}:\1,${1}/" /etc/group
        fi
        ;;
    esac
  else
    log "Group $2 does not exist!"
  fi
}

db_get() {
  if cmd_exists "getent"; then
    getent "$1" "$2"
  else
    if printf %s\\n "$2" | grep -qE '^[0-9]+$'; then
      field=3
    else
      field=1
    fi
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

# Create a user $USER, belonging to the group of the same name (created by
# function above), with identifier $DEW_UID and shell $SHELL, as detected at the
# when this script starts
create_user() {
  if [ -z "$(user_name "$DEW_UID")" ]; then
    log "Adding user $USER with id $DEW_UID to /etc/passwd. Shell: $SHELL"
    case "$DEW_DISTRO" in
      debian*)
        silent adduser \
          -q \
          --home "$HOME" \
          --shell "$SHELL" \
          --gid "$DEW_GID" \
          --disabled-password \
          --uid "$DEW_UID" \
          --gecos "" \
          "$USER";;
      alpine*)
        # Alpine uses the name of the group, which is the same as the user in our
        # case.
        silent adduser \
          -h "$HOME" \
          -s "$SHELL" \
          -G "$(group_name "$DEW_GID")" \
          -D \
          -u "$DEW_UID" \
          -g "" \
          "$USER";;
      rhel | centos | fedora)
        silent useradd \
          --home-dir "$HOME" \
          --shell "$SHELL" \
          --gid "$DEW_GID" \
          --password "" \
          --uid "$DEW_UID" \
          --no-create-home \
          --comment "" \
          "$USER";;
      *)
        # Go old style, just add an entry to the /etc/passwd file
        printf "%s:x:%d:%d::%s:%s\\n" \
              "$USER" \
              "$DEW_UID" \
              "$DEW_GID" \
              "$HOME" \
              "$SHELL" >> /etc/passwd;;
    esac
  fi
  user_name "$DEW_UID"
}


cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Decide upon a good plausible shell to run, the order might be questionable,
# but this covers a large set of distributions and shells.
SHELL=
for s in bash ash sh; do
  if cmd_exists "$s"; then
    SHELL=$(command -v "$s")
    break
  fi
done
log "Default shell detected as $SHELL"

if [ "${USER:-}" = "root" ] || [ -z "${USER:-}" ]; then
  # When running as root or an unknown user, we just replace ourselves with
  # either the default shell that we guessed existed in the container, or with
  # the one forced in from the outside by dew.
  if [ -n "${DEW_SHELL:-}" ]; then
    log "Replacing ourselves with $DEW_SHELL $*"
    exec "$DEW_SHELL" "$@"
  else
    log "Replacing ourselves with $SHELL $*"
    exec "$SHELL" "$@"
  fi
else
  # Otherwise (and ... in most cases), arrange for a minimal environment to
  # exist in the container before becoming the requested user and elevating down
  # to lesser privileges.

  # Discover distro, will be used in functions
  DEW_DISTRO=$(distro)

  # Create a home for the user and make sure it is accessible for RW
  if [ -n "$HOME" ] && ! [ -d "$HOME" ]; then
    log "Creating home directory $HOME"
    mkdir -p "$HOME"
  fi
  if [ -n "$HOME" ] && [ -d "$HOME" ]; then
    log "Changing owner of $HOME to ${DEW_UID:-0}:${DEW_GID:-0}"
    chown "${DEW_UID:-0}:${DEW_GID:-0}" "${HOME}"
    chmod ug+rwx "$HOME"
  fi

  # If a group identifier was specified, arrange for the group to exist. The
  # group will be named after the user. Once done, create a user inside that
  # group.
  if [ -f "/etc/group" ] && [ -n "${DEW_GID:-}" ]; then
    silent create_group "$USER" "$DEW_GID"

    # Create the user if it does not already exist. Arrange for the default
    # shell to be the one discovered at the beginning of this script. If a user
    # with that UID already exists, switch the username to the one already
    # registered for the UID, as nothing else would work.
    if [ -f "/etc/passwd" ] && [ -n "${DEW_UID:-}" ]; then
      CUSER=$(create_user)
      if [ "$CUSER" != "$USER" ]; then
        CHOME=$(db_get passwd "$CUSER" | cut -d: -f6)
        log "Image user $CUSER different from caller, linking $CHOME to $HOME"
        rm -rf "$CHOME"
        ln -sf "$HOME" "$CHOME"
        USER=$CUSER
      fi
    fi
  fi

  # Arrange for the user to be part of the Docker group by creating the group
  # and letting the user to be a member of the group. We are able to cope with
  # the fact that there might already be a group with the same id within the
  # container, in which case, we just reuse its name so we can map onto the
  # host's group.
  if [ -f "/etc/group" ] && \
      ! cut -d: -f1 /etc/group | grep -q "^${DOCKER_GROUP}:" && \
      [ -S "$DOCKER_SOCKET" ]; then
    dgid=$(stat -c '%g' "$DOCKER_SOCKET")
    log "Making user $USER member of the group $DOCKER_GROUP with id $dgid to /etc/passwd"
    silent create_group "$DOCKER_GROUP" "$dgid" || true
    silent group_member "$USER" "$(group_name "$dgid")" || true
  fi

  # Now run an interactive shell with lesser privileges, i.e. as the user that
  # we have just created. This will either be the default shell, or the one
  # specified from the outside by dew. In theory, there is a missing "else"
  # branch to the if-statement, but even busybox has an implementation of su!
  # This script would however fail in bare environments, i.e. raw images with a
  # single binary in them.
  if command -v "sudo" >/dev/null 2>&1; then
    if [ -z "${DEW_SHELL:-}" ]; then
      log "Becoming $USER, running $* with sudo"
      exec sudo -u "$USER" -- "$@"
    else
      log "Becoming $USER, running $DEW_SHELL $* (at: $(command -v "$DEW_SHELL")) with sudo"
      exec sudo -u "$USER" -- "$(command -v "$DEW_SHELL")" "$@"
    fi
  elif command -v "su" >/dev/null 2>&1; then
    # Create a temporary script that will call the remaining of the arguments,
    # with the DEW_SHELL prefixed if relevant. This is because su is evil and -c
    # option only takes a single command...
    tmpf=$(mktemp)
    printf '#!%s\n' "$SHELL" > "$tmpf"
    printf "exec" >> "$tmpf"
    if [ -n "${DEW_SHELL:-}" ]; then
      printf ' "%s"' "$DEW_SHELL" >> "$tmpf"
    fi
    for a in "$@"; do
      [ -n "$a" ] && printf ' "%s"' "$a" >> "$tmpf"
    done
    printf \\n >> "$tmpf"
    chmod a+rx "$tmpf"
    log "Becoming $USER, running ${DEW_SHELL:-} $* with su"
    exec su -c "$tmpf" "$USER"
  else
    log "Can neither find su, nor sudo"
    exit 1
  fi
fi
