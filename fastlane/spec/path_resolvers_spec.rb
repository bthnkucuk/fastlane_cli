# frozen_string_literal: true

# Coverage-hardening specs for FastlaneCliConfig path / option / env resolvers
# that previously had NO dedicated spec (or only partial happy-path coverage).
#
# Audited gap (see PR body): resolve_app_root, resolve_runner_fastlane_path,
# in_app_root / in_runner_root, flutter_command / flutter_target /
# resolved_flutter_command, android_aab_path / ios_ipa_path, resolve_app_path
# (relative-vs-absolute), resolve_path_in_fastlane / absolute_metadata_path,
# the absolute_* family, option_or_env / absolute_option_or_env / path_option /
# maybe_absolute / path_or_default, app_root_prefixed_option_tokens,
# app_file_exists? / ensure_app_file / ensure_app_directory,
# normalize_shell_command, command_available? / clean_path_for_subprocess,
# colorize / pad_to_width / nearest_break, ui_important / ui_success,
# default_derived_data_root / fastlane_cli_cache_root /
# discover_swiftpm_upload_symbols, resolve_app_or_default_path and the iOS
# submission-config resolvers, materialize_review_information.
#
# Every example is hermetic: ENV is snapshot/restored, temp dirs only, no real
# network or shell-outs to flutter/fastlane/gradle/firebase.

