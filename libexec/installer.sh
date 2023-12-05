#!/bin/sh

module log xdg locals


# Download the url passed as the first argument to the destination path passed
# as a second argument. The destination will be the same as the basename of the
# URL, in the current directory, if omitted.
download() {
  if command -v curl >/dev/null; then
    curl -sSL -o "${2:-$(basename "$1")}" "$1"
  elif command -v wget >/dev/null; then
    wget -q -O "${2:-$(basename "$1")}" "$1"
  fi
}


# Guess version of GH project passed as a parameter using the tags in the HTML
# description.
gh_version() {
  log_debug "Guessing latest stable version for project $1"
  # This works on the HTML from GitHub as follows:
  # 1. Start from the list of tags, they point to the corresponding release.
  # 2. Extract references to the release page, force a possible v and a number
  #    at start of sub-path
  # 3. Use slash and quote as separators and extract the tag/release number with
  #    awk. This is a bit brittle.
  # 4. Remove leading v, if there is one (there will be in most cases!)
  # 5. Extract only pure SemVer sharp versions
  # 6. Just keep the top one, i.e. the latest release.
  download "${DEW_GITHUB}/${1}/tags" -|
    grep -Eo "<a href=\"/${1}/releases/tag/v?[0-9][^\"]*" |
    awk -F'[/\"]' '{print $7}' |
    sed 's/^v//g' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -n -r |
    head -1
}

# Path to latest downloaded tool in cache, i.e. sorted by modification date.
_latest_downloaded() {
  find "${XDG_CACHE_HOME}/dew" -name "${1}_*" -print |
    while IFS='
' read -r fpath; do
      printf '%d %s\n' "$(stat -c %Y "$fpath")" "$fpath"
    done |
    sort -n -k 1 -r |
    head -1 |
    sed -E 's/^[0-9]+ //g'
}

# Remove obsolete binaries from cache. Args: $1 is the name of the tool, e.g.
# docker
_rm_obsolete() {
  stack_let now
  stack_let touched
  stack_let elapsed

  if [ -n "$DEW_BINCACHE_EXPIRE" ] && [ "$DEW_BINCACHE_EXPIRE" -gt "0" ]; then
    now=$(date +%s)
    find "${XDG_CACHE_HOME}/dew" -name "${1}_*" -print |
      while IFS='
' read -r fpath; do
        touched=$(stat -c %Y "$fpath")
        elapsed=$((now - touched))
        if [ "$elapsed" -gt "$DEW_BINCACHE_EXPIRE" ]; then
          log_notice "Removing obsolete cached binary $fpath"
          rm -f "$fpath"
        fi
      done
  fi
  stack_unlet now touched elapsed
}

# $1 is the name of the tool
# $2 is the project at github
version() {
  stack_let ondisk
  stack_let ondisk_version
  stack_let checked
  stack_let now
  stack_let elapsed
  # Look for the tool on the disk
  ondisk=$(_latest_downloaded "$1")
  if [ -n "$ondisk" ]; then
    # Extract the version number that its name carries.
    ondisk_version=$(basename "$ondisk" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+$')
    # Count the number of seconds since the binary was last modify (we will use
    # the modification date as version check storage marker).
    checked=$(stat -c %Y "$ondisk")
    now=$(now)
    elapsed=$((now - checked))
    # Too long have elapsed? Ask GitHub about the latest version and if similar
    # change the modification date of the binary to avoid reasking soon again.
    if [ "$elapsed" -gt "$DEW_BINCACHE_VERCHECK" ]; then
      version=$(gh_version "$2")
      if [ "$ondisk_version" = "$version" ]; then
        touch "$ondisk"
      fi
      printf %s\\n "$version"
    else
      # When binary on disk is recent, return the version that it carries.
      printf %s\\n "$ondisk_version"
    fi
  else
    # Nothing on disk? Return the version from GitHub
    gh_version "$2"
  fi

  stack_unlet ondisk ondisk_version checked now elapsed
}


# Install the content of a remote compressed tar file in the XDG cache
# directory, if not already present. Args:
#   $1 is internal name of binary
#   $2 is version (no leading v).
#   $3 is location of the tar file
#   $4 is name of project at GitHub
#   $5 is printable name of project
tgz_installer() {
  if ! [ -f "${XDG_CACHE_HOME}/dew/$1_$2" ]; then
    log_notice "Downloading ${5:-"tarfile"} v$2"
    tmpdir=$(mktemp -d)
    download "$3" "${tmpdir}/$1.tgz"
    tar -C "$tmpdir" -xf "${tmpdir}/$1.tgz"
    mv "${tmpdir}/$4" "${XDG_CACHE_HOME}/dew/$1_$2"
    # Update modification time of downloaded binary to allow for slow version
    # check algorithm to work (it stores the time of the check as the
    # modification date of the binary)
    touch "${XDG_CACHE_HOME}/dew/$1_$2"
    rm -rf "$tmpdir"
  fi
}



install_docker() {
  stack_let version
  version=${1:-""}
  xdg dew CACHE > /dev/null
  if [ -z "$version" ]; then
    version=$(version "docker" "moby/moby")
    # Remove obsolete binaries from cache
    _rm_obsolete "docker"
  fi

  tgz_installer \
    docker \
    "$version" \
    "https://download.docker.com/linux/static/stable/x86_64/docker-$version.tgz" \
    docker/docker \
    "Docker client"
  printf %s\\n "$version"
  stack_unlet version
}


install_fixuid() {
  stack_let version
  version=${1:-""}
  xdg dew CACHE > /dev/null
  if [ -z "$version" ]; then
    version=$(version "fixuid" "boxboat/fixuid")
    # Remove obsolete binaries from cache
    _rm_obsolete "fixuid"
  fi

  tgz_installer \
    fixuid \
    "$version" \
    "https://github.com/boxboat/fixuid/releases/download/v${version}/fixuid-${version}-linux-amd64.tar.gz" \
    fixuid \
    fixuid
  printf %s\\n "$version"
  stack_unlet version
}