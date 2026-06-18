# mac-screenshot-filename-sanitizer

`mac-screenshot-filename-sanitizer` is a small macOS command-line tool that renames screenshots to shell-safe, agent-friendly filenames.

macOS creates names like:

```text
Screenshot 2026-06-17 at 9.14.48 pm.png
```

Those spaces and extra dots are annoying in terminals, scripts, and when handing screenshot paths to LLM coding agents or CLI tools. This tool turns that name into:

```text
screenshot-2026-06-17-at-9-14-48-pm.png
```

## Non-Invasive Design

By default, this tool is an observer. It does not change macOS screenshot settings, does not move your screenshot folder, and does not write any `com.apple.screencapture` defaults.

On install, it detects the folder where screenshots already land:

```sh
defaults read com.apple.screencapture location
```

If that setting is unset, it watches `$HOME/Desktop`, which is the macOS default. It only renames files that carry the screenshot extended attribute:

```sh
xattr -p com.apple.metadata:kMDItemIsScreenCapture "$file"
```

That safety gate is locale-proof, rename-proof, and does not depend on Spotlight indexing. Files without that metadata are left alone, even if their names look like screenshots.

If your current screenshot folder is protected by macOS privacy controls, such as Desktop, Documents, or Downloads, you can opt into changing the macOS screenshot location during install:

```sh
./install.sh --safe-location
```

That creates `$HOME/Screenshots`, tells macOS to save new screenshots there, and watches that folder instead. Existing screenshots are not moved.

## Install

Recommended path:

```sh
git clone https://github.com/betocmn/mac-screenshot-filename-sanitizer.git
cd mac-screenshot-filename-sanitizer
./install.sh
```

The installer copies `mac-screenshot-filename-sanitizer` to `$PREFIX/bin`, where `PREFIX` defaults to `$HOME/.local`, then registers the LaunchAgent.

To choose another install prefix:

```sh
PREFIX="$HOME/bin" ./install.sh
```

To set a custom screenshot folder and install the watcher for it:

```sh
./install.sh --set-location "$HOME/Pictures/Screenshots"
```

You can install with a one-liner, but clone and read the script first if you can:

```sh
curl -fsSL https://raw.githubusercontent.com/betocmn/mac-screenshot-filename-sanitizer/main/install.sh | bash
```

## How The Watcher Works

`mac-screenshot-filename-sanitizer install` writes a user LaunchAgent at:

```text
~/Library/LaunchAgents/io.github.betocmn.mac-screenshot-filename-sanitizer.plist
```

The plist uses launchd `WatchPaths` for the detected screenshot folder. Under the hood, launchd uses kqueue filesystem events. There is no polling loop and no resident worker process between screenshots.

When the watched folder changes, launchd starts:

```sh
mac-screenshot-filename-sanitizer run --dir "<detected-folder>" --settle-seconds 2
```

The short settle delay gives macOS time to finish attaching screenshot metadata before the worker checks the file. The worker also runs once when the LaunchAgent is loaded, so screenshots that already exist in the watched folder are reconciled after install.

The worker reconciles the whole folder and exits. This is deliberate: launchd may coalesce or throttle bursts of folder events, so the worker is designed to be idempotent instead of handling one event at a time. Already-clean filenames are skipped, so the rename event itself becomes a harmless no-op on the next run.

If your screenshot location changes later, run:

```sh
mac-screenshot-filename-sanitizer install
```

`mac-screenshot-filename-sanitizer status` warns when the detected folder no longer matches the folder baked into the installed LaunchAgent.

## Avoiding Full Disk Access

If your screenshots land on the Desktop, the LaunchAgent watches the Desktop. That can sound broad, but the worker does cheap checks first:

1. skip dotfiles and non-files
2. require a known screenshot extension
3. compute the sanitized name and skip already-clean names
4. only then call `xattr` on the remaining dirty candidates

It never runs `xattr` across the whole directory, and it never renames files that lack the screenshot metadata.

