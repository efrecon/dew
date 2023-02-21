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
  grep -E "^${1}\s*=" |
    head -n 1 |
    var_val "$1"
}

# This is an expansion safe envsubst implementation in pure-shell and inspired
# by https://stackoverflow.com/a/40167919. It uses eval in a controlled-manner
# to avoid side-effects.
# shellcheck disable=SC2120
_envsubst() {
    if [ "$#" -gt "0" ]; then
        printf %s\\n "$1" | _envsubst
    else
        # Prepare a sed script that will replace all occurrences of the known
        # environment variables by their value
        _sed=$(mktemp)
        while IFS='=' read -r var val; do
            for separator in ! ~ ^ % \; /; do
                if ! printf %s\\n "$val" | grep -qo "$separator"; then
                    printf 's%s\x04%s%s%s%sg\n' \
                        "$separator" "$var" "$separator" "$val" "$separator" >> "$_sed"
                    break
                fi
            done
        done <<EOF
$(env|grep -E '^[0-9[:upper:]][0-9[:upper:]_]*=')
EOF

        while IFS= read -r line || [ -n "$line" ]; do  # Read, incl. non-empty last line
            # Transpose all chars that could trigger an expansion to control
            # characters, and perform expansion using the script above for pure
            # variable substitutions. Once done, transpose only the ${ back to
            # what they should (and escape the double quotes)
            _line=$(printf %s\\n "$line" |
                        tr '`([$' '\1\2\3\4' |
                        sed -f "$_sed" |
                        sed -e 's/\x04{/${/g' -e 's/"/\\\"/g')
            # At this point, eval is safe, since the only expansion left is for
            # ${} contructs. Perform the eval and convert back the control
            # characters to the real chars.
            eval "printf '%s\n' \"$_line\"" | tr '\1\2\3\4' '`([$'
        done

        # Get rid of the temporary sed script
        rm -f "$_sed"
    fi
}

# Resolve the value of % enclosed variables with their content in the incoming
# stream. Do this only for "our" variables, i.e. the ones from this script.
resolve() {
  stack_let subset
  subset=${1:-"[A-Z0-9_]+="}
  set --
  # Construct a set of -e sed expressions. Build these onto the only array that
  # we have, i.e. the one to carry incoming arguments.
  while IFS='=' read -r var val; do
    # remove the leading and ending quotes out of the value coming from set, we
    # could run through eval here, but it'll be approx as many processes (so no
    # optimisation possible)
    val=$(printf %s\\n "$val" | unquote)
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
