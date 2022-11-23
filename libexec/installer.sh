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
version() {
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
    head -1
}

# Install the content of a remote compressed tar file in the XDG cache
# directory. Args:
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
    rm -rf "$tmpdir"
  fi
}



install_docker() {
  stack_let version
  version=${1:-""}
  xdg dew CACHE > /dev/null
  if [ -z "$version" ]; then
    version=$(version "moby/moby")
  fi

  tgz_installer \
    docker \
    "$version" \
    "https://download.docker.com/linux/static/stable/x86_64/docker-$version.tgz" \
    docker/docker \
    "Docker client"
  stack_unlet version
}

install_fixuid() {
  stack_let version
  version=${1:-""}
  xdg dew CACHE > /dev/null
  if [ -z "$version" ]; then
    version=$(version "boxboat/fixuid")
  fi

  tgz_installer \
    fixuid \
    "$version" \
    "https://github.com/boxboat/fixuid/releases/download/v${version}/fixuid-${version}-linux-amd64.tar.gz" \
    fixuid \
    fixuid
  stack_unlet version
}