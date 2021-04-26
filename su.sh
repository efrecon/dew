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
log() {
  if [ "$DEW_DEBUG" = "1" ]; then
    printf %s\\n "$1" >/dev/stderr
  fi
}

# Return the name of the Linux distribution this is running on, in lowercase.
distro() {
  if [ -r "/etc/os-release" ]; then
    # shellcheck disable=SC1091 # /etc/os-release is standardised
    lsb_dist=$(. /etc/os-release && printf %s\\n "$ID")
    printf %s\\n "$lsb_dist" | tr '[:upper:]' '[:lower:]'
  fi
}

# Create a user group called $USER with the identifier $DEW_GID
create_group() {
  log "Adding group $USER with id $DEW_GID to /etc/group"
  case "$(distro)" in
    ubuntu* | debian*)
      addgroup -q --gid "$DEW_GID" "$USER";;
    alpine*)
      addgroup -g "$DEW_GID" "$USER";;
    fedora)
      groupadd -g "$DEW_GID" "$USER";;
    *)
      # Go old style, just add an entry to the /etc/group file
      printf "%s:x:%d:\n" "$USER" "$DEW_GID" >> /etc/group;;
  esac
}

# Create a user $USER, belonging to the group of the same name (created by
# function above), with identifier $DEW_UID and shell $SHELL, as detected at the
# when this script starts
create_user() {
  log "Adding user $USER with id $DEW_UID to /etc/passwd. Shell: $SHELL"
  case "$(distro)" in
    ubuntu* | debian*)
      adduser \
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
      adduser \
        -h "$HOME" \
        -s "$SHELL" \
        -G "$USER" \
        -D \
        -u "$DEW_UID" \
        -g "" \
        "$USER";;
    fedora)
      useradd \
        --home-dir "$HOME" \
        --shell "$SHELL" \
        --gid "$DEW_GID" \
        --password "" \
        --uid "$DEW_UID" \
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

}


# Decide upon a good plausible shell to run, the order might be questionable,
# but this covers a large set of distributions and shells.
SHELL=
for s in bash ash sh; do
  if command -v "$s" >/dev/null 2>&1; then
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
    log "Replacing ourselves with $DEW_SHELL"
    exec "$DEW_SHELL"
  else
    log "Replacing ourselves with $SHELL"
    exec "$SHELL"
  fi
else
  # Otherwise (and ... in most cases), arrange for a minimal environment to
  # exist in the container before becoming the requested user and elevating down
  # to lesser privileges.

  # Create a home for the user and make sure it is accessible for RW
  if [ -n "$HOME" ]; then
    log "Creating home directory $HOME, owned by ${DEW_UID:-0}:${DEW_GID:-0}"
    mkdir -p "$HOME"
    chown "${DEW_UID:-0}:${DEW_GID:-0}" "${HOME}"
    chmod ug+rwx "$HOME"
  fi

  # If a group identifier was specified, arrange for the group to exist. The
  # group will be named after the user. Once done, create a user inside that
  # group.
  if [ -n "${DEW_GID:-}" ]; then
    if [ -f "/etc/group" ]; then
      # Create the group if it does not already exist at the same GID
      if ! cut -d: -f3 /etc/group | grep -q "$DEW_GID"; then
        create_group
      fi
    fi

    # Create the user if it does not already exist. Arrange for the default
    # shell to be the one discovered at the beginning of this script.
    if [ -f "/etc/passwd" ] && [ -n "${DEW_UID:-}" ]; then
      if ! cut -d: -f1 /etc/passwd | grep -q "$USER"; then
        create_user
      fi
    fi
  fi

  # Arrange for the user to be part of the Docker group by creating the group
  # and letting the user to be a member of the group.
  if [ -f "/etc/group" ] && \
      ! cut -d: -f1 /etc/group | grep -q "^${DOCKER_GROUP}:" && \
      [ -S "$DOCKER_SOCKET" ]; then
    dgid=$(stat -c '%g' "$DOCKER_SOCKET")
    log "Making user $USER member of the group $DOCKER_GROUP with id $dgid to /etc/passwd"
    printf "${DOCKER_GROUP}:x:%d:%s\n" "$dgid" "$USER" >> /etc/group
  fi

  # Now run an interactive shell with lesser privileges, i.e. as the user that
  # we have just created. This will either be the default shell, or the one
  # specified from the outside by dew. In theory, there is a missing "else"
  # branch to the if-statement, but even busybox has an implementation of su!
  # This script would however fail in bare environments, i.e. raw images with a
  # single binary in them.
  if command -v "su" >/dev/null 2>&1; then
    if [ -z "${DEW_SHELL:-}" ]; then
      log "Becoming $USER, running $SHELL as set in /etc/passwd"
      exec su "$USER"
    else
      log "Becoming $USER, running $DEW_SHELL"
      exec su -s "$(command -v "$DEW_SHELL")" "$USER"
    fi
  else
    log "Cannot find su"
    exit 1
  fi
fi
