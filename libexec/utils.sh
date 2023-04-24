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
