class MacScreenshotFilenameSanitizer < Formula
  desc "Rename macOS screenshots to shell-safe filenames"
  homepage "https://github.com/betocmn/mac-screenshot-filename-sanitizer"
  url "https://github.com/betocmn/mac-screenshot-filename-sanitizer/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  def install
    bin.install "mac-screenshot-filename-sanitizer"
  end

  def caveats
    <<~EOS
      Run this once to register the event-driven WatchPaths LaunchAgent:
        mac-screenshot-filename-sanitizer install

      This formula intentionally does not define a brew services block because
      brew services does not expose launchd WatchPaths.
    EOS
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/mac-screenshot-filename-sanitizer --version")
  end
end
