#!/usr/bin/env bats

setup() {
  INSTALLER="$BATS_TEST_DIRNAME/../install.sh"
  WORK_DIR=$(mktemp -d "$BATS_TEST_TMPDIR/install.XXXXXX")
  HOME_DIR="$WORK_DIR/home"
  PREFIX_DIR="$WORK_DIR/prefix"
  MOCK_BIN="$WORK_DIR/bin"
  mkdir -p "$HOME_DIR" "$PREFIX_DIR" "$MOCK_BIN"

  CURL_URL_LOG="$WORK_DIR/curl-url"
  export CURL_URL_LOG
  DEFAULTS_LOG="$WORK_DIR/defaults-log"
  : >"$DEFAULTS_LOG"
  export DEFAULTS_LOG

  cat >"$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
out=
url=

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      shift
      out=$1
      ;;
    -*)
      ;;
    *)
      url=$1
      ;;
  esac
  shift
done

[ -n "$out" ] || exit 1
printf '%s\n' "$url" >"${CURL_URL_LOG:?}"
if [ "${FAIL_CURL:-0}" = "1" ]; then
  exit 7
fi
cat >"$out" <<'WORKER'
#!/usr/bin/env bash
printf 'downloaded worker: %s\n' "$*"
if [ "${1:-}" = "install" ]; then
  mkdir -p "${PREFIX:?}/bin" || exit 1
  cp "$0" "$PREFIX/bin/mac-screenshot-filename-sanitizer" || exit 1
  chmod 0755 "$PREFIX/bin/mac-screenshot-filename-sanitizer" || exit 1
fi
WORKER
EOF

  cat >"$MOCK_BIN/defaults" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  read)
    if [ -n "${DEFAULTS_READ_LOCATION:-}" ]; then
      printf '%s\n' "$DEFAULTS_READ_LOCATION"
      exit 0
    fi
    exit 1
    ;;
  write)
    printf '%s\n' "$*" >>"${DEFAULTS_LOG:?}"
    if [ "${DEFAULTS_FAIL_WRITE:-0}" = "1" ]; then
      exit 1
    fi
    exit 0
    ;;
  delete)
    printf '%s\n' "$*" >>"${DEFAULTS_LOG:?}"
    exit 0
    ;;
esac

exit 1
EOF

  cat >"$MOCK_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod 0755 "$MOCK_BIN/curl" "$MOCK_BIN/defaults" "$MOCK_BIN/launchctl" "$MOCK_BIN/killall" "$MOCK_BIN/sleep"
}

teardown() {
  rm -rf "$WORK_DIR"
}

@test "stdin installer downloads worker instead of copying current directory file" {
  cwd="$WORK_DIR/cwd"
  mkdir -p "$cwd"
  cat >"$cwd/mac-screenshot-filename-sanitizer" <<'EOF'
#!/usr/bin/env bash
printf 'stale worker: %s\n' "$*"
EOF

  run bash -c 'cd "$1" && HOME="$2" PREFIX="$3" MAC_SCREENSHOT_RENAME_URL="$4" PATH="$5" bash < "$6"' \
    _ "$cwd" "$HOME_DIR" "$PREFIX_DIR" "https://example.invalid/worker" "$MOCK_BIN:$PATH" "$INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_URL_LOG")" = "https://example.invalid/worker" ]
  grep -F "downloaded worker" "$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer"
  ! grep -F "stale worker" "$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer"
  [[ "$output" == *"downloaded worker: install"* ]]
}

@test "file installer copies sibling worker for local clone installs" {
  clone="$WORK_DIR/clone"
  mkdir -p "$clone"
  cp "$INSTALLER" "$clone/install.sh"
  cat >"$clone/mac-screenshot-filename-sanitizer" <<'EOF'
#!/usr/bin/env bash
printf 'local worker: %s\n' "$*"
if [ "${1:-}" = "install" ]; then
  mkdir -p "${PREFIX:?}/bin" || exit 1
  cp "$0" "$PREFIX/bin/mac-screenshot-filename-sanitizer" || exit 1
  chmod 0755 "$PREFIX/bin/mac-screenshot-filename-sanitizer" || exit 1
fi
EOF
  chmod 0755 "$clone/install.sh" "$clone/mac-screenshot-filename-sanitizer"

  run env HOME="$HOME_DIR" PREFIX="$PREFIX_DIR" MAC_SCREENSHOT_RENAME_URL="https://example.invalid/worker" PATH="$MOCK_BIN:$PATH" \
    bash "$clone/install.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$CURL_URL_LOG" ]
  grep -F "local worker" "$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer"
  [[ "$output" == *"local worker: install"* ]]
}

@test "installer wrapper preserves previous worker when delegated install rolls back" {
  clone="$WORK_DIR/clone"
  previous_worker="$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer"
  home_abs=$(cd "$HOME_DIR" && pwd -P)
  safe_dir="$home_abs/Screenshots"
  mkdir -p "$clone" "${previous_worker%/*}"
  cp "$INSTALLER" "$clone/install.sh"
  cp "$BATS_TEST_DIRNAME/../mac-screenshot-filename-sanitizer" "$clone/mac-screenshot-filename-sanitizer"
  chmod 0755 "$clone/install.sh" "$clone/mac-screenshot-filename-sanitizer"
  printf 'previous worker\n' >"$previous_worker"
  chmod 0755 "$previous_worker"

  run env HOME="$HOME_DIR" PREFIX="$PREFIX_DIR" DEFAULTS_FAIL_WRITE=1 MAC_SCREENSHOT_RENAME_SKIP_BACKGROUND_CHECK=1 PATH="$MOCK_BIN:$PATH" \
    bash "$clone/install.sh" --safe-location

  [ "$status" -ne 0 ]
  grep -F "write com.apple.screencapture location $safe_dir" "$DEFAULTS_LOG"
  grep -F "previous worker" "$previous_worker"
  ! grep -F "SCREENSHOT_XATTR" "$previous_worker"
  [[ "$output" == *"could not set macOS screenshot location to $safe_dir"* ]]
}

@test "standalone installer stops cleanly when worker download fails" {
  clone="$WORK_DIR/standalone"
  mkdir -p "$clone"
  cp "$INSTALLER" "$clone/install.sh"
  chmod 0755 "$clone/install.sh"

  run env HOME="$HOME_DIR" PREFIX="$PREFIX_DIR" MAC_SCREENSHOT_RENAME_URL="https://example.invalid/worker" FAIL_CURL=1 PATH="$MOCK_BIN:$PATH" \
    bash "$clone/install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not download https://example.invalid/worker"* ]]
  [[ "$output" != *"command not found"* ]]
  [ -z "$(find "$PREFIX_DIR/bin" -type f -name 'mac-screenshot-filename-sanitizer.installer.*' -print -quit)" ]
  [ ! -e "$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer" ]
}
