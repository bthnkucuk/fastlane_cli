# typed: false
# frozen_string_literal: true

# Homebrew formula for fastlane_cli.
#
# NOTE: This file is a DRAFT living inside the fastlane_cli source repo at
# dist/homebrew/Formula/. Once the first tagged release ships, it is
# copied into the dedicated tap repo `bthnkucuk/homebrew-fastlane_cli`
# at `Formula/fastlane_cli.rb`. The `PLACEHOLDER_REPLACED_BY_RELEASE_CI`
# sha256 values are templating markers that release CI (Track D2)
# substitutes on each tag push.
class FastlaneCli < Formula
  desc "Terminal-first Fastlane assistant for Flutter projects"
  homepage "https://github.com/bthnkucuk/fastlane_cli"
  version "0.1.0"
  license "MIT"

  depends_on "fastlane"

  # URL + sha256 substitution pattern (Track D2): the
  # `PLACEHOLDER_REPLACED_BY_RELEASE_CI` markers are rewritten per-tarball
  # by the release CI bump job, which reads the sha256 lines from the
  # release body produced by `.github/workflows/release.yml`. The version
  # string above is rewritten in the same pass.
  on_macos do
    on_arm do
      url "https://github.com/bthnkucuk/fastlane_cli/releases/download/v0.1.0/fastlane_cli-macos-arm64.tar.gz"
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
    on_intel do
      url "https://github.com/bthnkucuk/fastlane_cli/releases/download/v0.1.0/fastlane_cli-macos-x86_64.tar.gz"
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/bthnkucuk/fastlane_cli/releases/download/v0.1.0/fastlane_cli-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_REPLACED_BY_RELEASE_CI"
    end
    # linux-arm64 intentionally omitted — release.yml does not produce one.
  end

  def install
    # `.github/workflows/release.yml` tars `build/fastlane_cli` plus the
    # `fastlane/` and `skills/` payload directories (and README / LICENSE
    # when present). Layout inside the tarball:
    #   build/fastlane_cli   — compiled Dart binary
    #   fastlane/            — Ruby/Fastlane runner assets
    #   skills/              — bundled Claude Code / Cursor skills
    bin.install "build/fastlane_cli"
    (share/"fastlane_cli").install "fastlane"
    (share/"fastlane_cli").install "skills"
  end

  def caveats
    <<~EOS
      One-time setup — drop the bundled Claude Code / Cursor skills into
      your Flutter project's `.claude/` and `.cursor/` directories:

        fastlane_cli skills install --project

      Or install them once for every project under your user account:

        fastlane_cli skills install --global

      The bundled Fastlane runner lives at:
        #{opt_share}/fastlane_cli/fastlane

      On first lane run, fastlane_cli will materialise a per-user bundle
      cache under ~/Library/Caches/fastlane_cli (macOS) or
      ~/.cache/fastlane_cli (Linux). Run `fastlane_cli doctor` if anything
      goes wrong.
    EOS
  end

  test do
    help_output = shell_output("#{bin}/fastlane_cli --help")
    # Smoke: the binary runs and prints its own name in the help banner.
    assert_match "fastlane_cli", help_output
    # Confirms the CommandRunner subcommand layer (Track A2) is wired —
    # `completion` is the cheapest subcommand to name-check here because it
    # does not require a profile, network, or filesystem mutation.
    assert_match "completion", help_output
  end
end
