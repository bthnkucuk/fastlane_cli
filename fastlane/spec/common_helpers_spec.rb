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

  describe ".crashlytics_symbol_task" do
    it "capitalises the first letter of a single-word flavor" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "staging")
      ).to eq("uploadCrashlyticsSymbolFileStagingRelease")
    end

    it "drops the flavor segment when no flavor is given" do
      expect(
        described_class.crashlytics_symbol_task(flavor: nil)
      ).to eq("uploadCrashlyticsSymbolFileRelease")
    end

    it "treats a blank flavor string as no flavor" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "   ")
      ).to eq("uploadCrashlyticsSymbolFileRelease")
    end

    it "capitalises only the first letter of a multi-word flavor (Gradle casing)" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "freeStaging")
      ).to eq("uploadCrashlyticsSymbolFileFreeStagingRelease")
    end

    it "trims surrounding whitespace from the flavor" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "  staging  ")
      ).to eq("uploadCrashlyticsSymbolFileStagingRelease")
    end

    it "honours an explicit build_type override" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "staging", build_type: "debug")
      ).to eq("uploadCrashlyticsSymbolFileStagingDebug")
    end

    it "falls back to Release when build_type is blank" do
      expect(
        described_class.crashlytics_symbol_task(flavor: "staging", build_type: "")
      ).to eq("uploadCrashlyticsSymbolFileStagingRelease")
    end
  end

  describe ".flutter_build_flags" do
    it "returns no flags when neither option is set" do
      expect(described_class.flutter_build_flags({}, artifact: :apk)).to eq([])
      expect(described_class.flutter_build_flags({}, artifact: :appbundle)).to eq([])
      expect(described_class.flutter_build_flags({}, artifact: :ipa)).to eq([])
    end

    it "emits --obfuscate with the default split-debug-info dir" do
      expect(
        described_class.flutter_build_flags({ obfuscate: "true" }, artifact: :apk)
      ).to eq(["--obfuscate", "--split-debug-info=build/symbols"])
    end

    it "obfuscate applies to every artifact" do
      %i[apk appbundle ipa].each do |artifact|
        expect(
          described_class.flutter_build_flags({ obfuscate: true }, artifact: artifact)
        ).to include("--obfuscate", "--split-debug-info=build/symbols")
      end
    end

    it "honours a custom split_debug_info directory" do
      expect(
        described_class.flutter_build_flags(
          { obfuscate: true, split_debug_info: "out/dbg" }, artifact: :ipa
        )
      ).to eq(["--obfuscate", "--split-debug-info=out/dbg"])
    end

    it "ignores split_debug_info when obfuscate is off" do
      expect(
        described_class.flutter_build_flags(
          { split_debug_info: "out/dbg" }, artifact: :apk
        )
      ).to eq([])
    end

    it "honours split_per_abi for :apk" do
      expect(
        described_class.flutter_build_flags({ split_per_abi: "true" }, artifact: :apk)
      ).to eq(["--split-per-abi"])
    end

    it "ignores split_per_abi for :appbundle" do
      expect(
        described_class.flutter_build_flags({ split_per_abi: true }, artifact: :appbundle)
      ).to eq([])
    end

    it "ignores split_per_abi for :ipa" do
      expect(
        described_class.flutter_build_flags({ split_per_abi: true }, artifact: :ipa)
      ).to eq([])
    end

    it "combines obfuscate and split_per_abi for :apk" do
      expect(
        described_class.flutter_build_flags(
          { obfuscate: true, split_per_abi: true }, artifact: :apk
        )
      ).to eq(["--obfuscate", "--split-debug-info=build/symbols", "--split-per-abi"])
    end
  end

  describe ".capitalize_variant_segment" do
    it "capitalises only the first character" do
      expect(described_class.capitalize_variant_segment("freeStaging")).to eq("FreeStaging")
    end

    it "returns an empty string for nil" do
      expect(described_class.capitalize_variant_segment(nil)).to eq("")
    end

    it "returns an empty string for a blank value" do
      expect(described_class.capitalize_variant_segment("   ")).to eq("")
    end

    it "handles a single-character value" do
      expect(described_class.capitalize_variant_segment("a")).to eq("A")
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

  describe ".redact_secret_value" do
    it "redacts password: ..." do
      expect(described_class.redact_secret_value("password: secret123"))
        .to eq("password: ***")
    end

    it "redacts api_key= ... (equals delimiter)" do
      expect(described_class.redact_secret_value("api_key=AKIAEXAMPLE"))
        .to eq("api_key=***")
    end

    it "is case insensitive (API_KEY)" do
      expect(described_class.redact_secret_value("API_KEY: AKIAEXAMPLE"))
        .to eq("API_KEY: ***")
    end

    it "redacts token: Bearer xyz" do
      expect(described_class.redact_secret_value("token: Bearer xyz.abc.def"))
        .to eq("token: ***")
    end

    it "redacts json_key_data: {...}" do
      expect(described_class.redact_secret_value('json_key_data: {"type":"service_account"}'))
        .to eq("json_key_data: ***")
    end

    it "redacts api-key (dash variant)" do
      expect(described_class.redact_secret_value("api-key: AKIA-DASH"))
        .to eq("api-key: ***")
    end

    it "redacts private_key=..." do
      expect(described_class.redact_secret_value("private_key=-----BEGIN..."))
        .to eq("private_key=***")
    end

    it "redacts client_secret: ..." do
      expect(described_class.redact_secret_value("client_secret: abcdef"))
        .to eq("client_secret: ***")
    end

    it "redacts authorization: Bearer ..." do
      expect(described_class.redact_secret_value("Authorization: Bearer eyJhbGciOi"))
        .to eq("Authorization: ***")
    end

    it "passes plain non-sensitive lines through unchanged" do
      expect(described_class.redact_secret_value("build: 42")).to eq("build: 42")
      expect(described_class.redact_secret_value("App identifier : com.example.app"))
        .to eq("App identifier : com.example.app")
    end

    it "leaves nil untouched" do
      expect(described_class.redact_secret_value(nil)).to be_nil
    end
  end

  describe ".summary_box redaction integration" do
    it "redacts secret-bearing lines before rendering" do
      ENV["NO_COLOR"] = "1"
      lines = described_class.summary_box("Auth", [
        "App identifier : com.example.app",
        "api_key: AKIAEXAMPLESECRET",
        "token: Bearer eyJabc.def.ghi"
      ])
      body = lines.join("\n")
      expect(body).to include("api_key: ***")
      expect(body).to include("token: ***")
      expect(body).not_to include("AKIAEXAMPLESECRET")
      expect(body).not_to include("eyJabc.def.ghi")
      expect(body).to include("com.example.app")
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

  describe ".run_subline" do
    # `run_subline` is the cross-platform sub-lane invoker that replaced
    # the v0.3.2 `sh("cd #{runner} && fastlane <platform> <lane>")`
    # pattern with an in-process call.
    #
    # v0.4.1 wrongly called `Fastlane::FastFile.runner.execute(...)` —
    # `runner` is an `attr_accessor` (instance method) on FastFile, not a
    # class method, so every invocation crashed with
    # `undefined method 'runner' for class Fastlane::FastFile`. v0.4.2
    # changes the signature to take the FastFile *instance* explicitly
    # (call sites pass `self` from inside the lane block, where `self` IS
    # the FastFile instance). The spec asserts the new signature.
    let(:received) { [] }
    let(:fastfile_double) do
      received_log = received
      runner_double = Object.new
      runner_double.define_singleton_method(:execute) do |lane, platform, params|
        received_log << [lane, platform, params]
        "executed:#{platform}:#{lane}:#{params.inspect}"
      end

      ff = Object.new
      ff.define_singleton_method(:runner) { runner_double }
      ff
    end

    it "forwards lane and platform onto fastfile.runner.execute as symbols" do
      result = described_class.run_subline(fastfile_double, "android", "internal_testing", flavor: "prod")
      expect(received).to eq([
        [:internal_testing, :android, { flavor: "prod" }]
      ])
      expect(result).to match(/executed:android:internal_testing/)
    end

    it "coerces symbol input the same as string input" do
      described_class.run_subline(fastfile_double, :ios, :test_flight, {})
      expect(received).to eq([
        [:test_flight, :ios, {}]
      ])
    end

    it "defaults options to an empty hash" do
      described_class.run_subline(fastfile_double, :ios, :get_ios_version_data)
      expect(received.first).to eq([:get_ios_version_data, :ios, {}])
    end

    it "propagates exceptions raised by the runner so callers can rescue/fallback" do
      crashing_fastfile = Object.new
      crashing_runner = Object.new
      crashing_runner.define_singleton_method(:execute) do |*_args|
        raise StandardError, "lane blew up"
      end
      crashing_fastfile.define_singleton_method(:runner) { crashing_runner }

      expect { described_class.run_subline(crashing_fastfile, :ios, :test_flight) }
        .to raise_error(StandardError, "lane blew up")
    end

    it "rejects callers that forget to pass the FastFile instance (v0.4.1 regression guard)" do
      # The old v0.4.1 signature was `run_subline(platform, lane, options)`.
      # Calling it that way against the v0.4.2 helper should produce an
      # ArgumentError (wrong number of arguments) or a NoMethodError on
      # `.runner` for the platform symbol — either way it must NOT
      # silently no-op, which is what would happen if we forgot to update
      # a call site.
      expect {
        described_class.run_subline(:android, :internal_testing, {})
      }.to raise_error(StandardError)
    end

    # v0.4.5 — cwd-loss regression guard.
    #
    # `cruise_lane` wraps the outer invocation in
    #   Dir.chdir(File.expand_path("..", fastfile_path)) { ... }
    # so any action that calls `FastlaneCore::FastlaneFolder.path` /
    # `Dir.getwd` finds a real directory. Sub-lane invocations called via
    # `run_subline` did NOT get that wrapper before v0.4.5, so a previous
    # build step that left the parent process's cwd pointing at a deleted
    # temp dir caused the next sub-lane's `DocsGenerator.run` to crash with
    # `Errno::ENOENT - No such file or directory - getcwd`.
    describe "cwd pinning (v0.4.5)" do
      it "wraps runner.execute in Dir.chdir(runner_root) when fastfile.path is set" do
        Dir.mktmpdir("runner_root_") do |runner_dir|
          real_runner = File.realpath(runner_dir)
          fastfile_path = File.join(real_runner, "fastlane", "Fastfile")
          FileUtils.mkdir_p(File.dirname(fastfile_path))
          FileUtils.touch(fastfile_path)

          chdir_calls = []
          received_log = []
          runner_double = Object.new
          runner_double.define_singleton_method(:execute) do |lane, platform, params|
            # Confirm we're actually inside the chdir block when execute runs.
            chdir_calls << Dir.pwd
            received_log << [lane, platform, params]
            :ok
          end

          ff = Object.new
          ff.define_singleton_method(:runner) { runner_double }
          ff.define_singleton_method(:path) { fastfile_path }

          # Run from a known cwd that is NOT runner_root, so we can prove
          # the chdir happened.
          Dir.chdir(real_runner) do
            described_class.run_subline(ff, :ios, :test_flight, {})
          end

          expected_pin = File.expand_path("..", fastfile_path)
          expect(chdir_calls.size).to eq(1)
          expect(File.realpath(chdir_calls.first)).to eq(File.realpath(expected_pin))
          expect(received_log).to eq([[:test_flight, :ios, {}]])
        end
      end

      it "recovers when the parent process's cwd has been deleted (regression guard)" do
        # Simulate the production failure mode:
        #  1. Build step chdir'd into a temp dir.
        #  2. The temp dir got deleted (xcodebuild / pod install / flutter
        #     clean tear-down).
        #  3. Parent Ruby process's cwd now references a phantom inode;
        #     `Dir.pwd` raises Errno::ENOENT.
        #  4. The next sub-lane must NOT crash on `Dir.getwd`.
        Dir.mktmpdir("runner_pin_") do |runner_dir|
          real_runner = File.realpath(runner_dir)
          fastfile_path = File.join(real_runner, "fastlane", "Fastfile")
          FileUtils.mkdir_p(File.dirname(fastfile_path))
          FileUtils.touch(fastfile_path)

          received_log = []
          runner_double = Object.new
          runner_double.define_singleton_method(:execute) do |lane, platform, params|
            # Inside the chdir-pinned block: Dir.pwd MUST succeed.
            pwd_inside = Dir.pwd
            received_log << [lane, platform, params, pwd_inside]
            :ok
          end

          ff = Object.new
          ff.define_singleton_method(:runner) { runner_double }
          ff.define_singleton_method(:path) { fastfile_path }

          # Capture a safe cwd to return to once the example finishes — we
          # can't rely on `Dir.pwd` after the rm_r, and the spec_helper's
          # around blocks may try to read it.
          safe_cwd = Dir.pwd

          ghost_dir = Dir.mktmpdir("ghost_cwd_")
          begin
            Dir.chdir(ghost_dir)
            FileUtils.rm_r(ghost_dir)
            # We are now in a deleted directory. Dir.pwd should raise.
            expect { Dir.pwd }.to raise_error(Errno::ENOENT)

            # The fix: run_subline chdirs into runner_root before executing,
            # so getcwd-dependent code (DocsGenerator) sees a real path.
            expect {
              described_class.run_subline(ff, :ios, :test_flight, {})
            }.not_to raise_error

            expect(received_log.size).to eq(1)
            inside_pwd = received_log.first[3]
            expect(File.realpath(inside_pwd)).to eq(File.realpath(File.expand_path("..", fastfile_path)))
          ensure
            # After the chdir block exits, Ruby tries to chdir back to the
            # ghost dir. That fails silently inside Dir.chdir's ensure on
            # some libcs, but on macOS the saved cwd is the ghost — so
            # explicitly return to a known-good directory.
            Dir.chdir(safe_cwd)
          end
        end
      end

      it "falls back gracefully when fastfile.path is unavailable and FastlaneCore is undefined" do
        # If neither fastfile.path / @path nor FastlaneCore::FastlaneFolder
        # resolves, run_subline must still forward to runner.execute (no
        # chdir, no crash).
        received_log = []
        runner_double = Object.new
        runner_double.define_singleton_method(:execute) do |lane, platform, params|
          received_log << [lane, platform, params]
          :ok
        end
        ff = Object.new
        ff.define_singleton_method(:runner) { runner_double }
        # NOTE: deliberately no `.path` and no `@path`.

        expect {
          described_class.run_subline(ff, :android, :internal_testing, {})
        }.not_to raise_error
        expect(received_log).to eq([[:internal_testing, :android, {}]])
      end
    end
  end

  describe ".with_clean_subprocess_env" do
    let(:scrubbed_keys) { FastlaneCliConfig::SUBPROCESS_ENV_KEYS_TO_SCRUB }

    around do |example|
      saved_keys = scrubbed_keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
      saved_path = ENV["PATH"]
      example.run
    ensure
      saved_keys.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      ENV["PATH"] = saved_path unless saved_path.nil?
    end

    it "scrubs GEM_HOME / GEM_PATH / BUNDLE_* inside the block" do
      ENV["GEM_HOME"] = "/brewed/fastlane/gems"
      ENV["GEM_PATH"] = "/a:/b"
      ENV["BUNDLE_GEMFILE"] = "/some/Gemfile"

      seen = {}
      described_class.with_clean_subprocess_env do
        seen["GEM_HOME"] = ENV["GEM_HOME"]
        seen["GEM_PATH"] = ENV["GEM_PATH"]
        seen["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"]
      end

      expect(seen.values).to all(be_nil)
    end

    it "strips fastlane brew PATH segments inside the block" do
      ENV["PATH"] = [
        "/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin",
        "/Users/me/.local/share/fastlane/4.0.0/bin",
        "/usr/local/bin",
        "/usr/bin"
      ].join(":")

      seen_path = nil
      described_class.with_clean_subprocess_env { seen_path = ENV["PATH"] }

      expect(seen_path).to eq("/usr/local/bin:/usr/bin")
    end

    it "restores ENV after the block returns" do
      ENV["GEM_HOME"] = "/original/gems"
      ENV["PATH"] = "/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin:/usr/bin"

      described_class.with_clean_subprocess_env { :ok }

      expect(ENV["GEM_HOME"]).to eq("/original/gems")
      expect(ENV["PATH"]).to eq("/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin:/usr/bin")
    end

    it "restores ENV even when the block raises" do
      ENV["GEM_HOME"] = "/original/gems"
      ENV["PATH"] = "/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin:/usr/bin"

      expect {
        described_class.with_clean_subprocess_env { raise "boom" }
      }.to raise_error("boom")

      expect(ENV["GEM_HOME"]).to eq("/original/gems")
      expect(ENV["PATH"]).to eq("/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin:/usr/bin")
    end

    it "no-ops when called without a block" do
      ENV["GEM_HOME"] = "/original/gems"
      expect { described_class.with_clean_subprocess_env }.not_to raise_error
      expect(ENV["GEM_HOME"]).to eq("/original/gems")
    end
  end
end
