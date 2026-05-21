require "fileutils"
require "pathname"
require "set"
require "shellwords"

module FastlaneCliConfig
  module_function

  TRUE_VALUES = %w[1 true yes y on].freeze
  FALSE_VALUES = %w[0 false no n off].freeze

  def blank?(value)
    return true if value.nil?

    value.to_s.strip.empty?
  end

  def option(options, *keys)
    return nil unless options.respond_to?(:key?)

    keys.flatten.each do |key|
      [key, key.to_s, key.to_sym].uniq.each do |candidate|
        next unless options.key?(candidate)

        value = options[candidate]
        return value unless blank?(value)
      end
    end
    nil
  end

  def env_first(*keys)
    keys.each do |key|
      value = ENV[key]
      return value unless blank?(value)
    end
    nil
  end

  def parse_bool(value, default:)
    return value if value == true || value == false

    normalized = value.to_s.strip.downcase
    return true if TRUE_VALUES.include?(normalized)
    return false if FALSE_VALUES.include?(normalized)

    default
  end

  def bool_option(options, key, default:)
    value = option(options, key)
    return default if value.nil?

    parse_bool(value, default: default)
  end

  def resolve_fastlane_root(options = {})
    explicit = option(options, :fastlane_root, :fastlane_path, :fastlane_directory)
    return File.expand_path(explicit.to_s, Dir.pwd) unless blank?(explicit)

    from_env = env_first("FASTLANE_ROOT", "FASTLANE_DIRECTORY", "APP_FASTLANE_PATH")
    return File.expand_path(from_env.to_s, Dir.pwd) unless blank?(from_env)

    gemfile = ENV["BUNDLE_GEMFILE"]
    return File.dirname(File.expand_path(gemfile)) unless blank?(gemfile)

    File.expand_path("fastlane", Dir.pwd)
  end

  def resolve_app_root(options = {})
    explicit = option(options, :app_root, :root_path, :project_root)
    return File.expand_path(explicit.to_s, Dir.pwd) unless blank?(explicit)

    from_env = env_first("FASTLANE_APP_ROOT", "APP_ROOT")
    return File.expand_path(from_env.to_s, Dir.pwd) unless blank?(from_env)

    File.expand_path("..", resolve_fastlane_root(options))
  end

  def resolve_pubspec_path(options = {})
    explicit = option(options, :pubspec_path)
    if explicit && !blank?(explicit)
      full_path = File.expand_path(explicit.to_s, Dir.pwd)
      FastlaneCore::UI.user_error!("pubspec.yaml not found at #{full_path}") unless File.exist?(full_path)
      return full_path
    end

    from_env = env_first("FASTLANE_PUBSPEC_PATH", "PUBSPEC_PATH")
    if from_env && !blank?(from_env)
      full_path = File.expand_path(from_env.to_s, Dir.pwd)
      FastlaneCore::UI.user_error!("pubspec.yaml not found at #{full_path}") unless File.exist?(full_path)
      return full_path
    end

    app_root = resolve_app_root(options)
    fastlane_root = resolve_fastlane_root(options)
    candidates = [
      File.expand_path("pubspec.yaml", app_root),
      File.expand_path("pubspec.yaml", Dir.pwd),
      File.expand_path("../pubspec.yaml", Dir.pwd),
      File.expand_path("../pubspec.yaml", fastlane_root)
    ].uniq

    found = candidates.find { |path| File.exist?(path) }
    FastlaneCore::UI.user_error!("Could not find pubspec.yaml. Tried: #{candidates.join(', ')}") unless found

    found
  end

  def resolve_flavor(options = {})
    value = option(options, :flavor)
    return value.to_s.strip unless blank?(value)

    from_env = env_first("FASTLANE_FLAVOR", "APP_FLAVOR", "FLAVOR")
    return nil if blank?(from_env)

    from_env.to_s.strip
  end

  # Build the Firebase Crashlytics NDK native-symbol upload Gradle task name:
  # `uploadCrashlyticsSymbolFile<Flavor><BuildType>`.
  #
  # Gradle variant casing only capitalises the FIRST letter of each segment
  # (`narravo` → `Narravo`, `release` → `Release`) — it does NOT title-case
  # multi-word names, so a flavor like `freeStaging` stays `FreeStaging`.
  # When no flavor resolves the task collapses to
  # `uploadCrashlyticsSymbolFile<BuildType>`.
  #
  # Pure function — no ENV / filesystem access — so it is unit-testable.
  def crashlytics_symbol_task(flavor:, build_type: "release")
    flavor_part = blank?(flavor) ? "" : capitalize_variant_segment(flavor)
    type_part = capitalize_variant_segment(blank?(build_type) ? "release" : build_type)
    "uploadCrashlyticsSymbolFile#{flavor_part}#{type_part}"
  end

  # Capitalise only the first character of a Gradle variant segment, leaving
  # the rest untouched (mirrors Gradle's own variant-name capitalisation).
  def capitalize_variant_segment(value)
    str = value.to_s.strip
    return "" if str.empty?

    str[0].upcase + str[1..].to_s
  end

  def resolve_identifier(options = {}, platform:)
    explicit = option(options, :app_identifier, :bundle_identifier, :package_name)
    return explicit.to_s.strip unless blank?(explicit)

    from_env = case platform
               when :android
                 env_first("ANDROID_PACKAGE_NAME", "FASTLANE_ANDROID_APP_IDENTIFIER")
               when :ios
                 env_first("IOS_APP_IDENTIFIER", "FASTLANE_IOS_APP_IDENTIFIER")
               else
                 nil
               end
    return from_env.to_s.strip unless blank?(from_env)

    shared_env = env_first("FASTLANE_APP_IDENTIFIER", "APP_IDENTIFIER")
    return shared_env.to_s.strip unless blank?(shared_env)

    flavor = resolve_flavor(options)
    template = option(options, :app_identifier_template, :identifier_template)
    template = case platform
               when :android
                 template || env_first("ANDROID_PACKAGE_NAME_TEMPLATE", "FASTLANE_APP_IDENTIFIER_TEMPLATE")
               when :ios
                 template || env_first("IOS_APP_IDENTIFIER_TEMPLATE", "FASTLANE_APP_IDENTIFIER_TEMPLATE")
               else
                 template
               end
    template ||= env_first("APP_IDENTIFIER_TEMPLATE")

    if template && !blank?(template) && flavor && !blank?(flavor)
      return template.to_s.gsub("%{flavor}", flavor.to_s)
    end

    platform_label = platform.to_s.upcase
    FastlaneCore::UI.user_error!(
      "Missing #{platform_label} identifier. Provide app_identifier/package_name option or set #{platform_label == 'ANDROID' ? 'ANDROID_PACKAGE_NAME' : 'IOS_APP_IDENTIFIER'} / FASTLANE_APP_IDENTIFIER env."
    )
  end

  def resolve_path_in_fastlane(options:, option_key:, env_keys:, default_relative:)
    app_root = resolve_app_root(options)

    explicit = option(options, option_key)
    unless blank?(explicit)
      path = explicit.to_s
      return path if Pathname.new(path).absolute?

      return File.expand_path(path, app_root)
    end

    from_env = env_first(*env_keys)
    unless blank?(from_env)
      path = from_env.to_s
      return path if Pathname.new(path).absolute?

      return File.expand_path(path, app_root)
    end

    File.expand_path(default_relative, resolve_fastlane_root(options))
  end

  def flutter_command(options = {})
    explicit = option(options, :flutter_cmd, :flutter_command)
    return explicit.to_s.strip unless blank?(explicit)

    from_env = env_first("FASTLANE_FLUTTER_CMD", "FLUTTER_CMD")
    return from_env.to_s.strip unless blank?(from_env)

    "fvm flutter"
  end

  def flutter_target(options = {})
    explicit = option(options, :target, :flutter_target)
    return explicit.to_s.strip unless blank?(explicit)

    from_env = env_first("FASTLANE_FLUTTER_TARGET", "FLUTTER_TARGET")
    return from_env.to_s.strip unless blank?(from_env)

    flavor = resolve_flavor(options)
    return nil if blank?(flavor)

    relative = "lib/main_#{flavor}.dart"
    full_path = File.expand_path(relative, resolve_app_root(options))
    File.exist?(full_path) ? relative : nil
  end

  def android_aab_path(options = {})
    explicit = option(options, :aab, :aab_path)
    return resolve_app_path(explicit.to_s.strip, options) unless blank?(explicit)

    flavor = resolve_flavor(options)
    relative = if flavor && !blank?(flavor)
                 "build/app/outputs/bundle/#{flavor}Release/app-#{flavor}-release.aab"
               else
                 "build/app/outputs/bundle/release/app-release.aab"
               end
    resolve_app_path(relative, options)
  end

  def resolve_app_path(path_value, options = {})
    return nil if blank?(path_value)

    path = path_value.to_s.strip
    return path if Pathname.new(path).absolute?

    File.expand_path(path, resolve_app_root(options))
  end

  def in_app_root(command, options = {})
    app_root = resolve_app_root(options)
    "cd #{Shellwords.escape(app_root)} && #{command}"
  end

  def resolve_runner_fastlane_path(options = {})
    explicit = option(options, :fastlane_runner_path, :fastlane_cli_fastlane_path)
    return File.expand_path(explicit.to_s, Dir.pwd) unless blank?(explicit)

    from_env = env_first("FASTLANE_CLI_FASTLANE_PATH")
    return File.expand_path(from_env.to_s, Dir.pwd) unless blank?(from_env)

    gemfile = ENV["BUNDLE_GEMFILE"]
    return File.dirname(File.expand_path(gemfile)) unless blank?(gemfile)

    File.expand_path("fastlane", Dir.pwd)
  end

  def in_runner_root(command, options = {})
    runner_root = File.expand_path("..", resolve_runner_fastlane_path(options))
    "cd #{Shellwords.escape(runner_root)} && #{command}"
  end

  # In-process cross-platform lane invocation.
  #
  # Replaces the pre-v0.4.1 pattern of
  #   sh("cd <runner> && fastlane <platform> <lane> k:v ...")
  # which spawned a *second* fastlane process via the shell. That child
  # process inherits the outer process's stdin file descriptor but NOT the
  # PTY-level routing v0.4.0's PromptParser uses — so when a sub-lane
  # prompts (e.g. App Store Connect 2FA), the user's typed response goes to
  # the outer process and the child waits forever.
  #
  # `fastfile.runner.execute` invokes the lane in the SAME Ruby process.
  # Stdin, lane_context, SharedValues, fastlane env, and the current TTY
  # are all shared, so:
  #   - Interactive prompts (2FA, yes/no) appear to the outer PTY directly.
  #   - The lane's return value is returned to the caller (no need to
  #     parse stdout for `[VERSION_DATA]` markers, though existing parsing
  #     is preserved for backward compatibility).
  #   - Errors propagate as Ruby exceptions, which call sites rescue and
  #     translate into the same "fallback unknown|0" log line as before.
  #
  # The first argument is the FastFile instance running the outer lane —
  # pass `self` from any `lane :foo do ... end` block. `runner` is an
  # *instance* accessor on `Fastlane::FastFile` (see fastlane source
  # `fastlane/lib/fastlane/fast_file.rb` `attr_accessor :runner`), so
  # there is no class-level `Fastlane::FastFile.runner` — v0.4.1 called
  # that and crashed every sub-lane invocation with
  # `undefined method 'runner' for class Fastlane::FastFile`. v0.4.2
  # fixes that by taking the FastFile instance explicitly.
  #
  # Requires the platform Fastfiles to be `import`-ed into the same
  # FastFile context. Top-level `fastlane/Fastfile` already does this:
  #   import File.expand_path("android/Fastfile", __dir__)
  #   import File.expand_path("ios/Fastfile",     __dir__)
  #
  # v0.4.5: Pin the working directory to the FastFile's parent (runner root)
  # for the duration of the sub-lane invocation. Without this, a previous
  # build step (`flutter build ipa` → xcodebuild → pod install, or
  # `flutter clean` / a temp-dir teardown) can leave the parent Ruby process's
  # cwd pointing at a now-deleted directory. When `runner.execute` then
  # runs the next sub-lane and `DocsGenerator.run` calls
  # `FastlaneCore::FastlaneFolder.path` (which calls `Dir.getwd`), Ruby
  # raises `Errno::ENOENT - No such file or directory - getcwd`. This
  # mirrors what `Fastlane::LaneManager.cruise_lane` does for the outer
  # CLI invocation (`Dir.chdir(File.expand_path("..", fastfile_path))`).
  def run_subline(fastfile, platform, lane, options = {})
    runner_root = resolve_runner_root_for_subline(fastfile)

    if runner_root.nil?
      # No path resolvable AND current cwd is healthy enough to keep using.
      # Just forward — there's nothing better to chdir to.
      return fastfile.runner.execute(lane.to_sym, platform.to_sym, options)
    end

    # Capture the cwd to restore *before* chdir-ing, but tolerate
    # Errno::ENOENT from `Dir.pwd` — if we're already in a deleted
    # directory the only sane restore target IS `runner_root` itself, so
    # there's nothing else to remember.
    #
    # We intentionally avoid the `Dir.chdir(path) { block }` form here:
    # Ruby's block form calls `Dir.getwd` internally to save the cwd for
    # restoration, which raises immediately if the current directory has
    # been deleted (exactly the bug we're trying to fix). The manual
    # capture-then-chdir below sidesteps that.
    saved_cwd = begin
      Dir.pwd
    rescue Errno::ENOENT
      nil
    end

    Dir.chdir(runner_root)
    begin
      fastfile.runner.execute(lane.to_sym, platform.to_sym, options)
    ensure
      # Restore the previous cwd if it still exists; otherwise stay in
      # runner_root (a known-good directory). Never re-raise from the
      # restore — that would mask the lane's real exception.
      begin
        if saved_cwd && Dir.exist?(saved_cwd)
          Dir.chdir(saved_cwd)
        end
      rescue StandardError
        # Swallow — runner_root is a perfectly valid resting cwd.
      end
    end
  end

  # Determine the directory we should chdir into before invoking a sub-lane.
  # Resolution order:
  #   1. `fastfile.path` (public-ish accessor; not always defined on
  #      `Fastlane::FastFile` but call sites' test doubles may expose it).
  #   2. `fastfile.instance_variable_get(:@path)` — what
  #      `Fastlane::FastFile#initialize` actually stores.
  #   3. `FastlaneCore::FastlaneFolder.fastfile_path` — the same lookup
  #      `cruise_lane` uses when no path is passed.
  # Returns an absolute directory path, or nil if nothing resolves AND the
  # current cwd is still readable (caller can run without chdir). Raises
  # `Errno::ENOENT` cwd from `Dir.pwd` are tolerated — we deliberately do
  # NOT call `Dir.pwd` as part of the resolution because that's exactly
  # the call that crashes when the cwd has been removed.
  def resolve_runner_root_for_subline(fastfile)
    candidate_path = nil

    if fastfile.respond_to?(:path)
      begin
        candidate_path = fastfile.path
      rescue StandardError
        candidate_path = nil
      end
    end

    if blank?(candidate_path) && fastfile.respond_to?(:instance_variable_get)
      candidate_path = fastfile.instance_variable_get(:@path)
    end

    if blank?(candidate_path) && defined?(FastlaneCore::FastlaneFolder)
      begin
        candidate_path = FastlaneCore::FastlaneFolder.fastfile_path
      rescue StandardError
        candidate_path = nil
      end
    end

    return nil if blank?(candidate_path)

    File.expand_path("..", candidate_path.to_s)
  end

  def app_root_prefixed_option_tokens(options = {}, allowed_keys: nil, path_keys: [])
    return [] unless options.respond_to?(:to_h)

    path_key_set = path_keys.map(&:to_sym).to_set
    fastlane_option_tokens(options, allowed_keys: allowed_keys).map do |token|
      key, value = Shellwords.split(token).first.to_s.split(":", 2)
      next token unless path_key_set.include?(key.to_sym)

      absolute_value = resolve_app_path(value, options)
      Shellwords.escape("#{key}:#{absolute_value}")
    end
  end

  def ios_ipa_path(options = {})
    explicit = option(options, :ipa, :ipa_path)
    return resolve_app_path(explicit.to_s.strip, options) unless blank?(explicit)

    from_env = env_first("IOS_IPA_PATH", "FASTLANE_IPA_PATH")
    return resolve_app_path(from_env.to_s.strip, options) unless blank?(from_env)

    explicit_name = option(options, :ipa_name)
    explicit_name ||= env_first("IOS_IPA_NAME", "FASTLANE_IPA_NAME")

    ipa_dir = resolve_app_path("build/ios/ipa", options)

    # Try the explicit name first if provided.
    unless blank?(explicit_name)
      explicit_path = File.join(ipa_dir, explicit_name.to_s)
      return explicit_path if File.exist?(explicit_path)
    end

    # Flutter names the IPA after the iOS scheme (defaults to Runner; with
    # flavors it's typically the flavor name). Try the common candidates and
    # fall back to whatever .ipa is freshest in the directory.
    flavor = resolve_flavor(options)
    candidates = []
    candidates << File.join(ipa_dir, "Runner.ipa")
    candidates << File.join(ipa_dir, "#{flavor}.ipa") unless blank?(flavor)
    found = candidates.find { |path| File.exist?(path) }
    return found if found

    if Dir.exist?(ipa_dir)
      ipa_files = Dir.glob(File.join(ipa_dir, "*.ipa"))
      newest = ipa_files.max_by { |path| File.mtime(path) }
      return newest if newest
    end

    # Nothing found yet — return the legacy default so callers get a clear
    # "file not found" error pointing at the expected location.
    File.join(ipa_dir, explicit_name.to_s.empty? ? "Runner.ipa" : explicit_name.to_s)
  end

  def absolute_option_or_env(options, option_key:, env_keys:)
    value = option(options, option_key)
    value = env_first(*env_keys) if blank?(value)
    resolve_app_path(value, options)
  end

  def path_option(options, *keys)
    value = option(options, *keys)
    return nil if blank?(value)

    resolve_app_path(value, options)
  end

  def normalize_shell_command(command)
    command.to_s.strip
  end

  def maybe_absolute(path, options = {})
    return nil if blank?(path)

    resolve_app_path(path, options)
  end

  def option_or_env(options, key, env_keys = [])
    value = option(options, key)
    value = env_first(*env_keys) if blank?(value)
    return nil if blank?(value)

    value.to_s.strip
  end

  def absolute_json_key(options = {})
    option_value = option(options, :json_key)
    env_value = env_first("GOOGLE_PLAY_JSON_KEY_PATH")
    value = blank?(option_value) ? env_value : option_value
    resolve_app_path(value, options)
  end

  def absolute_ios_file(options = {}, option_key:, env_keys:, fallback: nil)
    value = option(options, option_key)
    value = env_first(*env_keys) if blank?(value)
    value = fallback if blank?(value)
    resolve_app_path(value, options)
  end

  def absolute_workspace_path(options = {})
    workspace = option(options, :workspace)
    workspace = "ios/Runner.xcworkspace" if blank?(workspace)
    resolve_app_path(workspace, options)
  end

  def absolute_output_directory(options = {})
    output_directory = option(options, :output_directory)
    output_directory = "build/ios" if blank?(output_directory)
    resolve_app_path(output_directory, options)
  end

  def absolute_apk_path(options = {})
    apk_path = option(options, :apk_path)
    apk_path = "build/app/outputs/flutter-apk/app-release.apk" if blank?(apk_path)
    resolve_app_path(apk_path, options)
  end

  def absolute_path_list(values, options = {})
    Array(values).map { |item| resolve_app_path(item, options) }
  end

  def resolved_flutter_command(options = {})
    flutter_command(options)
  end

  # Env vars stripped by `with_clean_subprocess_env` before yielding.
  #
  # The brew `/opt/homebrew/bin/fastlane` wrapper prepends its own Ruby to
  # PATH and pins GEM_HOME / GEM_PATH at the bundled gem cache. Any child
  # process inherits that env — including `flutter build ipa`, which then
  # invokes `pod` under a Ruby that can no longer see its own cocoapods
  # gem ("CocoaPods is installed but broken … different Ruby"). Wrap any
  # sh-out that may transitively spawn `pod` (`flutter build ipa`,
  # `flutter pub get` on iOS-plugin projects) in `with_clean_subprocess_env`
  # so the child sees the user's original Ruby/gem env.
  SUBPROCESS_ENV_KEYS_TO_SCRUB = %w[
    GEM_HOME
    GEM_PATH
    RUBYOPT
    RUBYLIB
    BUNDLE_GEMFILE
    BUNDLE_PATH
    BUNDLE_BIN_PATH
    BUNDLER_VERSION
    BUNDLER_SETUP
  ].freeze

  # Path-segment substrings that the brew fastlane wrapper / its libexec
  # prepend to PATH. Stripped from PATH inside `with_clean_subprocess_env`
  # so the child resolves `ruby` / `pod` from the user's normal PATH.
  SUBPROCESS_PATH_SEGMENTS_TO_STRIP = [
    "/Cellar/fastlane/",
    "/.local/share/fastlane/"
  ].freeze

  # Yield with GEM_HOME/GEM_PATH/etc. stripped and brew fastlane's PATH
  # additions removed, so the child process resolves `ruby` and `pod`
  # against the user's normal environment. Restores ENV on the way out
  # (including on exceptions).
  def with_clean_subprocess_env
    return unless block_given?

    saved = SUBPROCESS_ENV_KEYS_TO_SCRUB.each_with_object({}) do |key, acc|
      acc[key] = ENV.delete(key)
    end

    original_path = ENV["PATH"]
    cleaned_path = clean_path_for_subprocess(original_path)
    ENV["PATH"] = cleaned_path unless cleaned_path.nil?

    yield
  ensure
    saved&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    ENV["PATH"] = original_path unless original_path.nil?
  end

  def clean_path_for_subprocess(path)
    return nil if blank?(path)

    path.split(File::PATH_SEPARATOR).reject do |segment|
      SUBPROCESS_PATH_SEGMENTS_TO_STRIP.any? { |needle| segment.include?(needle) }
    end.join(File::PATH_SEPARATOR)
  end

  def path_or_default(value, default, options = {})
    resolve_app_path(blank?(value) ? default : value, options)
  end

  def app_file_exists?(path, options = {})
    file_path = resolve_app_path(path, options)
    return false if blank?(file_path)

    File.exist?(file_path)
  end

  def ensure_app_file(path, options = {}, label: "file")
    file_path = resolve_app_path(path, options)
    FastlaneCore::UI.user_error!("Missing #{label}: #{file_path}") unless File.exist?(file_path)
    file_path
  end

  def ensure_app_directory(path, options = {}, label: "directory")
    dir_path = resolve_app_path(path, options)
    FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
    dir_path
  end

  def app_root(options = {})
    resolve_app_root(options)
  end

  def app_path(path, options = {})
    resolve_app_path(path, options)
  end

  def absolute_metadata_path(options = {}, platform:)
    case platform
    when :android
      resolve_path_in_fastlane(
        options: options,
        option_key: :metadata_path,
        env_keys: %w[ANDROID_METADATA_PATH FASTLANE_ANDROID_METADATA_PATH],
        default_relative: "android/metadata"
      )
    else
      resolve_path_in_fastlane(
        options: options,
        option_key: :metadata_path,
        env_keys: %w[IOS_METADATA_PATH FASTLANE_IOS_METADATA_PATH],
        default_relative: "ios/metadata"
      )
    end
  end

  LOCALISED_URL_FALLBACK_FILES = %w[support_url.txt marketing_url.txt privacy_url.txt].freeze
  METADATA_NON_LOCALE_DIRS = %w[review_information trade_representative_contact_information].freeze

  # Materialises root-level fallback files into each locale subfolder of an iOS
  # `ios/metadata` directory. Deliver treats files like support_url.txt as
  # *localised* (one per language), but the URLs are usually identical across
  # locales — same idea as the root-level copyright.txt for non-localised values.
  #
  # For each `filename` in `filenames`:
  #   * Read `<metadata_path>/<filename>` (root-level).
  #   * Skip if missing or blank.
  #   * For every locale subfolder, if that locale's file is missing or blank,
  #     write the root value. Locales with their own non-empty value are kept.
  #
  # Returns an array of `[path, original_existed?, original_content_or_nil]`
  # tuples describing what was materialised, so `restore_localised_fallbacks`
  # can put things back after `deliver` runs.
  def materialize_localised_fallbacks(metadata_path:, filenames: LOCALISED_URL_FALLBACK_FILES)
    fallback_map = {}
    filenames.each do |fname|
      root_path = File.join(metadata_path, fname)
      next unless File.file?(root_path)
      content = File.read(root_path).to_s
      next if content.strip.empty?
      fallback_map[fname] = content
    end
    return [] if fallback_map.empty?

    restorable = []
    Dir.children(metadata_path).each do |entry|
      full = File.join(metadata_path, entry)
      next unless File.directory?(full)
      next if METADATA_NON_LOCALE_DIRS.include?(entry)
      next if entry.start_with?(".")

      fallback_map.each do |fname, content|
        target = File.join(full, fname)
        existed = File.file?(target)
        current = existed ? File.read(target) : nil
        # Respect explicit per-locale override.
        next if existed && !current.to_s.strip.empty?
        File.write(target, content)
        restorable << [target, existed, current]
      end
    end
    restorable
  end

  def restore_localised_fallbacks(restorable)
    Array(restorable).each do |target, existed, original|
      if existed
        File.write(target, original.to_s)
      else
        File.delete(target) if File.file?(target)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # App Store Connect submission-related config files
  # ---------------------------------------------------------------------------
  # Each app may keep its own JSON/text overrides under `<fastlane>/ios/`, while
  # fastlane_cli ships sane defaults under `<runner>/ios/defaults/`. These
  # helpers resolve "app-level if present, otherwise CLI default, otherwise nil"
  # so lanes can pass an optional path to deliver / spaceship.

  IOS_CLI_DEFAULTS_RELATIVE = "ios/defaults"
  IOS_APP_RATING_CONFIG_FILENAME = "app_rating_config.json"
  IOS_SUBMISSION_INFO_FILENAME = "submission_information.json"
  IOS_APP_PRIVACY_DETAILS_FILENAME = "app_privacy_details.json"
  IOS_PRICE_TIER_FILENAME = "price_tier.txt"

  def resolve_app_or_default_path(options:, app_relative:, default_relative:)
    app_root = resolve_fastlane_root(options)
    app_path = File.expand_path(app_relative, app_root)
    return app_path if File.file?(app_path)

    runner_root = resolve_runner_fastlane_path(options)
    default_path = File.expand_path(default_relative, runner_root)
    return default_path if File.file?(default_path)

    nil
  end

  def resolve_app_rating_config_path(options = {})
    explicit = path_option(options, :app_rating_config_path)
    return explicit if explicit && File.file?(explicit)

    resolve_app_or_default_path(
      options: options,
      app_relative: "ios/#{IOS_APP_RATING_CONFIG_FILENAME}",
      default_relative: "#{IOS_CLI_DEFAULTS_RELATIVE}/#{IOS_APP_RATING_CONFIG_FILENAME}"
    )
  end

  def resolve_submission_information_path(options = {})
    explicit = path_option(options, :submission_information_path)
    return explicit if explicit && File.file?(explicit)

    resolve_app_or_default_path(
      options: options,
      app_relative: "ios/#{IOS_SUBMISSION_INFO_FILENAME}",
      default_relative: "#{IOS_CLI_DEFAULTS_RELATIVE}/#{IOS_SUBMISSION_INFO_FILENAME}"
    )
  end

  def resolve_app_privacy_details_path(options = {}, must_exist: true)
    explicit = path_option(options, :app_privacy_details_path, :json_path)
    return explicit if explicit && File.file?(explicit)

    resolved = resolve_app_or_default_path(
      options: options,
      app_relative: "ios/#{IOS_APP_PRIVACY_DETAILS_FILENAME}",
      default_relative: "#{IOS_CLI_DEFAULTS_RELATIVE}/#{IOS_APP_PRIVACY_DETAILS_FILENAME}"
    )
    return resolved if resolved

    return nil unless must_exist
    File.expand_path("ios/#{IOS_APP_PRIVACY_DETAILS_FILENAME}", resolve_fastlane_root(options))
  end

  def read_price_tier(options = {}, metadata_path: nil)
    metadata_path ||= absolute_metadata_path(options, platform: :ios)
    candidates = [
      File.join(metadata_path, IOS_PRICE_TIER_FILENAME),
      File.expand_path(
        "#{IOS_CLI_DEFAULTS_RELATIVE}/#{IOS_PRICE_TIER_FILENAME}",
        resolve_runner_fastlane_path(options)
      )
    ]
    file = candidates.find { |c| File.file?(c) }
    return nil if file.nil?
    raw = File.read(file).to_s.strip
    return nil if raw.empty?
    Integer(raw)
  rescue ArgumentError
    FastlaneCore::UI.user_error!("Invalid price_tier '#{raw}' at #{file} — expected an integer") if defined?(FastlaneCore::UI)
    raise
  end

  IOS_REVIEW_INFORMATION_DIR = "review_information"
  # Filenames map to deliver's REVIEW_INFORMATION_VALUES keys
  # (see vendored deliver/lib/deliver/upload_metadata.rb:53). Earlier versions
  # of this Fastfile seeded `contact_*.txt` filenames, which deliver silently
  # ignored because they don't match these keys — that's why no review info
  # was actually being uploaded.
  IOS_REVIEW_INFORMATION_FILES = %w[
    first_name.txt
    last_name.txt
    phone_number.txt
    email_address.txt
    demo_user.txt
    demo_password.txt
    notes.txt
  ].freeze

  # Sprays each missing/empty `review_information/*.txt` file from CLI defaults
  # into the app's metadata path so `deliver` finds a complete set. Mirrors the
  # localised URL fallback pattern: per-file override wins; otherwise the CLI
  # default is used; otherwise the file is left missing (deliver will fail
  # loudly, which is correct).
  def materialize_review_information(options = {}, metadata_path: nil)
    metadata_path ||= absolute_metadata_path(options, platform: :ios)
    defaults_dir = File.expand_path(
      "#{IOS_CLI_DEFAULTS_RELATIVE}/#{IOS_REVIEW_INFORMATION_DIR}",
      resolve_runner_fastlane_path(options)
    )
    return [] unless Dir.exist?(defaults_dir)

    target_dir = File.join(metadata_path, IOS_REVIEW_INFORMATION_DIR)
    FileUtils.mkdir_p(target_dir)

    restorable = []
    IOS_REVIEW_INFORMATION_FILES.each do |fname|
      src = File.join(defaults_dir, fname)
      next unless File.file?(src)

      target = File.join(target_dir, fname)
      existed = File.file?(target)
      current = existed ? File.read(target) : nil
      # Respect explicit per-app override (non-empty).
      next if existed && !current.to_s.strip.empty?

      File.write(target, File.read(src))
      restorable << [target, existed, current]
    end
    restorable
  end

  # Same restore semantics as `restore_localised_fallbacks` — kept as a
  # distinct name so call sites read clearly.
  def restore_review_information(restorable)
    restore_localised_fallbacks(restorable)
  end

  def read_submission_information(options = {})
    path = resolve_submission_information_path(options)
    return [nil, {}] unless path

    require "json"
    data = JSON.parse(File.read(path))
    [path, data.is_a?(Hash) ? data : {}]
  rescue JSON::ParserError => e
    FastlaneCore::UI.user_error!("Invalid submission_information JSON at #{path}: #{e.message}") if defined?(FastlaneCore::UI)
    raise
  end

  def fastlane_option_tokens(options = {}, allowed_keys: nil)
    return [] unless options.respond_to?(:to_h)

    allowed = allowed_keys&.map(&:to_sym)
    options.to_h.each_with_object([]) do |(key, value), list|
      key_sym = key.to_sym
      next if allowed && !allowed.include?(key_sym)
      next if blank?(value)

      list << Shellwords.escape("#{key_sym}:#{value}")
    end
  end

  def shell_join(parts)
    parts.compact.reject { |item| blank?(item) }.join(" ")
  end

  # ---------------------------------------------------------------------------
  # Summary log box
  # ---------------------------------------------------------------------------
  # Renders a multi-line summary inside a coloured Unicode box so the user
  # can spot the structured “human report” inside the noisy fastlane log
  # stream. Intended for end-of-lane summaries (versiyon, build, deploy,
  # download).
  #
  # Usage:
  #   FastlaneCliConfig.print_summary_box("Version data", [
  #     "App: example",
  #     "Flavor: ExampleApp",
  #     "Selected: 1.4.2+57"
  #   ])
  #
  # Honours NO_COLOR env var: colours are stripped automatically.

  SUMMARY_BOX_BORDER_COLOR = "\e[96m" # bright cyan
  SUMMARY_BOX_TITLE_COLOR = "\e[1;95m" # bold magenta
  SUMMARY_BOX_RESET = "\e[0m"
  SUMMARY_BOX_WIDTH = 78

  # Keys whose trailing value should be replaced with `***` before a line is
  # rendered into the summary box. The doc claim in CLAUDE.md §5.3 ("the
  # helper auto-redacts known sensitive keys") relies on this list — keep it
  # in sync if you add a new sensitive identifier elsewhere.
  #
  # Patterns are matched case-insensitively at a word boundary, followed by an
  # optional ANSI colour run, an optional whitespace gap, then `:` or `=`,
  # then the value through end-of-line. Replacement keeps the key + delimiter
  # so the structure stays legible (`api_key: ***`).
  SUMMARY_BOX_SECRET_KEY_PATTERNS = [
    /\bpassword\b/i,
    /\bapi[_-]?key\b/i,
    /\bsecret\b/i,
    /\btoken\b/i,
    /\bprivate[_-]?key\b/i,
    /\bjson[_-]?key[_-]?data\b/i,
    /\bclient[_-]?secret\b/i,
    /\bauthorization\b/i,
    /\bauth\b/i
  ].freeze

  # Joined alternation used by the redaction regex. Built once.
  SUMMARY_BOX_SECRET_KEY_ALTERNATION = Regexp.union(SUMMARY_BOX_SECRET_KEY_PATTERNS).freeze

  # Matches `<key><optional spaces><: or =><value to end>` — the value is the
  # capture group we overwrite with `***`. The key itself is preserved so the
  # rendered line stays human-readable.
  SUMMARY_BOX_REDACTION_REGEX = /(#{SUMMARY_BOX_SECRET_KEY_ALTERNATION}\s*[:=]\s*)\S.*/i

  # Scans a single rendered line for known sensitive keys and replaces the
  # value portion with `***`. Returns the line unchanged if no pattern hits.
  # Safe to call on lines containing ANSI escape sequences — the regex only
  # matches the literal key tokens.
  def redact_secret_value(line)
    return line if line.nil?

    line.to_s.gsub(SUMMARY_BOX_REDACTION_REGEX) do
      "#{Regexp.last_match(1)}***"
    end
  end

  def color_enabled?
    !ENV["NO_COLOR"].to_s.empty? ? false : true
  end

  def colorize(text, code)
    return text.to_s unless color_enabled?

    "#{code}#{text}#{SUMMARY_BOX_RESET}"
  end

  def visible_length(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "").length
  end

  def pad_to_width(text, width)
    visible = visible_length(text)
    return text if visible >= width

    "#{text}#{" " * (width - visible)}"
  end

  def summary_box(title, lines, width: SUMMARY_BOX_WIDTH)
    inner_width = width - 4 # account for "│ " and " │"
    title_text = colorize(" #{title} ", SUMMARY_BOX_TITLE_COLOR)
    title_visible = visible_length(title_text)
    side_fill = [(width - 2 - title_visible) / 2, 0].max

    top = colorize("┌#{"─" * side_fill}#{title_text}#{"─" * (width - 2 - title_visible - side_fill)}┐",
                   SUMMARY_BOX_BORDER_COLOR)
    bottom = colorize("└#{"─" * (width - 2)}┘", SUMMARY_BOX_BORDER_COLOR)
    sep = colorize("├#{"─" * (width - 2)}┤", SUMMARY_BOX_BORDER_COLOR)
    bar = colorize("│", SUMMARY_BOX_BORDER_COLOR)

    body = Array(lines).flat_map do |line|
      if line == :sep
        [sep]
      else
        redacted = redact_secret_value(line.to_s)
        wrap_summary_line(redacted, inner_width).map do |chunk|
          "#{bar} #{pad_to_width(chunk, inner_width)} #{bar}"
        end
      end
    end

    [top, *body, bottom]
  end

  def wrap_summary_line(line, width)
    return [""] if line.empty?

    visible_segments = []
    remaining = line.dup
    until remaining.empty?
      if visible_length(remaining) <= width
        visible_segments << remaining
        break
      end

      cut = nearest_break(remaining, width)
      visible_segments << remaining[0...cut]
      remaining = remaining[cut..].to_s.lstrip
    end
    visible_segments
  end

  def nearest_break(text, width)
    visible = 0
    last_space = nil
    text.each_char.with_index do |char, idx|
      visible += 1
      last_space = idx if char == " " && visible <= width
      return last_space || width if visible >= width
    end
    text.length
  end

  def print_summary_box(title, lines, width: SUMMARY_BOX_WIDTH, sink: :ui)
    summary_box(title, lines, width: width).each do |rendered_line|
      case sink
      when :ui
        if defined?(FastlaneCore::UI)
          FastlaneCore::UI.message(rendered_line)
        else
          puts rendered_line
        end
      when :stderr
        warn(rendered_line)
      else
        puts rendered_line
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Version bump computation (pure)
  # ---------------------------------------------------------------------------
  # The version-bump algorithm is component-wise-max aware across all three
  # version sources (Android Play, iOS App Store, local pubspec). Rather than
  # picking the single highest semver and bumping it — which loses the fact
  # that a *different* source may have reached a higher value on some other
  # component — we take the maximum of each component independently. The
  # resulting version is therefore strictly ahead of EVERY source on EVERY
  # axis: no store can be "ahead" of the new version on a component the
  # chosen base would have ignored.
  #
  # All functions below are PURE — no file/network I/O — so they are fully
  # unit-testable in isolation.

  ACCEPTED_BUMP_LEVELS = %i[patch minor major].freeze

  # Parse a `MAJOR.MINOR.PATCH` (with optional `+BUILD`) string into integer
  # components. Tolerates:
  #   * a missing `+BUILD` suffix (build defaults to 0),
  #   * surrounding whitespace,
  #   * an inline `# comment` trailing the version (the v0.3.2 pubspec regex
  #     fix), e.g. `1.2.3+45  # do not edit`.
  # A `nil`, blank, `"unknown"`, or `"0"` value is treated as `0.0.0+0` so a
  # not-yet-published / unreachable store does not block the computation.
  # Any other malformed input (non-numeric component, missing component)
  # raises an ArgumentError with a clear message.
  #
  # Returns a hash: { major:, minor:, patch:, build: } (all Integers).
  def parse_version_components(raw)
    text = raw.to_s.strip
    # Strip an inline `# comment` (mirrors the v0.3.2 pubspec regex).
    text = text.sub(/\s+#.*\z/, "").strip

    # Unknown / unpublished / unreachable source → contributes zeros.
    return { major: 0, minor: 0, patch: 0, build: 0 } if text.empty? ||
                                                         text.casecmp?("unknown") ||
                                                         text == "0"

    match = text.match(/\A(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\z/)
    unless match
      raise ArgumentError,
            "Invalid version string #{raw.inspect} — expected MAJOR.MINOR.PATCH[+BUILD] with integer components"
    end

    {
      major: match[1].to_i,
      minor: match[2].to_i,
      patch: match[3].to_i,
      build: (match[4] || "0").to_i
    }
  end

  # Normalise a bump level to one of :patch / :minor / :major. Raises an
  # ArgumentError listing the accepted values on anything else.
  def normalize_bump_level(bump)
    level = bump.to_s.strip.downcase
    level = "patch" if level.empty?
    sym = level.to_sym
    unless ACCEPTED_BUMP_LEVELS.include?(sym)
      raise ArgumentError,
            "Invalid bump level #{bump.inspect} — accepted values: patch, minor, major"
    end
    sym
  end

  # Compute the next version using the component-wise-max algorithm.
  #
  #   sources : an Array of source version strings, OR an Array of hashes
  #             shaped { version: "X.Y.Z", build: N } / { version: "X.Y.Z+N" }.
  #             Each source is parsed into components; unknown/0 → 0.0.0+0.
  #   bump    : :patch (default) / :minor / :major (also accepts strings).
  #
  # Algorithm:
  #   1. max_major/minor/patch/build = component-wise max across all sources.
  #   2. patch bump → max_major . max_minor . (max_patch + 1)
  #      minor bump → max_major . (max_minor + 1) . 0
  #      major bump → (max_major + 1) . 0 . 0
  #   3. build_number = max_build + 1 (always, regardless of bump level).
  #
  # Returns { version_name:, build_number:, full:, maxes: }.
  def resolve_bumped_version(sources:, bump: :patch)
    level = normalize_bump_level(bump)

    parsed = Array(sources).map do |source|
      if source.is_a?(Hash)
        version = source[:version] || source["version"]
        build = source[:build] || source["build"]
        components = parse_version_components(version)
        # An explicit `build:` overrides any `+BUILD` parsed from `version`.
        unless build.nil? || build.to_s.strip.empty?
          components = components.merge(build: parse_build_component(build))
        end
        components
      else
        parse_version_components(source)
      end
    end
    parsed = [{ major: 0, minor: 0, patch: 0, build: 0 }] if parsed.empty?

    max_major = parsed.map { |c| c[:major] }.max
    max_minor = parsed.map { |c| c[:minor] }.max
    max_patch = parsed.map { |c| c[:patch] }.max
    max_build = parsed.map { |c| c[:build] }.max

    version_name = case level
                   when :major
                     "#{max_major + 1}.0.0"
                   when :minor
                     "#{max_major}.#{max_minor + 1}.0"
                   else
                     "#{max_major}.#{max_minor}.#{max_patch + 1}"
                   end

    build_number = max_build + 1

    {
      version_name: version_name,
      build_number: build_number,
      full: "#{version_name}+#{build_number}",
      bump: level,
      maxes: {
        major: max_major,
        minor: max_minor,
        patch: max_patch,
        build: max_build
      }
    }
  end

  # Parse a standalone build-number value (the `build:` field of a source
  # hash). Tolerates an inline comment / blank → 0; raises on non-numeric.
  def parse_build_component(raw)
    text = raw.to_s.strip.sub(/\s+#.*\z/, "").strip
    return 0 if text.empty? || text.casecmp?("unknown")

    unless text.match?(/\A\d+\z/)
      raise ArgumentError, "Invalid build number #{raw.inspect} — expected a non-negative integer"
    end

    text.to_i
  end
end
