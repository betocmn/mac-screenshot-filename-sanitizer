#!/usr/bin/env bash

set -u

BINARY_NAME="mac-screenshot-rename"
DEFAULT_URL="https://raw.githubusercontent.com/betocmn/mac-screenshot-filename-sanitizer/main/mac-screenshot-rename"

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

script_dir() {
  local script_path
  local dir

  script_path=${BASH_SOURCE[0]:-$0}
  case "$script_path" in
    */*)
      dir=${script_path%/*}
      ;;
    *)
      dir=.
      ;;
  esac

  (cd "$dir" 2>/dev/null && pwd -P) || pwd -P
}

install_prefix() {
  local prefix

  prefix=${PREFIX:-$HOME/.local}
  strip_trailing_slashes "$prefix"
}

main() {
  local prefix
  local bin_dir
  local target
  local source_file
  local tmp
  local url

  prefix=$(install_prefix)
  bin_dir=$prefix/bin
  target=$bin_dir/$BINARY_NAME
  source_file=$(script_dir)/$BINARY_NAME
  url=${MAC_SCREENSHOT_RENAME_URL:-$DEFAULT_URL}

  mkdir -p "$bin_dir" || die "could not create $bin_dir"

  tmp=$target.$$
  if [ -f "$source_file" ]; then
    cp "$source_file" "$tmp" || die "could not copy $source_file"
  else
    command -v curl >/dev/null 2>&1 || die "curl is required when installing without a local clone"
    curl -fsSL "$url" -o "$tmp" || die "could not download $url"
  fi

  chmod 0755 "$tmp" || die "could not chmod $tmp"
  mv -f "$tmp" "$target" || die "could not install $target"

  "$target" install "$@"
}

main "$@"
