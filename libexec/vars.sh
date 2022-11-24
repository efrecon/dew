#!/bin/sh

module log locals

# Remove leading and ending quote pairs from all lines when both are present. Do
# this a finite number of times. The implementation uses shell builtins as
# much as possible as an optimisation.
# shellcheck disable=SC2120    # We never use the param, but good to have!
unquote() {
  stack_let _iter
  stack_let line
  while IFS= read -r line; do
    for _iter in $(seq 1 "${1:-6}"); do
      if [ "${line#\'}" != "$line" ] && [ "${line%\'}" != "$line" ]; then
        line=${line#\'}
        line=${line%\'}
      elif [ "${line#\"}" != "$line" ] && [ "${line%\"}" != "$line" ]; then
        line=${line#\"}
        line=${line%\"}
      else
        break
      fi
    done
    printf %s\\n "$line"
  done
  stack_unlet _iter
  stack_unlet line
}

# Isolate the value of variables passed on stdin, i.e. remove XXX= from the
# lines. The default is to assume variables are all uppercase.
var_val() { sed -E -e "s/^${1:-"[A-Z_]+"}\s*=\s*//" | unquote ; }

# Get the value of the variable passed as a parameter, without running eval,
# i.e. through picking from the result of set
value_of() {
  # This forces in the exact name of the variable by performing a grep call that
  # contains both the name of the variable to look for AND the equal sign.
  set |
    grep -E "^${1}\s*=" |
    head -n 1 |
    var_val "$1"
}

# Resolve the value of % enclosed variables with their content in the incoming
# stream. Do this only for "our" variables, i.e. the ones from this script.
resolve() {
  stack_let subset
  subset=${1:-"[A-Z_]+"}
  set --
  # Construct a set of -e sed expressions. Build these onto the only array that
  # we have, i.e. the one to carry incoming arguments.
  while IFS= read -r line; do
    # Get the name of the variable, i.e. everything in uppercase before the
    # equal sign printed out by set.
    var=$(printf %s\\n "$line" | grep -Eo '^[A-Z_]+')
    # remove the leading and ending quotes out of the value coming from set, we
    # could run through eval here, but it'll be approx as many processes (so no
    # optimisation possible)
    val=$(printf %s\\n "$line" | var_val "$var")
    # Construct a sed expression using a non-printable separator (the vertical
    # tab) so we minimise the risk of its presence in the value.
    set -- -e "s%${var}%${val}g" "$@"
  done <<EOF
$(set | grep -E "^${subset}")
EOF
  # Build the final sed command and execute it, it will perform all
  # substitutions in one go and dump them onto the stdout.
  stack_unlet subset
  set -- sed "$@"
  exec "$@"
}