macOS may still block background LaunchAgents from reading Desktop, Documents, or Downloads unless the worker has Full Disk Access. A `Screenshots` subfolder inside Desktop is usually still inside that protected Desktop scope, so it is not a reliable way to avoid the permission prompt.

Use `--safe-location` to create and watch `$HOME/Screenshots`, which is outside those protected folders:

```sh
mac-screenshot-filename-sanitizer install --safe-location
```

Or choose your own folder:

```sh
mac-screenshot-filename-sanitizer install --set-location "$HOME/Pictures/Screenshots"
```

## Sanitization Rules

Given a filename:

1. Split base and extension.
2. Lowercase the extension.
3. Lowercase the base.
4. Replace spaces, dots, and underscores with hyphens.
5. Treat common macOS Unicode spacing characters as spaces.
6. Drop characters outside `[a-z0-9-]`.
7. Collapse repeated hyphens and trim leading or trailing hyphens.
8. If the base becomes empty, use `screenshot`.
9. On collision, append `-<unix-epoch>` before the extension.
10. Never overwrite existing files.

Default allowed extensions:

```text
png jpg jpeg gif heic tiff bmp pdf
```

Examples:

```text
Screenshot 2026-06-17 at 9.14.48 pm.png
=> screenshot-2026-06-17-at-9-14-48-pm.png

Screenshot_One.Two.JPG
=> screenshot-one-two.jpg

___ .png
=> screenshot.png
```

Screen recordings are out of scope by default. You can opt in with:

```sh
mac-screenshot-filename-sanitizer run --include-recordings
```

When enabled, `.mov` and `.mp4` files are considered only if their names match the normal macOS screen recording date and time pattern.

## Usage

Run one sweep without changing anything:

```sh
mac-screenshot-filename-sanitizer run --dry-run
```

`--dry-run` is only supported by `run`; install and uninstall reject it before making changes.

Run one sweep over a specific folder:

```sh
mac-screenshot-filename-sanitizer run --dir "$HOME/Desktop"
```

Show watcher status:

```sh
mac-screenshot-filename-sanitizer status
```

Status reports:

- detected screenshot folder
- folder currently written into the LaunchAgent
- whether the LaunchAgent is loaded
- the LaunchAgent's last exit code
- whether the LaunchAgent appears able to read the watched folder
- a warning if those folders differ
- how many verified screenshots currently have dirty names

## Troubleshooting

After install, the tool waits for the first LaunchAgent run. If macOS blocks background access to the watched folder, install prints a warning and exits nonzero so the failure is visible immediately. You can also check later with:

```sh
mac-screenshot-filename-sanitizer status
```

If status reports:

```text
LaunchAgent background access: blocked
```

grant Full Disk Access to the worker path shown in the warning, then restart the loaded agent:

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.betocmn.mac-screenshot-filename-sanitizer"
```

If `status` reports dirty screenshots but the LaunchAgent does not rename them, check the log:

```sh
tail -80 "$HOME/Library/Logs/io.github.betocmn.mac-screenshot-filename-sanitizer.log"
```

macOS can allow the item in Background Activity while still blocking background access to protected folders such as Desktop, Documents, or Downloads. In that case the log says the worker could not read the watched directory. Grant Full Disk Access to the installed worker, or choose a screenshot folder outside the protected locations and reinstall the watcher with `--set-location`.

To avoid Full Disk Access, let the tool create and use `$HOME/Screenshots`:

```sh
mac-screenshot-filename-sanitizer install --safe-location
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

Uninstall unloads and removes the LaunchAgent and removes the installed worker from `$PREFIX/bin`. It does not move, rename, or delete screenshot files. If you installed with `--safe-location` or `--set-location`, uninstall leaves the macOS screenshot location where you set it.

## Development

Runtime dependencies are limited to macOS built-ins: Bash, `defaults`, `launchctl`, `xattr`, and standard command-line utilities.

Checks:

```sh
shellcheck mac-screenshot-filename-sanitizer install.sh uninstall.sh
bats test
```

GitHub Actions runs those checks on `macos-latest`.
