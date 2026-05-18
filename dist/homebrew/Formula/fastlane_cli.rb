# typed: false
# frozen_string_literal: true

# Homebrew formula for fastlane_cli.
#
# NOTE: This file is a Wave 1 DRAFT living inside the fastlane_cli source
# repo at dist/homebrew/Formula/. When ROADMAP §0 lands (owner decided), it
# will be copied / moved into the dedicated tap repo `homebrew-fastlane_cli`
# at `Formula/fastlane_cli.rb`. Until then, treat the `<owner>` placeholders
# and `PLACEHOLDER_REPLACED_BY_RELEASE_CI` SHA256 values as TODO markers that
# release CI (Track D2) will substitute on each tag push.
class FastlaneCli < Formula
  desc "Terminal-first Fastlane assistant for Flutter projects"
  homepage "https://github.com/<owner>/fastlane_cli"
  version "0.1.0"
  license "Apache-2.0" # TODO: §0 — confirm Apache-2.0 vs MIT before first release.

  depends_on "fastlane"

  on_macos do
    on_arm do
      url "https://github.com/<owner>/fastlane_cli/releases/download/v0.1.0/fastlane_cli-macos-arm64.tar.gz"
      # TODO: replaced by release CI (Track D2) — do not hand-edit.
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
    on_intel do
      url "https://github.com/<owner>/fastlane_cli/releases/download/v0.1.0/fastlane_cli-macos-x86_64.tar.gz"
      # TODO: replaced by release CI (Track D2) — do not hand-edit.
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/<owner>/fastlane_cli/releases/download/v0.1.0/fastlane_cli-linux-x86_64.tar.gz"
      # TODO: replaced by release CI (Track D2) — do not hand-edit.
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
    # TODO: linux-arm64 leg pending — add once Track D1 (release matrix) ships an aarch64 tarball.
  end

  def install
    # Track D1 ships tarballs with the binary at the archive root and the
    # `fastlane/` + `skills/` payloads alongside it. Adjust paths here if
    # that layout changes.
    bin.install "fastlane_cli"
    (share/"fastlane_cli").install "fastlane"
    (share/"fastlane_cli").install "skills"
  end

  def caveats
    <<~EOS
      First-time setup:
        Run `fastlane_cli skills install --project` inside your Flutter project
        to drop the bundled Claude Code / Cursor skills and rules into the
        project's `.claude/` and `.cursor/` directories.

      The bundled Fastlane runner lives at:
        #{opt_share}/fastlane_cli/fastlane

      On first lane run, fastlane_cli will materialise a per-user bundle
      cache under ~/Library/Caches/fastlane_cli (macOS) or
      ~/.cache/fastlane_cli (Linux). See `fastlane_cli doctor` if anything
      goes wrong.
    EOS
  end

  test do
    assert_match "fastlane_cli", shell_output("#{bin}/fastlane_cli --help")
  end
end
