# frozen_string_literal: true

# Regression guard for cross-platform lane delegation inside the Fastfile(s).
#
# Two distinct historical failure modes are covered:
#
# 1) v0.3.2 — `bundle exec fastlane <platform> <lane>` inside `sh(...)`.
#    Failed under brew installs (`Could not locate Gemfile` at
#    `share/fastlane_cli/`). The brew formula declares
#    `depends_on "fastlane"` so plain `fastlane` works against the system
#    gem. Dropping `bundle exec` from the Fastfile sub-lane fan-out fixed
#    this. (`bundle exec ruby storepilot_bridge.rb` is a different code
#    path and stays.)
#
# 2) v0.4.1 — `sh("cd … && fastlane <ios|android> <lane>")`. Even without
#    `bundle exec`, the `sh(...)` indirection spawns a *second* fastlane
#    process via the shell. v0.4.0's interactive prompt forwarding (PTY
#    stdin routing) only reaches the outer process, so when the inner
#    child prompts for App Store Connect 2FA the typed code goes to the
#    outer process and the inner one waits forever. The v0.4.1 fix
#    invokes platform lanes in-process via
#    `FastlaneCliConfig.run_subline(:platform, :lane, options)`. This
#    spec bans the `sh(...fastlane (ios|android) …)` shape in any shape
#    going forward.
RSpec.describe "Fastfile sub-lane delegation" do
  FASTFILE_DIR = File.expand_path("..", __dir__)
  FASTFILES = [
    File.join(FASTFILE_DIR, "Fastfile"),
    File.join(FASTFILE_DIR, "ios", "Fastfile"),
    File.join(FASTFILE_DIR, "android", "Fastfile")
  ].freeze

  # Files in fastlane/ that are allowed to call `Dir.chdir`. Anything else
  # introducing a chdir is a regression — see v0.4.5 cwd-loss bug. Paths
  # are relative to FASTFILE_DIR for readable failure messages.
  ALLOWED_DIR_CHDIR_FILES = %w[
    common_helpers.rb
  ].freeze

  # Lines that look like *documentation* of the old pattern (rationale
  # comments referencing the banned shape) are allowed. The check is
  # therefore "non-comment lines only" — we strip leading whitespace and
  # skip any line starting with `#`. Heredocs that happen to embed the
  # banned token are not used in these Fastfiles, so this is sufficient.
  def self.non_comment_lines(content)
    content.lines.each_with_index.reject do |line, _idx|
      line.lstrip.start_with?("#")
    end
  end

  it "restricts `Dir.chdir` use to the allowlisted files inside fastlane/" do
    # Inventory check: any Ruby file under fastlane/ that calls `Dir.chdir`
    # outside the allowlist is flagged. This is the cwd-shift companion to
    # the `sh(... fastlane (ios|android) ...)` ban above — both are about
    # keeping the parent process's cwd predictable so sub-lanes don't crash
    # on `Dir.getwd`.
    ruby_files = Dir.glob(File.join(FASTFILE_DIR, "**", "*.rb")).reject do |file|
      file.include?("/spec/") || file.include?("/vendor/")
    end

    offenders = ruby_files.each_with_object([]) do |file, list|
      relative = file.sub("#{FASTFILE_DIR}/", "")
      next if ALLOWED_DIR_CHDIR_FILES.include?(relative)

      File.foreach(file).with_index do |line, idx|
        stripped = line.lstrip
        next if stripped.start_with?("#")
        next unless line =~ /\bDir\.chdir\b/

        list << [relative, idx + 1, line.strip]
      end
    end

    expect(offenders).to be_empty, lambda {
      formatted = offenders.map { |f, idx, l| "  #{f}:#{idx}: #{l}" }.join("\n")
      "Found `Dir.chdir` outside the allowlist (#{ALLOWED_DIR_CHDIR_FILES.join(', ')}). " \
        "All cwd shifts under fastlane/ must live inside common_helpers.rb so " \
        "they can be paired with a deterministic restore — see the v0.4.5 " \
        "cwd-loss fix in run_subline.\n#{formatted}"
    }
  end

  FASTFILES.each do |path|
    next unless File.exist?(path)

    relative = path.sub("#{FASTFILE_DIR}/", "")

    it "does not use `bundle exec fastlane` in #{relative}" do
      content = File.read(path)
      offenders = self.class.non_comment_lines(content).select do |line, _|
        line.include?("bundle exec fastlane")
      end

      expect(offenders).to be_empty, lambda {
        formatted = offenders.map { |line, idx| "  #{path}:#{idx + 1}: #{line.strip}" }.join("\n")
        "Found `bundle exec fastlane` invocation(s) — drop the `bundle exec` " \
          "prefix; lanes run against the system / brew fastlane gem:\n#{formatted}"
      }
    end

    it "does not introduce ad-hoc `Dir.chdir` inside Fastfile lanes (#{relative})" do
      # Fastfile lanes must NOT call `Dir.chdir` directly — every cwd shift
      # belongs inside a helper in common_helpers.rb where it can be paired
      # with a deterministic restore. A stray `Dir.chdir` in a lane is how
      # the v0.4.4 cwd-loss bug (sub-lane crashing on `getcwd` after
      # xcodebuild) sneaks back in.
      content = File.read(path)
      offenders = self.class.non_comment_lines(content).select do |line, _|
        line =~ /\bDir\.chdir\b/
      end

      expect(offenders).to be_empty, lambda {
        formatted = offenders.map { |line, idx| "  #{path}:#{idx + 1}: #{line.strip}" }.join("\n")
        "Found ad-hoc `Dir.chdir` in a Fastfile lane — cwd shifts must " \
          "live inside a common_helpers helper (e.g. `run_subline`) so " \
          "they can be paired with a deterministic restore.\n#{formatted}"
      }
    end

    it "does not shell-out to platform lanes via `sh(... fastlane ios|android ...)` in #{relative}" do
      content = File.read(path)
      # Matches `sh(` (any whitespace) followed by a string literal that
      # contains `fastlane ios` or `fastlane android` somewhere inside it,
      # regardless of `cd <runner> &&` prefix, quoting style, or
      # interpolation. We intentionally do NOT match `fastlane deliver` —
      # that's the standalone `deliver` gem CLI, a one-shot action that
      # does not interact with stdin in our flow.
      ban_regex = /sh\s*\(\s*[^)]*?fastlane\s+(?:ios|android)\b/

      offenders = self.class.non_comment_lines(content).select do |line, _|
        line =~ ban_regex
      end

      expect(offenders).to be_empty, lambda {
        formatted = offenders.map { |line, idx| "  #{path}:#{idx + 1}: #{line.strip}" }.join("\n")
        "Found `sh(... fastlane (ios|android) ...)` shell-outs — these spawn " \
          "a second fastlane process whose stdin is NOT wired to the outer " \
          "PTY, breaking interactive prompt forwarding (2FA hangs forever). " \
          "Use `FastlaneCliConfig.run_subline(:platform, :lane, options)` " \
          "instead so the sub-lane runs in-process.\n#{formatted}"
      }
    end
  end
end
