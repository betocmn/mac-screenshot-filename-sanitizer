#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../mac-screenshot-filename-sanitizer"
  WORK_DIR=$(mktemp -d "$BATS_TEST_TMPDIR/screens.XXXXXX")
  WORK_DIR=$(cd "$WORK_DIR" && pwd -P)
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  SCREENSHOT_XATTR_FILES="$BATS_TEST_TMPDIR/xattr-files"
  : >"$SCREENSHOT_XATTR_FILES"
  export SCREENSHOT_XATTR_FILES

  cat >"$MOCK_BIN/xattr" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" != "-p" ]; then
  exit 1
fi

file=${3:-}
while IFS= read -r allowed; do
  if [ "$file" = "$allowed" ]; then
    exit 0
  fi
done <"${SCREENSHOT_XATTR_FILES:?}"

exit 1
EOF

  cat >"$MOCK_BIN/date" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "+%s" ]; then
  printf '1700000000\n'
else
  /bin/date "$@"
fi
EOF

  cat >"$MOCK_BIN/mv" <<'EOF'
#!/usr/bin/env bash
if [ "${FAIL_MV:-0}" = "1" ]; then
  exit 1
fi

/bin/mv "$@"
EOF

  cat >"$MOCK_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod 0755 "$MOCK_BIN/xattr" "$MOCK_BIN/date" "$MOCK_BIN/mv" "$MOCK_BIN/launchctl"
  PATH="$MOCK_BIN:$PATH"
  export PATH
}

teardown() {
  rm -rf "$WORK_DIR"
}

mark_screenshot() {
  printf '%s\n' "$1" >>"$SCREENSHOT_XATTR_FILES"
}

@test "renames screenshots with spaces and dots" {
  file="$WORK_DIR/Screenshot 2026-06-17 at 9.14.48 pm.png"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot-2026-06-17-at-9-14-48-pm.png" ]
  [ ! -e "$file" ]
}

@test "replaces underscores and lowercases extension" {
  file="$WORK_DIR/Screenshot_One_Two.JPG"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot-one-two.jpg" ]
  [ ! -e "$file" ]
}

@test "drops unicode and other unsupported characters" {
  file="$WORK_DIR/Screenshot café Δ 2026.png"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot-caf-2026.png" ]
  [ ! -e "$file" ]
}

@test "appends epoch suffix on collision without overwriting" {
  file="$WORK_DIR/Screenshot 2026.png"
  existing="$WORK_DIR/screenshot-2026.png"
  touch "$file" "$existing"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$existing" ]
  [ -e "$WORK_DIR/screenshot-2026-1700000000.png" ]
  [ ! -e "$file" ]
}

@test "keeps probing when the epoch collision suffix already exists" {
  file="$WORK_DIR/Screenshot 2026.png"
  existing="$WORK_DIR/screenshot-2026.png"
  epoch_existing="$WORK_DIR/screenshot-2026-1700000000.png"
  touch "$file" "$existing" "$epoch_existing"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$existing" ]
  [ -e "$epoch_existing" ]
  [ -e "$WORK_DIR/screenshot-2026-1700000000-1.png" ]
  [ ! -e "$file" ]
}

@test "returns nonzero when a candidate rename fails" {
  file="$WORK_DIR/Screenshot 2026.png"
  touch "$file"
  mark_screenshot "$file"

  FAIL_MV=1 run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -ne 0 ]
  [ -e "$file" ]
}

@test "already clean screenshot names are no-ops" {
  file="$WORK_DIR/screenshot-2026.png"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$file" ]
  [ "$output" = "" ]
}

@test "falls back to screenshot when base sanitizes empty" {
  file="$WORK_DIR/___.png"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot.png" ]
  [ ! -e "$file" ]
}

@test "dirty files without screenshot xattr are never renamed" {
  file="$WORK_DIR/Screenshot 2026-06-17 at 9.14.48 pm.png"
  touch "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$file" ]
  [ "$output" = "" ]
}

@test "unsupported extensions are left untouched" {
  file="$WORK_DIR/Screenshot 2026-06-17 at 9.14.48 pm.txt"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$file" ]
  [ "$output" = "" ]
}

@test "generated plist contains absolute watched path and worker arguments" {
  plist="$WORK_DIR/agent.plist"
  worker="$WORK_DIR/mac-screenshot-filename-sanitizer"
  log_file="$WORK_DIR/agent.log"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  INCLUDE_RECORDINGS=0
  write_plist "$plist" "$WORK_DIR" "$worker" "$log_file"

  grep -F "<string>$worker</string>" "$plist"
  grep -F "<string>run</string>" "$plist"
  grep -F "<string>--dir</string>" "$plist"
  grep -F "<string>$WORK_DIR</string>" "$plist"
  grep -F "<string>$log_file</string>" "$plist"
}

@test "uninstall removes worker recorded in plist without matching prefix" {
  home="$WORK_DIR/home"
  custom_prefix="$WORK_DIR/custom"
  worker="$custom_prefix/bin/mac-screenshot-filename-sanitizer"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  mkdir -p "${worker%/*}" "${plist%/*}"
  touch "$worker"
  chmod 0755 "$worker"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  write_plist "$plist" "$WORK_DIR" "$worker" "$WORK_DIR/agent.log"

  run env HOME="$home" "$SCRIPT" uninstall

  [ "$status" -eq 0 ]
  [ ! -e "$worker" ]
  [ ! -e "$plist" ]
}

@test "dry-run is rejected for install and uninstall" {
  run "$SCRIPT" install --dry-run --dir "$WORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dry-run is only supported by the run command"* ]]

  run "$SCRIPT" uninstall --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dry-run is only supported by the run command"* ]]
}
