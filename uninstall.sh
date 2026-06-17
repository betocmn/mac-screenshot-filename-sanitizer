#!/usr/bin/env bash

set -u

LABEL="io.github.betocmn.mac-screenshot-filename-sanitizer"
BINARY_NAME="mac-screenshot-filename-sanitizer"

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

xml_unescape() {
  local input

  input=$1
  input=${input//&apos;/"'"}
  input=${input//&quot;/\"}
  input=${input//&gt;/>}
  input=${input//&lt;/<}
  input=${input//&amp;/&}
  printf '%s\n' "$input"
}

read_plist_worker_path() {
  local plist
  local line
  local in_program_arguments
  local value

  plist=$1
  in_program_arguments=0

  [ -f "$plist" ] || return 1

  while IFS= read -r line; do
    case "$line" in
      *"<key>ProgramArguments</key>"*)
        in_program_arguments=1
        ;;
      *"<string>"*"</string>"*)
        if [ "$in_program_arguments" -eq 1 ]; then
          value=${line#*<string>}
          value=${value%%</string>*}
          xml_unescape "$value"
          return 0
        fi
        ;;
      *"</array>"*)
        if [ "$in_program_arguments" -eq 1 ]; then
          return 1
        fi
        ;;
    esac
  done <"$plist"

  return 1
}

main() {
  local target
  local found
  local plist
  local domain
  local plist_worker
  local arg

  for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
      die "--dry-run is only supported by mac-screenshot-filename-sanitizer run"
    fi
  done

  target=$(install_prefix)/bin/$BINARY_NAME
  plist=$HOME/Library/LaunchAgents/$LABEL.plist
  if [ -x "$target" ]; then
    "$target" uninstall "$@"
    return $?
  fi

  if plist_worker=$(read_plist_worker_path "$plist") && [ -x "$plist_worker" ]; then
    "$plist_worker" uninstall "$@"
    return $?
  fi

  found=$(command -v "$BINARY_NAME" 2>/dev/null || true)
  if [ -n "$found" ] && [ -x "$found" ]; then
    "$found" uninstall "$@"
    return $?
  fi

  domain=gui/$(id -u)

  launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist" "$target"
  if [ -n "${plist_worker:-}" ]; then
    rm -f "$plist_worker"
  fi

  printf 'Uninstalled %s\n' "$LABEL"
  printf 'No macOS screenshot settings or screenshot files were changed.\n'
}

main "$@"
