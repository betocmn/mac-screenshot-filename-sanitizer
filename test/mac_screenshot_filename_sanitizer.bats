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
  SLEEP_LOG="$BATS_TEST_TMPDIR/sleep-log"
  : >"$SLEEP_LOG"
  export SLEEP_LOG
  DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults-log"
  : >"$DEFAULTS_LOG"
  export DEFAULTS_LOG
  KILLALL_LOG="$BATS_TEST_TMPDIR/killall-log"
  : >"$KILLALL_LOG"
  export KILLALL_LOG

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

  cat >"$MOCK_BIN/find" <<'EOF'
#!/usr/bin/env bash
if [ "${FAIL_FIND:-0}" = "1" ]; then
  exit 1
fi

/usr/bin/find "$@"
EOF

  cat >"$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SLEEP_LOG:?}"
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

  cat >"$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${KILLALL_LOG:?}"
EOF

  cat >"$MOCK_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "print" ] && [ -n "${LAUNCHCTL_PRINT_OUTPUT:-}" ]; then
  cat "$LAUNCHCTL_PRINT_OUTPUT"
  exit 0
fi

case "${1:-}" in
  bootstrap | load)
    if [ "${LAUNCHCTL_FAIL_LOAD:-0}" = "1" ]; then
      exit 1
    fi
    ;;
esac

exit 0
EOF

  chmod 0755 "$MOCK_BIN/xattr" "$MOCK_BIN/date" "$MOCK_BIN/mv" "$MOCK_BIN/find" "$MOCK_BIN/sleep" "$MOCK_BIN/defaults" "$MOCK_BIN/killall" "$MOCK_BIN/launchctl"
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

@test "treats macOS narrow no-break spaces as separators" {
  file="$WORK_DIR/$(printf 'Screenshot 2026-06-17 at 11.31.53\342\200\257pm.png')"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot-2026-06-17-at-11-31-53-pm.png" ]
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

@test "returns nonzero when the watched directory cannot be read" {
  file="$WORK_DIR/Screenshot 2026.png"
  touch "$file"
  mark_screenshot "$file"

  FAIL_FIND=1 run "$SCRIPT" run --dir "$WORK_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read directory: $WORK_DIR"* ]]
  [[ "$output" == *"Full Disk Access"* ]]
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

@test "settle delay waits before sweeping" {
  file="$WORK_DIR/Screenshot 2026.png"
  touch "$file"
  mark_screenshot "$file"

  run "$SCRIPT" run --settle-seconds 2 --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [ -e "$WORK_DIR/screenshot-2026.png" ]
  [ "$(cat "$SLEEP_LOG")" = "2" ]
}

@test "settle delay rejects non-integer values" {
  run "$SCRIPT" run --settle-seconds soon --dir "$WORK_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--settle-seconds requires a non-negative integer"* ]]
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
  grep -F "<string>--settle-seconds</string>" "$plist"
  grep -F "<string>2</string>" "$plist"
  grep -F "<key>RunAtLoad</key>" "$plist"
  grep -F "<true/>" "$plist"
  grep -F "<key>MAC_SCREENSHOT_RENAME_LAUNCHD_LOG_MARKERS</key>" "$plist"
  grep -F "<string>$log_file</string>" "$plist"
}

@test "generated plist respects custom settle delay" {
  plist="$WORK_DIR/agent.plist"
  worker="$WORK_DIR/mac-screenshot-filename-sanitizer"
  log_file="$WORK_DIR/agent.log"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  SETTLE_SECONDS=5
  SETTLE_SECONDS_PROVIDED=1
  write_plist "$plist" "$WORK_DIR" "$worker" "$log_file"

  grep -F "<string>--settle-seconds</string>" "$plist"
  grep -F "<string>5</string>" "$plist"
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

@test "install safe-location sets macOS screenshots to ~/Screenshots" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  safe_dir="$home/Screenshots"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"

  mkdir -p "$home"

  run env HOME="$home" PREFIX="$prefix" MAC_SCREENSHOT_RENAME_SKIP_BACKGROUND_CHECK=1 "$SCRIPT" install --safe-location

  [ "$status" -eq 0 ]
  [ -d "$safe_dir" ]
  [ -f "$plist" ]
  grep -F "write com.apple.screencapture location $safe_dir" "$DEFAULTS_LOG"
  grep -F "SystemUIServer" "$KILLALL_LOG"
  grep -F "<string>$safe_dir</string>" "$plist"
  [[ "$output" == *"Watching: $safe_dir"* ]]
  [[ "$output" == *"Set macOS screenshot location: $safe_dir"* ]]
}

