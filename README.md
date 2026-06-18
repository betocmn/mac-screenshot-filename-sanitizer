# mac-screenshot-filename-sanitizer

Rename macOS screenshots to shell-safe filenames.

```text
Screenshot 2026-06-17 at 9.14.48 pm.png
=> screenshot-2026-06-17-at-9-14-48-pm.png
```

The tool watches your screenshot folder with a user LaunchAgent, verifies files with macOS screenshot metadata, renames only real screenshots, and exits after each sweep.

## Install

Recommended:

```sh
git clone https://github.com/betocmn/mac-screenshot-filename-sanitizer.git
cd mac-screenshot-filename-sanitizer
./install.sh --safe-location
```

`--safe-location` creates `~/Screenshots`, sets macOS to save new screenshots there, and watches that folder. This avoids the common Desktop/Documents/Downloads privacy prompt because those folders are protected for background LaunchAgents.

| Option | Command | Use when |
| --- | --- | --- |
| Safe location | `./install.sh --safe-location` | You want the simplest install with no Full Disk Access prompt. |
| Existing location | `./install.sh` | You already have a screenshot folder set and are okay granting access if macOS requires it. |
| Custom location | `./install.sh --set-location "$HOME/Pictures/Screenshots"` | You want screenshots saved somewhere specific. |
| Custom prefix | `PREFIX="$HOME/bin" ./install.sh --safe-location` | You want the binary installed outside the default `$HOME/.local/bin`. |

Remote install:

```sh
curl -fsSL https://raw.githubusercontent.com/betocmn/mac-screenshot-filename-sanitizer/main/install.sh | bash -s -- --safe-location
```

## Usage

```sh
mac-screenshot-filename-sanitizer status
mac-screenshot-filename-sanitizer run --dry-run
mac-screenshot-filename-sanitizer run --dir "$HOME/Desktop"
```

By default the sanitizer handles common screenshot extensions:

```text
png jpg jpeg gif heic tiff bmp pdf
```

Screen recordings are skipped unless you opt in:

```sh
mac-screenshot-filename-sanitizer run --include-recordings
```

## Uninstall

From a clone:

```sh
./uninstall.sh
```

Or directly:

```sh
mac-screenshot-filename-sanitizer uninstall
```

Uninstall removes the LaunchAgent and installed worker. It does not move, rename, or delete screenshots, and it leaves your macOS screenshot location unchanged.

## Development

Runtime dependencies are macOS built-ins: Bash, `defaults`, `launchctl`, `xattr`, and standard command-line utilities.

Checks:

```sh
shellcheck mac-screenshot-filename-sanitizer install.sh uninstall.sh
bats test
```
