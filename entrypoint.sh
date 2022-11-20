#!/bin/sh

# File to read command from. Each line will be an argument
ENTRYPOINT_CMDFILE=${ENTRYPOINT_CMDFILE:-"/etc/dew.cmd"}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 read command from file and execute" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "c:h-" opt; do
  case "$opt" in
    h) # Print help and exit
      usage;;
    c) # Path to file
      ENTRYPOINT_CMDFILE="$OPTARG";;
    -) # End of options, everything after blindly appended to command
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))


if [ -f "$ENTRYPOINT_CMDFILE" ]; then
  while IFS= read -r cmd; do
    set -- "$cmd" "$@"
  done <<EOF
$(awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' "$ENTRYPOINT_CMDFILE")
EOF
fi

exec "$@"