@test "install set-location creates and watches a custom screenshot folder" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  custom_dir="$WORK_DIR/custom Screenshots"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"

  mkdir -p "$home"

  run env HOME="$home" PREFIX="$prefix" MAC_SCREENSHOT_RENAME_SKIP_BACKGROUND_CHECK=1 "$SCRIPT" install --set-location "$custom_dir"

  [ "$status" -eq 0 ]
  [ -d "$custom_dir" ]
  [ -f "$plist" ]
  grep -F "write com.apple.screencapture location $custom_dir" "$DEFAULTS_LOG"
  grep -F "<string>$custom_dir</string>" "$plist"
  [[ "$output" == *"Watching: $custom_dir"* ]]
  [[ "$output" == *"Set macOS screenshot location: $custom_dir"* ]]
}

@test "install location-changing flags reject conflicting options" {
  run "$SCRIPT" install --safe-location --set-location "$WORK_DIR/Screenshots"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--safe-location cannot be combined with --set-location"* ]]

  run "$SCRIPT" install --safe-location --dir "$WORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dir cannot be combined with --safe-location or --set-location"* ]]

  run "$SCRIPT" status --safe-location
  [ "$status" -ne 0 ]
  [[ "$output" == *"--safe-location and --set-location are only supported by the install command"* ]]
}

@test "install safe-location does not change macOS settings when launchd load fails" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  worker="$prefix/bin/mac-screenshot-filename-sanitizer"

  mkdir -p "$home"

  run env HOME="$home" PREFIX="$prefix" MAC_SCREENSHOT_RENAME_SKIP_BACKGROUND_CHECK=1 LAUNCHCTL_FAIL_LOAD=1 "$SCRIPT" install --safe-location

  [ "$status" -ne 0 ]
  [ ! -s "$DEFAULTS_LOG" ]
  [ ! -s "$KILLALL_LOG" ]
  [ ! -e "$plist" ]
  [ ! -e "$worker" ]
  [[ "$output" == *"could not load LaunchAgent"* ]]
}

@test "install safe-location reports defaults write failures cleanly" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  safe_dir="$home/Screenshots"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  worker="$prefix/bin/mac-screenshot-filename-sanitizer"

  mkdir -p "$home"

  run env HOME="$home" PREFIX="$prefix" MAC_SCREENSHOT_RENAME_SKIP_BACKGROUND_CHECK=1 DEFAULTS_FAIL_WRITE=1 "$SCRIPT" install --safe-location

  [ "$status" -ne 0 ]
  grep -F "write com.apple.screencapture location $safe_dir" "$DEFAULTS_LOG"
  [ ! -e "$plist" ]
  [ ! -e "$worker" ]
  [[ "$output" == *"could not set macOS screenshot location to $safe_dir"* ]]
  [[ "$output" != *"screenshot folder does not exist:"* ]]
}

@test "install safe-location rolls back previous watcher when smoke check fails" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  old_dir="$WORK_DIR/old Screenshots"
  safe_dir="$home/Screenshots"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  log_file="$home/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
  worker="$prefix/bin/mac-screenshot-filename-sanitizer"
  launchctl_output="$WORK_DIR/launchctl-print"

  mkdir -p "$home" "$old_dir" "${plist%/*}" "${log_file%/*}" "${worker%/*}"
  printf 'previous worker\n' >"$worker"
  chmod 0755 "$worker"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  write_plist "$plist" "$old_dir" "$worker" "$log_file"

  {
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$safe_dir"
    printf 'could not read directory: %s\n' "$safe_dir"
  } >"$log_file"
  cat >"$launchctl_output" <<'EOF'
gui/501/io.github.betocmn.mac-screenshot-filename-sanitizer = {
  runs = 1
  last exit code = 1
}
EOF

  run env HOME="$home" PREFIX="$prefix" DEFAULTS_READ_LOCATION="$old_dir" LAUNCHCTL_PRINT_OUTPUT="$launchctl_output" "$SCRIPT" install --safe-location

  [ "$status" -ne 0 ]
  grep -F "write com.apple.screencapture location $safe_dir" "$DEFAULTS_LOG"
  grep -F "write com.apple.screencapture location $old_dir" "$DEFAULTS_LOG"
  grep -F "<string>$old_dir</string>" "$plist"
  ! grep -F "<string>$safe_dir</string>" "$plist"
  grep -F "previous worker" "$worker"
  [[ "$output" == *"WARNING: macOS blocked the LaunchAgent from reading $safe_dir."* ]]
  [[ "$output" == *"install failed because the LaunchAgent could not read $safe_dir"* ]]
  [[ "$output" != *"Installed io.github.betocmn.mac-screenshot-filename-sanitizer"* ]]
}

@test "install safe-location clears screenshot setting on smoke failure when previously unset" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  safe_dir="$home/Screenshots"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  log_file="$home/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
  worker="$prefix/bin/mac-screenshot-filename-sanitizer"
  launchctl_output="$WORK_DIR/launchctl-print"

  mkdir -p "$home" "${log_file%/*}"
  {
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$safe_dir"
    printf 'could not read directory: %s\n' "$safe_dir"
  } >"$log_file"
  cat >"$launchctl_output" <<'EOF'