RSpec.describe FastlaneCliConfig, "path & option resolvers" do
  TRACKED_RESOLVER_ENV_KEYS = %w[
    FASTLANE_ROOT FASTLANE_DIRECTORY APP_FASTLANE_PATH
    FASTLANE_APP_ROOT APP_ROOT
    FASTLANE_CLI_FASTLANE_PATH BUNDLE_GEMFILE
    FASTLANE_FLAVOR APP_FLAVOR FLAVOR
    FASTLANE_FLUTTER_CMD FLUTTER_CMD
    FASTLANE_FLUTTER_TARGET FLUTTER_TARGET
    IOS_IPA_PATH FASTLANE_IPA_PATH IOS_IPA_NAME FASTLANE_IPA_NAME
    GOOGLE_PLAY_JSON_KEY_PATH
    ANDROID_METADATA_PATH FASTLANE_ANDROID_METADATA_PATH
    IOS_METADATA_PATH FASTLANE_IOS_METADATA_PATH
    NO_COLOR
  ].freeze

  around(:each) do |ex|
    saved = TRACKED_RESOLVER_ENV_KEYS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    TRACKED_RESOLVER_ENV_KEYS.each { |k| ENV.delete(k) }
    begin
      ex.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_app_root
  # ---------------------------------------------------------------------------
  describe ".resolve_app_root" do
    it "prefers an explicit :app_root option" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        Dir.chdir(real) do
          expect(described_class.resolve_app_root(app_root: "myapp"))
            .to eq(File.join(real, "myapp"))
        end
      end
    end

    it "accepts :root_path and :project_root aliases" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        Dir.chdir(real) do
          expect(described_class.resolve_app_root(root_path: "viaroot"))
            .to eq(File.join(real, "viaroot"))
          expect(described_class.resolve_app_root(project_root: "viaproj"))
            .to eq(File.join(real, "viaproj"))
        end
      end
    end

    it "falls back to FASTLANE_APP_ROOT env when no option is given" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = File.join(real, "envapp")
        expect(described_class.resolve_app_root({})).to eq(File.join(real, "envapp"))
      end
    end

    it "derives the app root as the parent of the fastlane root when nothing is set" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "project", "fastlane")
        expect(described_class.resolve_app_root(fastlane_root: fastlane_root))
          .to eq(File.join(real, "project"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_runner_fastlane_path / in_runner_root
  # ---------------------------------------------------------------------------
  describe ".resolve_runner_fastlane_path" do
    it "prefers an explicit :fastlane_runner_path option" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        Dir.chdir(real) do
          expect(described_class.resolve_runner_fastlane_path(fastlane_runner_path: "runner"))
            .to eq(File.join(real, "runner"))
        end
      end
    end

    it "falls back to FASTLANE_CLI_FASTLANE_PATH env" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        ENV["FASTLANE_CLI_FASTLANE_PATH"] = File.join(real, "envrunner")
        expect(described_class.resolve_runner_fastlane_path({}))
          .to eq(File.join(real, "envrunner"))
      end
    end

    it "falls back to the BUNDLE_GEMFILE directory when set" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        ENV["BUNDLE_GEMFILE"] = File.join(real, "Gemfile")
        expect(described_class.resolve_runner_fastlane_path({})).to eq(real)
      end
    end
  end

  describe ".in_app_root / .in_runner_root" do
    it "prefixes a command with a cd into the (shell-escaped) app root" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        cmd = described_class.in_app_root("flutter build apk", app_root: real)
        expect(cmd).to start_with("cd ")
        expect(cmd).to include(real)
        expect(cmd).to end_with("&& flutter build apk")
      end
    end

    it "shell-escapes an app root containing a space" do
      Dir.mktmpdir do |tmp|
        spaced = File.join(File.realpath(tmp), "my app")
        FileUtils.mkdir_p(spaced)
        cmd = described_class.in_app_root("echo hi", app_root: spaced)
        expect(cmd).to include('my\ app')
      end
    end

    it "in_runner_root chdirs into the parent of the runner fastlane dir" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        runner = File.join(real, "project", "fastlane")
        cmd = described_class.in_runner_root("fastlane ios test_flight", fastlane_runner_path: runner)
        expect(cmd).to start_with("cd ")
        expect(cmd).to include(File.join(real, "project"))
        expect(cmd).to end_with("&& fastlane ios test_flight")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # flutter_command / resolved_flutter_command / flutter_target
  # ---------------------------------------------------------------------------
  describe ".flutter_command" do
    it "defaults to 'fvm flutter'" do
      expect(described_class.flutter_command({})).to eq("fvm flutter")
    end

    it "prefers an explicit option, trimmed" do
      expect(described_class.flutter_command(flutter_cmd: "  flutter  ")).to eq("flutter")
    end

    it "honours the FASTLANE_FLUTTER_CMD env var" do
      ENV["FASTLANE_FLUTTER_CMD"] = "flutter"
      expect(described_class.flutter_command({})).to eq("flutter")
    end

    it "resolved_flutter_command is an alias of flutter_command" do
      expect(described_class.resolved_flutter_command(flutter_cmd: "flutter"))
        .to eq(described_class.flutter_command(flutter_cmd: "flutter"))
    end
  end

  describe ".flutter_target" do
    it "prefers an explicit :target option, trimmed" do
      expect(described_class.flutter_target(target: "  lib/main_dev.dart  "))
        .to eq("lib/main_dev.dart")
    end

    it "honours the FASTLANE_FLUTTER_TARGET env var" do
      ENV["FASTLANE_FLUTTER_TARGET"] = "lib/main_env.dart"
      expect(described_class.flutter_target({})).to eq("lib/main_env.dart")
    end

    it "returns nil when no flavor resolves and nothing is set" do
      expect(described_class.flutter_target({})).to be_nil
    end

    it "returns the conventional lib/main_<flavor>.dart when that file exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        write_file(File.join(app_root, "lib", "main_staging.dart"), "void main() {}")
        expect(described_class.flutter_target(app_root: app_root, flavor: "staging"))
          .to eq("lib/main_staging.dart")
      end
    end

    it "returns nil when the conventional flavor entrypoint is absent" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.flutter_target(app_root: app_root, flavor: "staging")).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # android_aab_path / ios_ipa_path
  # ---------------------------------------------------------------------------
  describe ".android_aab_path" do
    it "uses the flavorless release path when no flavor resolves" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.android_aab_path({}))
          .to eq(File.join(app_root, "build/app/outputs/bundle/release/app-release.aab"))
      end
    end

    it "uses the flavored release path when a flavor resolves" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.android_aab_path(flavor: "free"))
          .to eq(File.join(app_root, "build/app/outputs/bundle/freeRelease/app-free-release.aab"))
      end
    end

    it "honours an explicit :aab option resolved against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.android_aab_path(aab: "dist/app.aab"))
          .to eq(File.join(app_root, "dist/app.aab"))
      end
    end
  end

  describe ".ios_ipa_path" do
    it "returns the legacy Runner.ipa default when no IPA file exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.ios_ipa_path({}))
          .to eq(File.join(app_root, "build/ios/ipa/Runner.ipa"))
      end
    end

    it "picks an explicitly-named IPA when it exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        ipa = write_file(File.join(app_root, "build/ios/ipa", "MyApp.ipa"), "ipa")
        expect(described_class.ios_ipa_path(ipa_name: "MyApp.ipa")).to eq(ipa)
      end
    end

    it "falls back to the freshest .ipa in the directory when no candidate name matches" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        old = write_file(File.join(app_root, "build/ios/ipa", "old.ipa"), "old")
        newest = write_file(File.join(app_root, "build/ios/ipa", "new.ipa"), "new")
        File.utime(Time.now - 7200, Time.now - 7200, old)
        File.utime(Time.now, Time.now, newest)
        expect(described_class.ios_ipa_path({})).to eq(newest)
      end
    end

    it "honours an explicit :ipa option (absolute resolution)" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.ios_ipa_path(ipa: "dist/Build.ipa"))
          .to eq(File.join(app_root, "dist/Build.ipa"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_path_in_fastlane / absolute_metadata_path
  # ---------------------------------------------------------------------------
  describe ".resolve_path_in_fastlane" do
    it "passes an absolute explicit option through unchanged" do
      result = described_class.resolve_path_in_fastlane(
        options: { metadata_path: "/abs/meta" },
        option_key: :metadata_path,
        env_keys: %w[META_ENV],
        default_relative: "android/metadata"
      )
      expect(result).to eq("/abs/meta")
    end

    it "expands a relative explicit option against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        result = described_class.resolve_path_in_fastlane(
          options: { metadata_path: "rel/meta", app_root: app_root },
          option_key: :metadata_path,
          env_keys: %w[META_ENV],
          default_relative: "android/metadata"
        )
        expect(result).to eq(File.join(app_root, "rel/meta"))
      end
    end

    it "falls back to the default_relative under the fastlane root when nothing is set" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        result = described_class.resolve_path_in_fastlane(
          options: { fastlane_root: fastlane_root },
          option_key: :metadata_path,
          env_keys: %w[META_ENV],
          default_relative: "android/metadata"
        )
        expect(result).to eq(File.join(fastlane_root, "android/metadata"))
      end
    end
  end

  describe ".absolute_metadata_path" do
    it "uses the android default under the fastlane root" do
      Dir.mktmpdir do |tmp|
        fastlane_root = File.join(File.realpath(tmp), "fastlane")
        expect(
          described_class.absolute_metadata_path({ fastlane_root: fastlane_root }, platform: :android)
        ).to eq(File.join(fastlane_root, "android/metadata"))
      end
    end

    it "uses the ios default for any non-android platform" do
      Dir.mktmpdir do |tmp|
        fastlane_root = File.join(File.realpath(tmp), "fastlane")
        expect(
          described_class.absolute_metadata_path({ fastlane_root: fastlane_root }, platform: :ios)
        ).to eq(File.join(fastlane_root, "ios/metadata"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # option_or_env / absolute_option_or_env / path_option / maybe_absolute /
  # path_or_default
  # ---------------------------------------------------------------------------
  describe ".option_or_env" do
    it "prefers the option, then env, then nil" do
      ENV["FASTLANE_FLAVOR"] = "envval"
      expect(described_class.option_or_env({ flavor: "  optval  " }, :flavor, %w[FASTLANE_FLAVOR]))
        .to eq("optval")
      expect(described_class.option_or_env({}, :flavor, %w[FASTLANE_FLAVOR])).to eq("envval")
      expect(described_class.option_or_env({}, :flavor, %w[MISSING_ENV])).to be_nil
    end
  end

  describe ".absolute_option_or_env" do
    it "resolves an option value against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(
          described_class.absolute_option_or_env(
            { json: "creds/key.json", app_root: app_root },
            option_key: :json, env_keys: %w[SOME_ENV]
          )
        ).to eq(File.join(app_root, "creds/key.json"))
      end
    end

    it "returns nil when neither option nor env is set" do
      expect(
        described_class.absolute_option_or_env({}, option_key: :json, env_keys: %w[MISSING_ENV])
      ).to be_nil
    end
  end

  describe ".path_option" do
    it "returns nil for a blank value" do
      expect(described_class.path_option({ x: "" }, :x)).to be_nil
      expect(described_class.path_option({}, :x)).to be_nil
    end

    it "resolves a present value against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.path_option({ x: "p/q", app_root: app_root }, :x))
          .to eq(File.join(app_root, "p/q"))
      end
    end
  end

  describe ".maybe_absolute" do
    it "returns nil for blank input" do
      expect(described_class.maybe_absolute(nil)).to be_nil
      expect(described_class.maybe_absolute("  ")).to be_nil
    end

    it "resolves a relative path against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.maybe_absolute("a/b", app_root: app_root))
          .to eq(File.join(app_root, "a/b"))
      end
    end
  end

  describe ".path_or_default" do
    it "uses the default when the value is blank" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.path_or_default("", "fallback/dir", app_root: app_root))
          .to eq(File.join(app_root, "fallback/dir"))
      end
    end

    it "uses the provided value when it is present" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.path_or_default("real/dir", "fallback/dir", app_root: app_root))
          .to eq(File.join(app_root, "real/dir"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # absolute_* family
  # ---------------------------------------------------------------------------
  describe ".absolute_json_key" do
    it "resolves the GOOGLE_PLAY_JSON_KEY_PATH env var against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["GOOGLE_PLAY_JSON_KEY_PATH"] = "secrets/play.json"
        expect(described_class.absolute_json_key(app_root: app_root))
          .to eq(File.join(app_root, "secrets/play.json"))
      end
    end

    it "prefers an explicit :json_key option over the env var" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["GOOGLE_PLAY_JSON_KEY_PATH"] = "secrets/env.json"
        expect(described_class.absolute_json_key(json_key: "secrets/opt.json", app_root: app_root))
          .to eq(File.join(app_root, "secrets/opt.json"))
      end
    end

    it "returns nil when neither option nor env is set" do
      expect(described_class.absolute_json_key({})).to be_nil
    end
  end

  describe ".absolute_ios_file" do
    it "uses the fallback value when neither option nor env is set" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(
          described_class.absolute_ios_file(
            { app_root: app_root }, option_key: :key, env_keys: %w[NONE], fallback: "ios/key.p8"
          )
        ).to eq(File.join(app_root, "ios/key.p8"))
      end
    end

    it "prefers the option value" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(
          described_class.absolute_ios_file(
            { key: "ios/opt.p8", app_root: app_root },
            option_key: :key, env_keys: %w[NONE], fallback: "ios/fallback.p8"
          )
        ).to eq(File.join(app_root, "ios/opt.p8"))
      end
    end
  end

  describe ".absolute_workspace_path / .absolute_output_directory / .absolute_apk_path" do
    it "default workspace is ios/Runner.xcworkspace under the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_workspace_path(app_root: app_root))
          .to eq(File.join(app_root, "ios/Runner.xcworkspace"))
      end
    end

    it "honours an explicit :workspace option" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_workspace_path(workspace: "ios/App.xcworkspace", app_root: app_root))
          .to eq(File.join(app_root, "ios/App.xcworkspace"))
      end
    end

    it "default output directory is build/ios under the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_output_directory(app_root: app_root))
          .to eq(File.join(app_root, "build/ios"))
      end
    end

    it "default apk path is the flutter-apk release artifact under the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_apk_path(app_root: app_root))
          .to eq(File.join(app_root, "build/app/outputs/flutter-apk/app-release.apk"))
      end
    end
  end

  describe ".absolute_path_list" do
    it "resolves every entry against the app root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_path_list(%w[a/x b/y], app_root: app_root))
          .to eq([File.join(app_root, "a/x"), File.join(app_root, "b/y")])
      end
    end

    it "wraps a single non-array value" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect(described_class.absolute_path_list("solo", app_root: app_root))
          .to eq([File.join(app_root, "solo")])
      end
    end

    it "returns an empty array for nil" do
      expect(described_class.absolute_path_list(nil)).to eq([])
    end
  end

  describe ".app_root / .app_path" do
    it "app_root mirrors resolve_app_root" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.app_root({})).to eq(described_class.resolve_app_root({}))
      end
    end

    it "app_path mirrors resolve_app_path" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        ENV["FASTLANE_APP_ROOT"] = app_root
        expect(described_class.app_path("foo/bar")).to eq(File.join(app_root, "foo/bar"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # app_root_prefixed_option_tokens
  # ---------------------------------------------------------------------------
  describe ".app_root_prefixed_option_tokens" do
    it "returns [] for a non-hash input" do
      expect(described_class.app_root_prefixed_option_tokens(nil)).to eq([])
    end

    it "rewrites path-keyed token values to absolute paths and leaves the rest alone" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        tokens = described_class.app_root_prefixed_option_tokens(
          { json_key: "creds/key.json", track: "alpha", app_root: app_root },
          allowed_keys: %i[json_key track],
          path_keys: %i[json_key]
        )
        expect(tokens).to include("track:alpha")
        json_token = tokens.find { |t| t.start_with?("json_key:") }
        expect(json_token).to eq("json_key:#{File.join(app_root, 'creds/key.json')}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # app_file_exists? / ensure_app_file / ensure_app_directory
  # ---------------------------------------------------------------------------
  describe ".app_file_exists?" do
    it "returns true when the resolved file exists, false otherwise" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        write_file(File.join(app_root, "present.txt"), "x")
        expect(described_class.app_file_exists?("present.txt", app_root: app_root)).to be true
        expect(described_class.app_file_exists?("missing.txt", app_root: app_root)).to be false
      end
    end

    it "returns false for a blank path" do
      expect(described_class.app_file_exists?("", {})).to be false
    end
  end

  describe ".ensure_app_file" do
    it "returns the resolved path when the file exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        path = write_file(File.join(app_root, "f.txt"), "x")
        expect(described_class.ensure_app_file("f.txt", { app_root: app_root })).to eq(path)
      end
    end

    it "raises a UI error when the file is missing" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        expect {
          described_class.ensure_app_file("gone.txt", { app_root: app_root }, label: "config")
        }.to raise_error(FastlaneCore::UIError, /Missing config/)
      end
    end
  end

  describe ".ensure_app_directory" do
    it "creates the directory when it is absent and returns its path" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        target = File.join(app_root, "new/nested")
        expect(Dir.exist?(target)).to be false
        result = described_class.ensure_app_directory("new/nested", { app_root: app_root })
        expect(result).to eq(target)
        expect(Dir.exist?(target)).to be true
      end
    end

    it "is idempotent when the directory already exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        FileUtils.mkdir_p(File.join(app_root, "existing"))
        expect {
          described_class.ensure_app_directory("existing", { app_root: app_root })
        }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_shell_command
  # ---------------------------------------------------------------------------
  describe ".normalize_shell_command" do
    it "strips surrounding whitespace" do
      expect(described_class.normalize_shell_command("  flutter build  ")).to eq("flutter build")
    end

    it "coerces nil to an empty string" do
      expect(described_class.normalize_shell_command(nil)).to eq("")
    end
  end

  # ---------------------------------------------------------------------------
  # command_available? / clean_path_for_subprocess
  # ---------------------------------------------------------------------------
  describe ".command_available?" do
    it "returns true for a command that is on PATH" do
      expect(described_class.command_available?("ls")).to be true
    end

    it "returns false for a command that is not on PATH" do
      expect(described_class.command_available?("definitely-not-a-real-binary-xyz")).to be false
    end

    it "returns false for a blank name without shelling out" do
      expect(described_class.command_available?(nil)).to be false
      expect(described_class.command_available?("")).to be false
    end

    it "never raises even if the underlying lookup blows up" do
      allow(described_class).to receive(:system).and_raise(StandardError, "boom")
      expect(described_class.command_available?("anything")).to be false
    end
  end

  describe ".clean_path_for_subprocess" do
    it "returns nil for a blank path" do
      expect(described_class.clean_path_for_subprocess(nil)).to be_nil
      expect(described_class.clean_path_for_subprocess("")).to be_nil
    end

    it "strips brew fastlane PATH segments and keeps the rest" do
      path = [
        "/opt/homebrew/Cellar/fastlane/2.234.0/libexec/bin",
        "/Users/me/.local/share/fastlane/4.0.0/bin",
        "/usr/local/bin",
        "/usr/bin"
      ].join(File::PATH_SEPARATOR)
      expect(described_class.clean_path_for_subprocess(path))
        .to eq("/usr/local/bin:/usr/bin")
    end

    it "leaves a clean PATH untouched" do
      expect(described_class.clean_path_for_subprocess("/usr/local/bin:/usr/bin"))
        .to eq("/usr/local/bin:/usr/bin")
    end
  end

  # ---------------------------------------------------------------------------
  # colorize / pad_to_width / nearest_break
  # ---------------------------------------------------------------------------
  describe ".colorize" do
    it "wraps text in the colour code when colour is enabled" do
      ENV["NO_COLOR"] = ""
      result = described_class.colorize("hi", "\e[31m")
      expect(result).to start_with("\e[31m")
      expect(result).to end_with(FastlaneCliConfig::SUMMARY_BOX_RESET)
      expect(result).to include("hi")
    end

    it "returns plain text when NO_COLOR is set" do
      ENV["NO_COLOR"] = "1"
      expect(described_class.colorize("hi", "\e[31m")).to eq("hi")
    end
  end

  describe ".pad_to_width" do
    it "right-pads with spaces to the requested width" do
      expect(described_class.pad_to_width("ab", 5)).to eq("ab   ")
    end

    it "leaves text already at or over width unchanged" do
      expect(described_class.pad_to_width("abcdef", 3)).to eq("abcdef")
    end

    it "pads by visible length, ignoring ANSI codes" do
      coloured = "\e[31mab\e[0m"
      padded = described_class.pad_to_width(coloured, 5)
      expect(described_class.visible_length(padded)).to eq(5)
    end
  end

  describe ".nearest_break" do
    it "hard-cuts at the width when there is no space" do
      expect(described_class.nearest_break("abcdef", 3)).to eq(3)
    end

    it "breaks at the last space within the width" do
      expect(described_class.nearest_break("ab cdef", 5)).to eq(2)
    end

    it "returns the full length when the text fits within the width" do
      expect(described_class.nearest_break("abc", 10)).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # ui_important / ui_success (FastlaneCore is stubbed in spec_helper)
  # ---------------------------------------------------------------------------
  describe ".ui_important / .ui_success" do
    it "routes ui_important through FastlaneCore::UI when defined" do
      described_class.ui_important("heads up")
      expect(FastlaneCore::UI.captured_messages.join("\n")).to include("heads up")
    end

    it "routes ui_success through FastlaneCore::UI when defined" do
      described_class.ui_success("all good")
      expect(FastlaneCore::UI.captured_messages.join("\n")).to include("all good")
    end
  end

  # ---------------------------------------------------------------------------
  # default_derived_data_root / fastlane_cli_cache_root
  # ---------------------------------------------------------------------------
  describe ".default_derived_data_root / .fastlane_cli_cache_root" do
    it "default_derived_data_root points at Xcode's DerivedData under the home dir" do
      expect(described_class.default_derived_data_root)
        .to eq(File.expand_path("~/Library/Developer/Xcode/DerivedData"))
    end

    it "fastlane_cli_cache_root points at the per-user Caches dir" do
      expect(described_class.fastlane_cli_cache_root)
        .to eq(File.expand_path("~/Library/Caches/fastlane_cli"))
    end
  end

  # ---------------------------------------------------------------------------
  # discover_swiftpm_upload_symbols
  # ---------------------------------------------------------------------------
  describe ".discover_swiftpm_upload_symbols" do
    it "returns nil for a blank root" do
      expect(described_class.discover_swiftpm_upload_symbols(nil)).to be_nil
      expect(described_class.discover_swiftpm_upload_symbols("")).to be_nil
    end

    it "returns nil when the root directory does not exist" do
      expect(described_class.discover_swiftpm_upload_symbols("/no/such/dd/root")).to be_nil
    end

    it "returns nil when the root exists but has no matches" do
      Dir.mktmpdir do |dd|
        FileUtils.mkdir_p(File.join(dd, "Runner-x/Build"))
        expect(described_class.discover_swiftpm_upload_symbols(dd)).to be_nil
      end
    end

    it "returns the most-recently-modified matching binary" do
      Dir.mktmpdir do |dd|
        glob = "SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
        old = File.join(dd, "Runner-a", glob)
        new = File.join(dd, "Runner-b", glob)
        [old, new].each do |p|
          FileUtils.mkdir_p(File.dirname(p))
          File.write(p, "bin")
        end
        File.utime(Time.now - 7200, Time.now - 7200, old)
        File.utime(Time.now, Time.now, new)
        expect(described_class.discover_swiftpm_upload_symbols(dd)).to eq(new)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_app_or_default_path + iOS submission-config resolvers
  # ---------------------------------------------------------------------------
  describe ".resolve_app_or_default_path" do
    it "prefers the app-relative file when it exists" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "app_fastlane")
        runner_root = File.join(real, "runner_fastlane")
        app_file = write_file(File.join(fastlane_root, "ios/cfg.json"), "{}")
        write_file(File.join(runner_root, "ios/defaults/cfg.json"), "{}")

        result = described_class.resolve_app_or_default_path(
          options: { fastlane_root: fastlane_root, fastlane_runner_path: runner_root },
          app_relative: "ios/cfg.json",
          default_relative: "ios/defaults/cfg.json"
        )
        expect(result).to eq(app_file)
      end
    end

    it "falls back to the runner default when the app file is absent" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "app_fastlane")
        runner_root = File.join(real, "runner_fastlane")
        FileUtils.mkdir_p(fastlane_root)
        default_file = write_file(File.join(runner_root, "ios/defaults/cfg.json"), "{}")

        result = described_class.resolve_app_or_default_path(
          options: { fastlane_root: fastlane_root, fastlane_runner_path: runner_root },
          app_relative: "ios/cfg.json",
          default_relative: "ios/defaults/cfg.json"
        )
        expect(result).to eq(default_file)
      end
    end

    it "returns nil when neither the app file nor the default exists" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "app_fastlane")
        runner_root = File.join(real, "runner_fastlane")
        [fastlane_root, runner_root].each { |d| FileUtils.mkdir_p(d) }
        result = described_class.resolve_app_or_default_path(
          options: { fastlane_root: fastlane_root, fastlane_runner_path: runner_root },
          app_relative: "ios/cfg.json",
          default_relative: "ios/defaults/cfg.json"
        )
        expect(result).to be_nil
      end
    end
  end

  describe ".resolve_app_rating_config_path" do
    it "prefers an explicit option path that exists" do
      Dir.mktmpdir do |tmp|
        app_root = File.realpath(tmp)
        explicit = write_file(File.join(app_root, "rating.json"), "{}")
        result = described_class.resolve_app_rating_config_path(
          app_rating_config_path: "rating.json", app_root: app_root
        )
        expect(result).to eq(explicit)
      end
    end

    it "falls back to the app-level ios/app_rating_config.json" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        runner_root = File.join(real, "runner")
        [fastlane_root, runner_root].each { |d| FileUtils.mkdir_p(d) }
        app_file = write_file(File.join(fastlane_root, "ios/app_rating_config.json"), "{}")
        result = described_class.resolve_app_rating_config_path(
          fastlane_root: fastlane_root, fastlane_runner_path: runner_root
        )
        expect(result).to eq(app_file)
      end
    end
  end

  describe ".resolve_submission_information_path" do
    it "falls back to the runner default when no app file exists" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        runner_root = File.join(real, "runner")
        FileUtils.mkdir_p(fastlane_root)
        default_file = write_file(
          File.join(runner_root, "ios/defaults/submission_information.json"), "{}"
        )
        result = described_class.resolve_submission_information_path(
          fastlane_root: fastlane_root, fastlane_runner_path: runner_root
        )
        expect(result).to eq(default_file)
      end
    end
  end

  describe ".resolve_app_privacy_details_path" do
    it "returns the app file when present" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        runner_root = File.join(real, "runner")
        [fastlane_root, runner_root].each { |d| FileUtils.mkdir_p(d) }
        app_file = write_file(File.join(fastlane_root, "ios/app_privacy_details.json"), "{}")
        result = described_class.resolve_app_privacy_details_path(
          { fastlane_root: fastlane_root, fastlane_runner_path: runner_root }
        )
        expect(result).to eq(app_file)
      end
    end

    it "with must_exist: false returns nil when nothing resolves" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        runner_root = File.join(real, "runner")
        [fastlane_root, runner_root].each { |d| FileUtils.mkdir_p(d) }
        result = described_class.resolve_app_privacy_details_path(
          { fastlane_root: fastlane_root, fastlane_runner_path: runner_root },
          must_exist: false
        )
        expect(result).to be_nil
      end
    end

    it "with must_exist: true returns the expected app path even when the file is absent" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        fastlane_root = File.join(real, "fastlane")
        runner_root = File.join(real, "runner")
        [fastlane_root, runner_root].each { |d| FileUtils.mkdir_p(d) }
        result = described_class.resolve_app_privacy_details_path(
          { fastlane_root: fastlane_root, fastlane_runner_path: runner_root }
        )
        expect(result).to eq(File.join(fastlane_root, "ios/app_privacy_details.json"))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # materialize_review_information / restore_review_information
  # ---------------------------------------------------------------------------
  describe ".materialize_review_information" do
    it "returns [] when the runner defaults directory is absent" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        meta = File.join(real, "metadata")
        runner_root = File.join(real, "runner")
        FileUtils.mkdir_p(runner_root)
        result = described_class.materialize_review_information(
          { fastlane_runner_path: runner_root }, metadata_path: meta
        )
        expect(result).to eq([])
      end
    end

    it "sprays default review files into the metadata dir and returns restorable handles" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        meta = File.join(real, "metadata")
        runner_root = File.join(real, "runner")
        defaults = File.join(runner_root, "ios/defaults/review_information")
        write_file(File.join(defaults, "first_name.txt"), "Demo")
        write_file(File.join(defaults, "email_address.txt"), "demo@example.com")

        restorable = described_class.materialize_review_information(
          { fastlane_runner_path: runner_root }, metadata_path: meta
        )

        target = File.join(meta, "review_information")
        expect(File.read(File.join(target, "first_name.txt"))).to eq("Demo")
        expect(File.read(File.join(target, "email_address.txt"))).to eq("demo@example.com")
        expect(restorable.size).to eq(2)
        expect(restorable.map(&:first)).to all(include("review_information"))
      end
    end

    it "respects an existing non-empty per-app override" do
      Dir.mktmpdir do |tmp|
        real = File.realpath(tmp)
        meta = File.join(real, "metadata")
        runner_root = File.join(real, "runner")
        defaults = File.join(runner_root, "ios/defaults/review_information")
        write_file(File.join(defaults, "first_name.txt"), "DefaultName")
        write_file(File.join(meta, "review_information", "first_name.txt"), "AppOverride")

        described_class.materialize_review_information(
          { fastlane_runner_path: runner_root }, metadata_path: meta
        )

        expect(File.read(File.join(meta, "review_information", "first_name.txt")))
          .to eq("AppOverride")
      end
    end
  end

  describe ".restore_review_information" do
    it "restores originals and deletes files that did not exist before" do
      Dir.mktmpdir do |tmp|
        dir = File.realpath(tmp)
        kept = write_file(File.join(dir, "kept.txt"), "modified")
        added = write_file(File.join(dir, "added.txt"), "sprayed")

        described_class.restore_review_information([
          [kept, true, "original"],
          [added, false, nil]
        ])

        expect(File.read(kept)).to eq("original")
        expect(File.exist?(added)).to be false
      end
    end
  end
end
