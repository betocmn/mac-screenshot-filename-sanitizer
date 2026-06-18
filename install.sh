#!/usr/bin/env bash

set -u

BINARY_NAME="mac-screenshot-filename-sanitizer"
DEFAULT_URL="https://raw.githubusercontent.com/betocmn/mac-screenshot-filename-sanitizer/main/mac-screenshot-filename-sanitizer"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

strip_trailing_slashes() {
  local path

  path=$1
  while [ "${#path}" -gt 1 ] && [ "${path%/}" != "$path" ]; do
    path=${path%/}
  done
  printf '%s\n' "$path"
}

install_prefix() {
  local prefix

  prefix=${PREFIX:-$HOME/.local}
  strip_trailing_slashes "$prefix"
}

local_worker_source() {
  local script_path
  local dir
  local source_file

  script_path=${BASH_SOURCE[0]:-}
  case "${script_path##*/}" in
    install.sh)
      ;;
    *)
      return 1
      ;;
  esac

  case "$script_path" in
    */*)
      ;;
    *)
      script_path=./$script_path
      ;;
  esac

  [ -f "$script_path" ] || return 1
  dir=${script_path%/*}
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  source_file=$dir/$BINARY_NAME
  [ -f "$source_file" ] || return 1

  printf '%s\n' "$source_file"
}

download_worker() {
  local url
  local tmp

  url=$1
  tmp=$2

  command -v curl >/dev/null 2>&1 || die "curl is required when installing without a local clone"
  curl -fsSL "$url" -o "$tmp" || die "could not download $url"
}

install_worker() {
  local target
  local source_file
  local tmp
  local url

  target=$1
  url=$2
  tmp=$target.$$

  if source_file=$(local_worker_source); then
    cp "$source_file" "$tmp" || die "could not copy $source_file"
  else
    download_worker "$url" "$tmp"
  fi

  chmod 0755 "$tmp" || die "could not chmod $tmp"
  mv -f "$tmp" "$target" || die "could not install $target"
}

main() {
  local prefix
  local bin_dir
  local target
  local url
  local arg

  for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
      die "--dry-run is only supported by mac-screenshot-filename-sanitizer run"
    fi
  done

  prefix=$(install_prefix)
  bin_dir=$prefix/bin
  target=$bin_dir/$BINARY_NAME
  url=${MAC_SCREENSHOT_RENAME_URL:-$DEFAULT_URL}

  mkdir -p "$bin_dir" || die "could not create $bin_dir"
  install_worker "$target" "$url"

  "$target" install "$@"
}

main "$@"
