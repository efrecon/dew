#!/bin/sh

module log

# Single argument: fields separated by colon sign in order:
# - (full) path to file/directory
# - Type of path to create f or - (or empty, default): file, d: directory
# - Path to template for initial content
# - chmod access, i.e. 0700 or ug+rw. When empty, will be as default
# - Name/Id of owner for path
# - Name/Id of group for path
mkpath() {
  path=$(printf %s::::::\\n "$1" | cut -d: -f1)
  if [ -n "$path" ]; then
    type=$(printf %s::::::\\n "$1" | cut -d: -f2)
    template=$(printf %s::::::\\n "$1" | cut -d: -f3)
    if [ -n "$template" ]; then
      template=$(printf %s\\n "$template"|resolve)
    fi
    case "$type" in
      f | - | "")
        if [ -n "$template" ] && [ -f "$template" ]; then
          log_debug "Copying template $template to $path"
          cp "$template" "$path"
        else
          log_debug "Creating empty file: $path"
          touch "$path"
        fi
        ;;
      d )
        if [ -n "$template" ] && [ -d "$template" ]; then
          log_debug "Copying template files from $template to $path"
          mkdir -p "$path"
          cp -a "${template%/}"/* "$path"
        else
          log_debug "Creating directory: $path"
          mkdir -p "$path"
        fi
        ;;
      * )
        log_warn "$type is not a recognised path type!";;
    esac

    if [ -f "$path" ] || [ -d "$path" ]; then
      chmod=$(printf %s::::::\\n "$1" | cut -d: -f4)
      if [ -n "$chmod" ]; then
        chmod -R "$chmod" "$path"
      fi
      owner=$(printf %s::::::\\n "$1" | cut -d: -f5)
      group=$(printf %s::::::\\n "$1" | cut -d: -f6)
      if [ -n "$owner" ] && [ -n "$group" ]; then
        chown -R "${owner}:${group}" "$path"
      elif [ -n "$owner" ]; then
        chown -R "${owner}" "$path"
      elif [ -n "$group" ]; then
        chgrp -R "${group}" "$path"
      fi
    else
      log_error "Could not create path $path"
    fi
  fi
}
