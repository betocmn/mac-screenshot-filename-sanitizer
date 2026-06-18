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
cat >"$out" <<'WORKER'
#!/usr/bin/env bash
printf 'downloaded worker: %s\n' "$*"
WORKER
EOF

  chmod 0755 "$MOCK_BIN/curl"
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
EOF
  chmod 0755 "$clone/install.sh" "$clone/mac-screenshot-filename-sanitizer"

  run env HOME="$HOME_DIR" PREFIX="$PREFIX_DIR" MAC_SCREENSHOT_RENAME_URL="https://example.invalid/worker" PATH="$MOCK_BIN:$PATH" \
    bash "$clone/install.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$CURL_URL_LOG" ]
  grep -F "local worker" "$PREFIX_DIR/bin/mac-screenshot-filename-sanitizer"
  [[ "$output" == *"local worker: install"* ]]
}
