# frozen_string_literal: true

RSpec.describe FastlaneCliConfig do
  # Each example resets ENV to a known baseline; we snapshot specific keys we
  # care about rather than rolling the whole ENV, because rbenv/bundler
  # pollute it heavily and clobbering breaks subsequent requires.
  TRACKED_ENV_KEYS = %w[
    FASTLANE_ROOT FASTLANE_DIRECTORY APP_FASTLANE_PATH
    FASTLANE_APP_ROOT APP_ROOT
    FASTLANE_PUBSPEC_PATH PUBSPEC_PATH
    FASTLANE_FLAVOR APP_FLAVOR FLAVOR
    IOS_APP_IDENTIFIER FASTLANE_IOS_APP_IDENTIFIER
    ANDROID_PACKAGE_NAME FASTLANE_ANDROID_APP_IDENTIFIER
    FASTLANE_APP_IDENTIFIER APP_IDENTIFIER
    ANDROID_PACKAGE_NAME_TEMPLATE FASTLANE_APP_IDENTIFIER_TEMPLATE
    IOS_APP_IDENTIFIER_TEMPLATE APP_IDENTIFIER_TEMPLATE
    FASTLANE_FLUTTER_CMD FLUTTER_CMD
    NO_COLOR
    GOOGLE_PLAY_JSON_KEY_PATH
  ].freeze

  around(:each) do |ex|
    saved = TRACKED_ENV_KEYS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    TRACKED_ENV_KEYS.each { |k| ENV.delete(k) }
    begin
      ex.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  describe ".blank?" do
    it "treats nil, empty, and whitespace-only strings as blank" do
      [nil, "", "   ", "\t\n"].each do |v|
        expect(described_class.blank?(v)).to be true
      end
    end

    it "treats non-empty strings and numbers as present" do
      ["x", "  x  ", 0, 1, true, false].each do |v|
        expect(described_class.blank?(v)).to be false
      end
    end
  end

  describe ".option" do
    it "returns nil when options does not respond to :key?" do
      expect(described_class.option(nil, :foo)).to be_nil
      expect(described_class.option("string", :foo)).to be_nil
    end

    it "matches by symbol and string key" do
      expect(described_class.option({ foo: "bar" }, :foo)).to eq("bar")
      expect(described_class.option({ "foo" => "bar" }, :foo)).to eq("bar")
    end

    it "skips blank values and falls through to next key" do
      expect(described_class.option({ foo: "", bar: "ok" }, :foo, :bar)).to eq("ok")
      expect(described_class.option({ foo: "   ", bar: "ok" }, :foo, :bar)).to eq("ok")
    end

    it "returns nil when no key resolves" do
      expect(described_class.option({ foo: "", bar: nil }, :foo, :bar)).to be_nil
    end

    it "flattens nested key arrays (used by callers like resolve_fastlane_root)" do
      expect(described_class.option({ foo: "x" }, [:bar, :foo])).to eq("x")
    end
  end

  describe ".env_first" do
    it "returns the first non-blank ENV value" do
      ENV["FASTLANE_FLAVOR"] = ""
      ENV["APP_FLAVOR"] = "ExampleApp"
      expect(described_class.env_first("FASTLANE_FLAVOR", "APP_FLAVOR")).to eq("ExampleApp")
    end

    it "returns nil when all keys are blank" do
      expect(described_class.env_first("FASTLANE_FLAVOR", "APP_FLAVOR")).to be_nil
    end
  end

  describe ".parse_bool" do
    %w[1 true yes y on TRUE YES].each do |v|
      it "parses #{v.inspect} as true" do
        expect(described_class.parse_bool(v, default: false)).to be true
      end
    end

    %w[0 false no n off FALSE NO].each do |v|
      it "parses #{v.inspect} as false" do
        expect(described_class.parse_bool(v, default: true)).to be false
      end
    end

    it "returns the default for unrecognised values" do
      expect(described_class.parse_bool("maybe", default: true)).to be true
      expect(described_class.parse_bool("maybe", default: false)).to be false
    end

    it "passes booleans through" do
      expect(described_class.parse_bool(true, default: false)).to be true
      expect(described_class.parse_bool(false, default: true)).to be false
    end
  end

  describe ".bool_option" do
    it "returns the default when key is missing" do
      expect(described_class.bool_option({}, :flag, default: true)).to be true
      expect(described_class.bool_option({}, :flag, default: false)).to be false
    end

    it "uses parse_bool on a present value" do
      expect(described_class.bool_option({ flag: "yes" }, :flag, default: false)).to be true
      expect(described_class.bool_option({ flag: "off" }, :flag, default: true)).to be false
    end
  end

  describe ".resolve_identifier" do
    it "prefers an explicit option over env" do
      ENV["IOS_APP_IDENTIFIER"] = "env.ios"
      expect(described_class.resolve_identifier({ app_identifier: "opt.ios" }, platform: :ios))
        .to eq("opt.ios")
    end

    it "falls back to platform-specific ENV when no option supplied" do
      ENV["IOS_APP_IDENTIFIER"] = "env.ios"
      expect(described_class.resolve_identifier({}, platform: :ios)).to eq("env.ios")

      ENV.delete("IOS_APP_IDENTIFIER")
      ENV["ANDROID_PACKAGE_NAME"] = "env.android"
      expect(described_class.resolve_identifier({}, platform: :android)).to eq("env.android")
    end

    it "falls back to shared FASTLANE_APP_IDENTIFIER as final non-template option" do
      ENV["FASTLANE_APP_IDENTIFIER"] = "env.shared"
      expect(described_class.resolve_identifier({}, platform: :ios)).to eq("env.shared")
    end

    it "uses identifier_template + flavor when neither explicit nor identifier env is set" do
      ENV["APP_IDENTIFIER_TEMPLATE"] = "com.example.%{flavor}"
      ENV["APP_FLAVOR"] = "Staging"
      expect(described_class.resolve_identifier({}, platform: :ios)).to eq("com.example.Staging")
    end

    it "raises a UI error when nothing resolves" do
      expect {
        described_class.resolve_identifier({}, platform: :ios)
      }.to raise_error(FastlaneCore::UIError, /Missing IOS identifier/)
    end
  end

  describe ".resolve_flavor" do
    it "prefers options over env" do
      ENV["FASTLANE_FLAVOR"] = "envFlavor"
      expect(described_class.resolve_flavor(flavor: "optFlavor")).to eq("optFlavor")
    end

    it "trims env values" do
      ENV["FASTLANE_FLAVOR"] = "  staging  "
      expect(described_class.resolve_flavor({})).to eq("staging")
    end

    it "returns nil when nothing is set" do
      expect(described_class.resolve_flavor({})).to be_nil
    end
  end

  describe ".resolve_fastlane_root" do
    # macOS resolves /tmp -> /private/tmp; compare via realpath of the parent
    # so the test doesn't bind to platform symlink quirks.
    it "respects explicit option, expanded against cwd" do
      Dir.mktmpdir do |tmp|
        real_tmp = File.realpath(tmp)
        Dir.chdir(real_tmp) do
          expect(described_class.resolve_fastlane_root(fastlane_root: "myfast"))
            .to eq(File.join(real_tmp, "myfast"))
        end
      end
    end

    it "respects ENV when no option is given" do
      Dir.mktmpdir do |tmp|
        real_tmp = File.realpath(tmp)
        ENV["FASTLANE_ROOT"] = File.join(real_tmp, "envfast")
        expect(described_class.resolve_fastlane_root({}))
          .to eq(File.join(real_tmp, "envfast"))
      end
    end
  end

  describe ".resolve_pubspec_path" do
    it "raises with a clear UI error when explicit path does not exist" do
      expect {
        described_class.resolve_pubspec_path(pubspec_path: "/nonexistent/pubspec.yaml")
      }.to raise_error(FastlaneCore::UIError, /pubspec\.yaml not found/)
    end

    it "returns explicit path when it exists" do
      with_tmpdir do |tmp|
        path = write_file(File.join(tmp, "pubspec.yaml"), "name: foo\n")
        expect(described_class.resolve_pubspec_path(pubspec_path: path)).to eq(path)
      end
    end

    it "falls back to a candidate under the app root" do
      with_tmpdir do |tmp|
        write_file(File.join(tmp, "pubspec.yaml"), "name: bar\n")
        result = described_class.resolve_pubspec_path(app_root: tmp)
        expect(result).to eq(File.join(tmp, "pubspec.yaml"))
      end
    end
  end

  describe ".fastlane_option_tokens" do
    it "escapes shell-special characters in values" do
      tokens = described_class.fastlane_option_tokens(
        { flavor: "exam ple", track: "alpha" },
        allowed_keys: %i[flavor track]
      )
      expect(tokens).to contain_exactly(
        "flavor:exam\\ ple",
        "track:alpha"
      )
    end

    it "filters by allowed_keys" do
      tokens = described_class.fastlane_option_tokens(
        { flavor: "x", secret: "y" },
        allowed_keys: %i[flavor]
      )
      expect(tokens).to eq(["flavor:x"])
    end

    it "skips blank values" do
      tokens = described_class.fastlane_option_tokens(
        { flavor: "", track: "alpha" },
        allowed_keys: %i[flavor track]
      )
      expect(tokens).to eq(["track:alpha"])
    end

    it "returns [] for non-hash inputs" do
      expect(described_class.fastlane_option_tokens(nil)).to eq([])
    end
  end

  describe ".shell_join" do
    it "removes blanks and joins remaining parts with a space" do
      expect(described_class.shell_join(["a", nil, "", "b"])).to eq("a b")
    end
  end

  describe ".color_enabled?" do
    it "respects NO_COLOR" do
      ENV["NO_COLOR"] = "1"
      expect(described_class.color_enabled?).to be false
      ENV["NO_COLOR"] = ""
      expect(described_class.color_enabled?).to be true
    end
  end

  describe ".visible_length" do
    it "ignores ANSI escape sequences" do
      coloured = "\e[31mhello\e[0m"
      expect(described_class.visible_length(coloured)).to eq(5)
    end

    it "counts plain text directly" do
      expect(described_class.visible_length("hello world")).to eq(11)
    end
  end

  describe ".wrap_summary_line" do
    it "returns [\"\"] for empty input" do
      expect(described_class.wrap_summary_line("", 20)).to eq([""])
    end

    it "returns the input as-is when it fits" do
      expect(described_class.wrap_summary_line("hello", 20)).to eq(["hello"])
    end

    it "breaks on the nearest space within the width" do
      out = described_class.wrap_summary_line("hello world foo bar", 11)
      # First line should not exceed width; subsequent should keep the rest.
      expect(out.first.length).to be <= 11
      expect(out.join(" ").gsub(/\s+/, " ").strip).to eq("hello world foo bar")
    end

    it "falls back to hard-cut when no space within width" do
      out = described_class.wrap_summary_line("supercalifragilistic", 6)
      expect(out.first.length).to eq(6)
      expect(out.join("")).to eq("supercalifragilistic")
    end
  end

  describe ".summary_box" do
    it "renders top, body, and bottom borders" do
      ENV["NO_COLOR"] = "1"
      lines = described_class.summary_box("Title", ["one", "two"])
      expect(lines.first).to start_with("┌")
      expect(lines.first).to include("Title")
      expect(lines.last).to start_with("└")
      expect(lines.last).to end_with("┘")
      expect(lines.size).to eq(4) # top + 2 body + bottom
    end

    it "renders a separator when :sep is given" do
      ENV["NO_COLOR"] = "1"
      lines = described_class.summary_box("T", ["one", :sep, "two"])
      sep = lines.find { |l| l.start_with?("├") }
      expect(sep).not_to be_nil
      expect(sep).to end_with("┤")
    end

    it "strips colour when NO_COLOR is set" do
      ENV["NO_COLOR"] = "1"
      lines = described_class.summary_box("T", ["plain"])
      lines.each { |l| expect(l).not_to match(/\e\[/) }
    end

    it "wraps long lines to width" do
      ENV["NO_COLOR"] = "1"
      long = "a" * 200
      lines = described_class.summary_box("T", [long], width: 40)
      # Body lines should be exactly width characters long (border-to-border)
      body = lines[1..-2]
      body.each { |l| expect(l.length).to eq(40) }
    end
  end

  describe ".print_summary_box" do
    it "writes to puts when sink is :stdout and UI is undefined" do
      # Force the puts branch by using sink: :stdout
      ENV["NO_COLOR"] = "1"
      expect {
        described_class.print_summary_box("Hello", ["x"], sink: :stdout)
      }.to output(/Hello/).to_stdout
    end

    it "routes to FastlaneCore::UI.message when sink is :ui" do
      ENV["NO_COLOR"] = "1"
      described_class.print_summary_box("Hello", ["x"], sink: :ui)
      expect(FastlaneCore::UI.captured_messages.join("\n")).to include("Hello")
      expect(FastlaneCore::UI.captured_messages.join("\n")).to include("x")
    end
  end

  describe ".materialize_localised_fallbacks" do
    it "writes root-level fallbacks into empty locale subdirs and returns restorable handles" do
      with_tmpdir do |meta|
        write_file(File.join(meta, "support_url.txt"), "https://support.example/\n")
        FileUtils.mkdir_p(File.join(meta, "en-US"))
        FileUtils.mkdir_p(File.join(meta, "tr"))
        # Existing per-locale override should be preserved
        write_file(File.join(meta, "en-US", "support_url.txt"), "https://override.example/\n")

        restorable = described_class.materialize_localised_fallbacks(metadata_path: meta)

        # tr got the fallback
        expect(File.read(File.join(meta, "tr", "support_url.txt"))).to include("support.example")
        # en-US was preserved
        expect(File.read(File.join(meta, "en-US", "support_url.txt"))).to include("override.example")
        # restorable should not include en-US
        expect(restorable.map(&:first)).to all(include("tr/support_url.txt"))
      end
    end

    it "skips non-locale dirs and hidden entries" do
      with_tmpdir do |meta|
        write_file(File.join(meta, "support_url.txt"), "https://x/")
        FileUtils.mkdir_p(File.join(meta, "review_information"))
        FileUtils.mkdir_p(File.join(meta, ".cache"))

        described_class.materialize_localised_fallbacks(metadata_path: meta)

        expect(File.exist?(File.join(meta, "review_information", "support_url.txt"))).to be false
        expect(File.exist?(File.join(meta, ".cache", "support_url.txt"))).to be false
      end
    end
  end

  describe ".restore_localised_fallbacks" do
    it "rewrites originals where they existed and deletes the rest" do
      with_tmpdir do |dir|
        a = File.join(dir, "a.txt")
        b = File.join(dir, "b.txt")
        File.write(a, "newA")
        File.write(b, "newB")

        described_class.restore_localised_fallbacks([
          [a, true, "originalA"],
          [b, false, nil]
        ])

        expect(File.read(a)).to eq("originalA")
        expect(File.exist?(b)).to be false
      end
    end
  end

  describe ".read_price_tier" do
    it "returns nil when no price_tier.txt is present in metadata or defaults" do
      with_tmpdir do |meta|
        expect(described_class.read_price_tier(metadata_path: meta)).to be_nil
      end
    end

    it "parses an integer price tier when present" do
      with_tmpdir do |meta|
        write_file(File.join(meta, "price_tier.txt"), "  3  \n")
        expect(described_class.read_price_tier(metadata_path: meta)).to eq(3)
      end
    end

    it "raises a UI error on non-integer content" do
      with_tmpdir do |meta|
        write_file(File.join(meta, "price_tier.txt"), "abc\n")
        expect {
          described_class.read_price_tier(metadata_path: meta)
        }.to raise_error(FastlaneCore::UIError, /Invalid price_tier/)
      end
    end
  end

  describe ".read_submission_information" do
    it "returns [nil, {}] when no submission file is resolvable" do
      with_tmpdir do |tmp|
        # Isolate both the app fastlane root AND the runner fastlane root —
        # otherwise the bundled CLI defaults under fastlane/ios/defaults/
        # win the fallback and the result is non-nil.
        options = {
          fastlane_root: File.join(tmp, "app_fastlane"),
          fastlane_runner_path: File.join(tmp, "runner_fastlane")
        }
        FileUtils.mkdir_p(options[:fastlane_root])
        FileUtils.mkdir_p(options[:fastlane_runner_path])

        result = described_class.read_submission_information(options)
        expect(result).to eq([nil, {}])
      end
    end

    it "parses a valid JSON submission file" do
      with_tmpdir do |tmp|
        app_root = File.join(tmp, "fastlane")
        FileUtils.mkdir_p(File.join(app_root, "ios"))
        path = write_file(
          File.join(app_root, "ios", "submission_information.json"),
          '{"export_compliance_uses_encryption": false}'
        )
        result_path, data = described_class.read_submission_information(fastlane_root: app_root)
        expect(File.realpath(result_path)).to eq(File.realpath(path))
        expect(data).to eq({ "export_compliance_uses_encryption" => false })
      end
    end

    it "raises a UI error on invalid JSON" do
      with_tmpdir do |tmp|
        app_root = File.join(tmp, "fastlane")
        FileUtils.mkdir_p(File.join(app_root, "ios"))
        write_file(
          File.join(app_root, "ios", "submission_information.json"),
          "{not valid json"
        )
        expect {
          described_class.read_submission_information(fastlane_root: app_root)
        }.to raise_error(FastlaneCore::UIError, /Invalid submission_information JSON/)
      end
    end
  end

  describe ".resolve_app_path" do
    it "returns nil for blank input" do
      expect(described_class.resolve_app_path(nil)).to be_nil
      expect(described_class.resolve_app_path("  ")).to be_nil
    end

    it "passes absolute paths through unchanged" do
      expect(described_class.resolve_app_path("/abs/path")).to eq("/abs/path")
    end

    it "expands relative paths against the app root" do
      Dir.mktmpdir do |tmp|
        ENV["FASTLANE_APP_ROOT"] = tmp
        expect(described_class.resolve_app_path("build/app.aab"))
          .to eq(File.join(tmp, "build/app.aab"))
      end
    end
  end

  describe ".gradle_flavor_task_fragment is indirectly Bridge concern (covered in bridge spec)" do
    it "is a noop here" do
      # Sentinel test — gradle_flavor_task_fragment lives in StorePilotBridge.
      expect(true).to be true
    end
  end
end
