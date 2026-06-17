#!/usr/bin/env bash

set -u

LABEL="io.github.betocmn.mac-screenshot-filename-sanitizer"
BINARY_NAME="mac-screenshot-filename-sanitizer"

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

main() {
  local target
  local found
  local plist
  local domain

  target=$(install_prefix)/bin/$BINARY_NAME
  if [ -x "$target" ]; then
    "$target" uninstall "$@"
    return $?
  fi

  found=$(command -v "$BINARY_NAME" 2>/dev/null || true)
  if [ -n "$found" ] && [ -x "$found" ]; then
    "$found" uninstall "$@"
    return $?
  fi

  plist=$HOME/Library/LaunchAgents/$LABEL.plist
  domain=gui/$(id -u)

  launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist" "$target"

  printf 'Uninstalled %s\n' "$LABEL"
  printf 'No macOS screenshot settings or screenshot files were changed.\n'
}

main "$@"
