#!/bin/sh

module log vars

# Create the XDG directory of type $2 for the tool named $1.
xdg() (
  if [ -z "${1:-}" ]; then
    d=$(set|value_of "XDG_${2}_${3:-HOME}")
  else
    d=$(set|value_of "XDG_${2}_${3:-HOME}")/$1
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
