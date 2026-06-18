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

  command -v curl >/dev/null 2>&1 || {
    printf 'error: curl is required when installing without a local clone\n' >&2
    return 1
  }
  curl -fsSL "$url" -o "$tmp" || {
    printf 'error: could not download %s\n' "$url" >&2
    return 1
  }
}

prepare_downloaded_worker() {
  local bin_dir
  local tmp
  local url

  bin_dir=$1
  url=$2

  tmp=$(mktemp "$bin_dir/$BINARY_NAME.installer.XXXXXX") || {
    printf 'error: could not create temporary worker\n' >&2
    return 1
  }
  if ! download_worker "$url" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! chmod 0755 "$tmp"; then
    printf 'error: could not chmod %s\n' "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp"
}

main() {
  local prefix
  local bin_dir
  local url
  local arg
  local worker
  local worker_is_temp
  local result

  for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
      die "--dry-run is only supported by mac-screenshot-filename-sanitizer run"
    fi
  done

  prefix=$(install_prefix)
  bin_dir=$prefix/bin
  url=${MAC_SCREENSHOT_RENAME_URL:-$DEFAULT_URL}
  worker_is_temp=0

  mkdir -p "$bin_dir" || die "could not create $bin_dir"
  if worker=$(local_worker_source); then
    :
  else
    worker=$(prepare_downloaded_worker "$bin_dir" "$url") || return $?
    worker_is_temp=1
  fi

  "$worker" install "$@"
  result=$?
  if [ "$worker_is_temp" -eq 1 ]; then
    rm -f "$worker"
  fi
  return "$result"
}

main "$@"
