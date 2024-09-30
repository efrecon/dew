#!/bin/sh

# shellcheck disable=SC2120 # We are fine with the default in this script!
digest() {
  sha256sum | grep -Eo '[0-9a-f]+' | cut -c -"${1:-$DEW_DIGEST}"
}

# Reverse order of lines (tac emulation, tac is cat in reverse)
# shellcheck disable=SC2120  # no args==take from stdin
tac() {
  awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' "$@"
}

# Generate a bindmount option, arrange for Z to be passed as an option when
# using podman.
bindmount() {
  stack_let src
  stack_let dst
  stack_let opt

  src=$1
  if [ -z "${2:-}" ]; then
    dst=$1
  else
    dst=$2
  fi

  if [ "$DEW_RUNTIME" = "podman" ]; then
    if [ -n "${3:-}" ]; then
      opt="$3,Z"
    else
      opt=Z
    fi
  elif [ -n "${3:-}" ]; then
    opt="$3"
  fi

  if [ -n "${opt:-}" ]; then
    printf '%s:%s:%s\n' "$src" "$dst" "$opt"
  else
    printf '%s:%s\n' "$src" "$dst"
  fi

  stack_unlet src
  stack_unlet dst
  stack_unlet opt
}