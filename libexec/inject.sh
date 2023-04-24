#!/bin/sh

module log utils


# Is image passed as a parameter an injected image
injected() {
  printf %s\\n "$1" | grep -qE ":${DEW_INJECT_TAG_PREFIX}[a-f0-9]{12}_[a-f0-9]{12}\$"
}

# Return name of original image, when injected image, or the name of the image
baseimage() {
  if injected "$1"; then
    "${DEW_RUNTIME}" image inspect --format '{{ .Comment }}' "$1"
  else
    printf %s\\n "$1"
  fi
}


# Inject a command in the current image and save the result in a new image that
# will be used for all further operations. The command is always executed as
# root inside the original image.
inject() {
  # Extract the raw (untagged) name of the image
  img=$(printf %s\\n "$DEW_IMAGE" | sed -E 's~((:([a-z0-9_.-]+))|(@sha256:[a-f0-9]{64}))?$~~')

  # Use or create a shell script to run the command
  if [ -f "$1" ]; then
    tmpdir=
    injector=$1
  else
    tmpdir=$(mktemp -d)
    printf '#!/bin/sh\n' > "${tmpdir}/init.sh"
    printf %s\\n "$1" >> "${tmpdir}/init.sh"
    chmod a+x "${tmpdir}/init.sh"
    injector="${tmpdir}/init.sh"
    log_debug "Created temporary injection script: $injector"
  fi
  injector_args=${2:-}
  shift 2

  # Compute a shortened hash for the script to inject and its arguments, we will
  # use them as part of the tag for the image.
  sum_cmd=$(digest < "$injector")
  sum_args=$(printf %s\\n "$injector_args" | digest)
  injected_img=$(printf %s:%s%s_%s\\n "$img" "$DEW_INJECT_TAG_PREFIX" "$sum_cmd" "$sum_args")

  # When we already have an injected image, don't do anything. Otherwise, run a
  # container based on the original image with the entrypoint being the script
  # to run. Once done, save the image and make this the image that we are going
  # to use for further operations.
  if ! "${DEW_RUNTIME}" image inspect "$injected_img" >/dev/null 2>&1; then
    # Remove prior images to keep diskspace low. Iterate across all images with
    # the same name, if any. For all that have a tag that starts with the
    # injection prefix and have the name of the image in comment, remove them.
    # Note that this might remove a bit too much, as it does not take the
    # injection arguments into account.
    if [ "$DEW_INJECT_CLEANUP" = "1" ]; then
      log_debug "Removing dangling injected siblings..."
      "${DEW_RUNTIME}" image ls --format '{{ .Tag }}' "$img" | while IFS= read -r tag; do
        if printf %s\\n "$tag" | grep -qE "^$DEW_INJECT_TAG_PREFIX"; then
          if [ "$(baseimage "${img}:${tag}")" = "$DEW_IMAGE" ] && [ "${img}:${tag}" != "$DEW_IMAGE" ]; then
            if "${DEW_RUNTIME}" image rm -f "${img}:${tag}" >/dev/null; then
              log_info "Removed dangling injected image ${img}:${tag}"
            else
              log_warn "Could not remove dangling injected image ${img}:${tag}, still having a container running?"
            fi
          fi
        fi
      done
    fi

    DEW_INJECT=$(readlink_f "$injector")
    # Create a container, with the injection script as an entrypoint. Let it run
    # until it exits. Once done, use the stopped container to generate a new
    # image, then remove the (temporary) container entirely.
    log_info "Injecting $injector $injector_args into $DEW_IMAGE, generating local image for future runs"
    "${DEW_RUNTIME}" run \
      -u 0 \
      -v "$(dirname "$injector"):$(dirname "$injector"):ro" \
      --entrypoint "$injector" \
      --name "$DEW_NAME" \
      "$@" \
      -- \
      "$DEW_IMAGE" \
      $injector_args
    log_debug "Run $injector $injector_args in $DEW_IMAGE, generated container $DEW_NAME"
    "${DEW_RUNTIME}" commit \
      --message "$(baseimage "$DEW_IMAGE")" \
      -- \
      "$DEW_NAME" "$injected_img" >/dev/null
    log_debug "Generated local image $injected_img for future runs"
    "$DEW_RUNTIME" rm --volumes "$DEW_NAME" >/dev/null
  fi

  # Replace the image for further operations and then cleanup.
  log_info "Using injected image $injected_img instead of $DEW_IMAGE"
  DEW_IMAGE=$injected_img
  if [ -n "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}
