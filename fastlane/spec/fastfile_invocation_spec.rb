# frozen_string_literal: true

# Regression guard for v0.3.2 (fix: drop `bundle exec` from sub-lane
# delegation). The Dart-side CommandBuilder was fixed in v0.2.1 to invoke
# `fastlane` directly without `bundle exec`, but the Fastfile itself still
# fanned out to platform sub-lanes through `sh("cd … && bundle exec fastlane
# <platform> <lane>")`, which failed at runtime with
#
#     Could not locate Gemfile
#
# under brew installs (the `share/fastlane_cli/` cwd has no Gemfile and is not
# meant to). The brew formula declares `depends_on "fastlane"`, so plain
# `fastlane …` works against the system gem.
#
# This spec scans the in-repo Fastfile(s) for any remaining `bundle exec
# fastlane` invocation. `bundle exec ruby storepilot_bridge.rb` (and similar
# bundle-protected helper script invocations) ARE legitimate and stay.
RSpec.describe "Fastfile sub-lane delegation" do
  FASTFILE_DIR = File.expand_path("..", __dir__)
  FASTFILES = [
    File.join(FASTFILE_DIR, "Fastfile"),
    File.join(FASTFILE_DIR, "ios", "Fastfile"),
    File.join(FASTFILE_DIR, "android", "Fastfile")
  ].freeze

  FASTFILES.each do |path|
    next unless File.exist?(path)

    it "does not use `bundle exec fastlane` in #{path.sub("#{FASTFILE_DIR}/", '')}" do
      content = File.read(path)
      # We're looking for `bundle exec fastlane` literally — that's the
      # combination that broke under brew installs (no Gemfile at cwd, system
      # `fastlane` is on PATH already via `depends_on "fastlane"`).
      # `bundle exec ruby storepilot_bridge.rb` and similar non-fastlane
      # invocations are NOT matched and are intentionally allowed.
      offenders = content.lines.each_with_index.select do |line, _|
        line.include?("bundle exec fastlane")
      end

      expect(offenders).to be_empty, lambda {
        formatted = offenders.map { |line, idx| "  #{path}:#{idx + 1}: #{line.strip}" }.join("\n")
        "Found `bundle exec fastlane` invocation(s) — drop the `bundle exec` " \
          "prefix; lanes run against the system / brew fastlane gem:\n#{formatted}"
      }
    end
  end
end