gui/501/io.github.betocmn.mac-screenshot-filename-sanitizer = {
  runs = 1
  last exit code = 1
}
EOF

  run env HOME="$home" PREFIX="$prefix" LAUNCHCTL_PRINT_OUTPUT="$launchctl_output" "$SCRIPT" install --safe-location

  [ "$status" -ne 0 ]
  grep -F "write com.apple.screencapture location $safe_dir" "$DEFAULTS_LOG"
  grep -F "delete com.apple.screencapture location" "$DEFAULTS_LOG"
  [ ! -e "$plist" ]
  [ ! -e "$worker" ]
  [[ "$output" == *"install failed because the LaunchAgent could not read $safe_dir"* ]]
}

@test "status reports blocked background access from LaunchAgent logs" {
  home="$WORK_DIR/home"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  log_file="$home/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
  worker="$WORK_DIR/mac-screenshot-filename-sanitizer"
  launchctl_output="$WORK_DIR/launchctl-print"
  file="$WORK_DIR/Screenshot 2026.png"

  mkdir -p "${plist%/*}" "${log_file%/*}"
  touch "$worker" "$file"
  chmod 0755 "$worker"
  mark_screenshot "$file"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  write_plist "$plist" "$WORK_DIR" "$worker" "$log_file"

  {
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$WORK_DIR"
    printf 'could not read directory: %s\n' "$WORK_DIR"
  } >"$log_file"
  cat >"$launchctl_output" <<'EOF'
gui/501/io.github.betocmn.mac-screenshot-filename-sanitizer = {
  runs = 1
  last exit code = 1
}
EOF

  run env HOME="$home" LAUNCHCTL_PRINT_OUTPUT="$launchctl_output" "$SCRIPT" status --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"LaunchAgent last exit code: 1"* ]]
  [[ "$output" == *"LaunchAgent background access: blocked"* ]]
  [[ "$output" == *"WARNING: macOS blocked the LaunchAgent from reading $WORK_DIR."* ]]
  [[ "$output" == *"Grant Full Disk Access to: $worker"* ]]
  [[ "$output" == *"Alternatively, run: \"$worker\" install --safe-location"* ]]
  [[ "$output" == *"Dirty screenshots in detected folder: 1"* ]]
}

@test "status ignores stale unreadable directory logs from earlier launchd runs" {
  home="$WORK_DIR/home"
  plist="$home/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist"
  log_file="$home/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
  worker="$WORK_DIR/mac-screenshot-filename-sanitizer"
  launchctl_output="$WORK_DIR/launchctl-print"

  mkdir -p "${plist%/*}" "${log_file%/*}"
  touch "$worker"
  chmod 0755 "$worker"

  # shellcheck source=/dev/null
  source "$SCRIPT"
  write_plist "$plist" "$WORK_DIR" "$worker" "$log_file"

  {
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$WORK_DIR"
    printf 'could not read directory: %s\n' "$WORK_DIR"
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$WORK_DIR"
    printf 'some later worker failure\n'
  } >"$log_file"
  cat >"$launchctl_output" <<'EOF'
gui/501/io.github.betocmn.mac-screenshot-filename-sanitizer = {
  runs = 2
  last exit code = 2
}
EOF

  run env HOME="$home" LAUNCHCTL_PRINT_OUTPUT="$launchctl_output" "$SCRIPT" status --dir "$WORK_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"LaunchAgent last exit code: 2"* ]]
  [[ "$output" == *"LaunchAgent background access: failed (last exit code 2)"* ]]
  [[ "$output" != *"WARNING: macOS blocked the LaunchAgent"* ]]
}

@test "install warns when the launchd smoke check cannot read the watched folder" {
  home="$WORK_DIR/home"
  prefix="$WORK_DIR/prefix"
  log_file="$home/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
  launchctl_output="$WORK_DIR/launchctl-print"

  mkdir -p "${log_file%/*}"
  {
    printf 'mac-screenshot-filename-sanitizer launchd run started: %s\n' "$WORK_DIR"
    printf 'could not read directory: %s\n' "$WORK_DIR"
  } >"$log_file"
  cat >"$launchctl_output" <<'EOF'
gui/501/io.github.betocmn.mac-screenshot-filename-sanitizer = {
  runs = 1
  last exit code = 1
}
EOF

  run env HOME="$home" PREFIX="$prefix" LAUNCHCTL_PRINT_OUTPUT="$launchctl_output" "$SCRIPT" install --dir "$WORK_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARNING: macOS blocked the LaunchAgent from reading $WORK_DIR."* ]]
  [[ "$output" == *"Grant Full Disk Access to: $prefix/bin/mac-screenshot-filename-sanitizer"* ]]
  [[ "$output" == *"Alternatively, run: \"$prefix/bin/mac-screenshot-filename-sanitizer\" install --safe-location"* ]]
  [[ "$output" == *"install failed because the LaunchAgent could not read $WORK_DIR"* ]]
  [[ "$output" != *"Installed io.github.betocmn.mac-screenshot-filename-sanitizer"* ]]
}
