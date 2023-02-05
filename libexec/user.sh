#!/bin/sh

# Query image for the user:group to be used. This will peek into the
# /etc/password file to discover if a used is created in the image and pick that
# one whenever it exists.
_query_user() {
  _qimg=$1; shift
  uspec=$("${DEW_RUNTIME}" run --rm -v "${DEW_BINDIR}/prefuser.sh:/tmp/prefuser.sh:ro" --entrypoint /tmp/prefuser.sh "$_qimg" "$@")
  if [ -z "$uspec" ]; then
    printf 0:0\\n
  else
    printf %s\\n "$uspec"
  fi
}

# Return user:group to use with the passed as a parameter. This is able to guess
# a good user out of the ones created inside the image.
_image_user() {
  img_user=$("${DEW_RUNTIME}" image inspect --format '{{ .Config.User }}' "$1")
  if printf %s\\n "$img_user" | grep -qF ':'; then
    printf %s\\n "$img_user"
  elif [ -z "$img_user" ]; then
    _query_user "$1"
  elif [ "$img_user" = "0" ]; then
    _query_user "$1"
  else
    _query_user "$1" 0
  fi
}

image_user() {
  # Location of the image user/group cache
  _cache=${XDG_CACHE_HOME}/dew/images.usr

  if [ -f "$_cache" ]; then
    if grep -qF "$1" "$_cache"; then
      log_trace "Returning user and group for $1 from cache at $_cache"
      grep -F "$1" "$_cache" | cut -f2
    else
      _user_group=$(_image_user "$1")
      printf '%s\t%s\n' "$1" "$_user_group" >> "$_cache"
      log_trace "Cached user and group for $1: $_user_group to cache at $_cache"
      printf %s\\n "$_user_group"
    fi
  else
    _user_group=$(_image_user "$1")
    printf '%s\t%s\n' "$1" "$_user_group" >> "$_cache"
    log_trace "Cached user and group for $1: $_user_group to cache at $_cache"
    printf %s\\n "$_user_group"
  fi
}