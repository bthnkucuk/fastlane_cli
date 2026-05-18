#!/usr/bin/env ruby
# frozen_string_literal: true

ENV["FASTLANE_SKIP_UPDATE_CHECK"] = "1"
ENV["FASTLANE_DISABLE_COLORS"] = "1"
ENV["SPACESHIP_AVOID_XCODE_API"] = "1"

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("Gemfile", __dir__)
ENV["BUNDLE_PATH"] ||= File.expand_path("vendor/bundle", __dir__)

tools_root = ENV["STOREPILOT_TOOLS_ROOT"].to_s
unless tools_root.empty?
  ssl_cert_file = File.expand_path(File.join(tools_root, "ruby", "ssl", "cert.pem"))
  ssl_cert_dir = File.expand_path(File.join(tools_root, "ruby", "ssl", "certs"))
  ENV["SSL_CERT_FILE"] ||= ssl_cert_file if File.file?(ssl_cert_file)
  ENV["SSL_CERT_DIR"] ||= ssl_cert_dir if Dir.exist?(ssl_cert_dir)
end

require "bundler/setup"
require "base64"
require "fileutils"
require "fastlane"
require_relative "./common_helpers"
require "googleauth"
require "json"
require "logger"
require "net/http"
require "open3"
require "shellwords"
require "spaceship"
require "stringio"
require "supply"
require "time"
require "tmpdir"
require "uri"

ENV["SPACESHIP_COOKIE_PATH"] ||= Dir.tmpdir

module Spaceship
  class Client
    def logger
      @logger ||= begin
        instance_logger = Logger.new(File::NULL)
        instance_logger.formatter = proc do |severity, datetime, _progname, msg|
          severity = format("%-5.5s", severity)
          "#{severity} [#{datetime.strftime('%H:%M:%S')}]: #{msg}\n"
        end
        instance_logger
      end
    end
  end
end

module StorePilotBridge
  class BridgeError < StandardError; end

  DEFAULT_GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token"
  PLAY_REPORTING_SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting"
  PREFERRED_LOCALES = %w[en-us en-gb tr-tr].freeze

  module_function

  def run(command, payload)
    case command
    when "apple_apps"
      { "apps" => fetch_apple_apps(payload) }
    when "google_apps"
      { "apps" => fetch_google_apps(payload) }
    when "apple_metadata"
      fetch_apple_metadata(payload)
    when "google_metadata"
      fetch_google_metadata(payload)
    when "development_project_inspect"
      inspect_development_project(payload)
    when "development_get_version_data"
      get_development_version_data(payload)
    when "development_update_pubspec_version"
      update_development_pubspec_version(payload)
    when "development_project_build"
      build_development_project(payload)
    else
      raise BridgeError, "Unsupported command: #{command.inspect}"
    end
  end

  def fetch_apple_apps(payload)
    authenticate_apple(extract_map(payload, "credential", allow_missing: true) || payload)

    apps = Spaceship::ConnectAPI::App.all(
      filter: {},
      includes: nil,
      limit: 200,
      sort: "name"
    )

    apps.filter_map do |app|
      store_app_id = app.id.to_s.strip
      bundle_id = app.bundle_id.to_s.strip
      next if store_app_id.empty? || bundle_id.empty?

      public_data = fetch_public_ios_store_data(bundle_id)

      {
        "storeAppId" => store_app_id,
        "packageOrBundleId" => bundle_id,
        "displayName" => first_non_empty([app.name, public_data["trackName"], bundle_id]),
        "iconUrl" => first_non_empty([public_data["iconUrl"]])
      }
    end
  end

  def fetch_apple_metadata(payload)
    credential = extract_map(payload, "credential", allow_missing: true) || payload
    app_payload = extract_map(payload, "app")

    authenticate_apple(credential)

    app_id = required_string(app_payload["storeAppId"], name: "app.storeAppId")
    bundle_id = first_non_empty([app_payload["packageOrBundleId"], app_payload["bundleId"]])

    app = Spaceship::ConnectAPI::App.get(app_id: app_id)
    raise BridgeError, "ASC app bulunamadi: #{app_id}" if app.nil?

    errors = []

    versions = app.get_app_store_versions(
      filter: { platform: Spaceship::ConnectAPI::Platform::IOS },
      includes: nil,
      limit: 200,
      sort: nil
    )

    sorted_versions = Array(versions)
      .sort_by { |item| parse_time(item.created_date) }
      .reverse

    version_labels = []
    version_entries = []

    sorted_versions.each do |version|
      label = version.version_string.to_s.strip
      next if label.empty?

      version_labels << label unless version_labels.include?(label)
      state = first_non_empty([version.app_store_state, version.app_version_state])
      channels = []
      channels << normalize_asc_state_chip(state) unless state.to_s.strip.empty?

      version_entries << {
        "label" => label,
        "channels" => channels,
        "storeState" => (state.to_s.strip.empty? ? nil : state)
      }
    end

    description = nil
    screenshot_urls = []

    latest_version = sorted_versions.first
    if latest_version
      begin
        localizations = latest_version.get_app_store_version_localizations(
          includes: nil,
          limit: 50,
          sort: nil
        )
        selected_localization = select_by_locale(localizations) { |item| item.locale }

        if selected_localization
          description = first_non_empty([selected_localization.description])

          begin
            screenshot_sets = selected_localization.get_app_screenshot_sets(
              includes: "appScreenshots",
              limit: 200,
              sort: nil
            )
            screenshot_urls = Array(screenshot_sets).flat_map do |set|
              Array(set.app_screenshots).filter_map do |screenshot|
                url = screenshot.image_asset_url(type: "jpg").to_s.strip
                url.empty? ? nil : url
              end
            end.uniq
          rescue StandardError => e
            errors << "ASC screenshot alinamadi: #{e.message}"
          end
        end
      rescue StandardError => e
        errors << "ASC localization alinamadi: #{e.message}"
      end
    end

    public_data = bundle_id.to_s.strip.empty? ? {} : fetch_public_ios_store_data(bundle_id)
    public_version = first_non_empty([public_data["version"]])

    if version_labels.empty? && public_version
      version_labels << public_version
      version_entries << {
        "label" => public_version,
        "channels" => ["PROD"],
        "storeState" => "READY_FOR_SALE"
      }
    end

    {
      "description" => first_non_empty([description, public_data["description"]]),
      "screenshotUrls" => screenshot_urls.empty? ? Array(public_data["screenshotUrls"]) : screenshot_urls,
      "versions" => version_labels,
      "versionEntries" => version_entries,
      "iconUrl" => first_non_empty([public_data["iconUrl"], app_payload["iconUrl"]]),
      "errors" => errors
    }
  end

  def fetch_google_apps(payload)
    credential = extract_map(payload, "credential", allow_missing: true) || payload
    access_token = fetch_google_access_token(credential, scope: PLAY_REPORTING_SCOPE)

    apps = []
    next_page_token = nil

    loop do
      response = google_reporting_apps_search(
        access_token: access_token,
        page_token: next_page_token
      )

      Array(response["apps"]).each do |item|
        package_name = item["packageName"].to_s.strip
        next if package_name.empty?

        display_name = first_non_empty([item["displayName"], package_name])

        apps << {
          "storeAppId" => first_non_empty([item["name"], package_name]),
          "packageOrBundleId" => package_name,
          "displayName" => display_name,
          "iconUrl" => fetch_google_play_icon(package_name)
        }
      end

      next_page_token = response["nextPageToken"].to_s.strip
      break if next_page_token.empty?
    end

    apps.sort_by { |item| item["displayName"].to_s.downcase }
  end

  def fetch_google_metadata(payload)
    credential = extract_map(payload, "credential", allow_missing: true) || payload
    app_payload = extract_map(payload, "app")
    package_name = required_string(
      first_non_empty([app_payload["packageOrBundleId"], app_payload["packageName"]]),
      name: "app.packageOrBundleId"
    )

    client = supply_client_for(credential, package_name: package_name)
    errors = []

    description = nil
    screenshot_urls = []
    versions = []
    version_entries = []
    icon_url = nil

    begin
      client.begin_edit(package_name: package_name)

      listings = client.listings
      selected_listing = select_by_locale(listings) { |item| item.language }
      locale = selected_listing&.language.to_s.strip

      description = first_non_empty([
        selected_listing&.full_description,
        selected_listing&.short_description
      ])

      unless locale.empty?
        icon_url = Array(client.fetch_images(image_type: "icon", language: locale))
          .filter_map { |image| first_non_empty([image.url]) }
          .first

        screenshot_urls = Array(client.fetch_images(image_type: "phoneScreenshots", language: locale))
          .filter_map { |image| first_non_empty([image.url]) }
          .uniq
      end

      Array(client.tracks).each do |track|
        track_name = track.track.to_s.strip

        Array(track.releases).each do |release|
          release_name = release.name.to_s.strip
          version_codes = Array(release.version_codes)
            .map { |item| item.to_s.strip }
            .reject(&:empty?)
          status = release.status.to_s.strip

          label = first_non_empty([
            release_name,
            (version_codes.empty? ? nil : "Version code: #{version_codes.join(', ')}")
          ])

          next if label.nil? || label.empty?

          versions << label unless versions.include?(label)

          channels = []
          channels << normalize_google_track_chip(track_name) unless track_name.empty?
          channels << normalize_google_release_status_chip(status) unless status.empty?

          version_entries << {
            "label" => label,
            "channels" => channels.uniq,
            "storeState" => (status.empty? ? nil : status)
          }
        end
      end
    rescue StandardError => e
      errors << "Google Play metadata alinamadi: #{e.message}"
    ensure
      begin
        client.abort_current_edit if client.respond_to?(:current_edit) && client.current_edit
      rescue StandardError
        # ignore cleanup failures
      end
    end

    icon_url ||= fetch_google_play_icon(package_name)

    {
      "description" => description,
      "screenshotUrls" => screenshot_urls,
      "versions" => versions,
      "versionEntries" => version_entries,
      "iconUrl" => first_non_empty([icon_url, app_payload["iconUrl"]]),
      "errors" => errors
    }
  end

  def inspect_development_project(payload)
    project_path = required_string(payload["projectPath"], name: "projectPath")
    expanded_path = File.expand_path(project_path)
    raise BridgeError, "Klasor bulunamadi: #{expanded_path}" unless Dir.exist?(expanded_path)

    profile = detect_development_project(expanded_path)
    version = read_local_version(profile)
    available_flavors = detect_project_flavors(profile)
    resolved_flutter_command = resolve_flutter_command(
      expanded_path,
      preferred_command: payload["flutterCommand"],
      allow_missing: true
    )

    {
      "projectPath" => expanded_path,
      "projectType" => profile[:project_type],
      "versionName" => version[:version_name],
      "buildNumber" => version[:build_number],
      "displayVersion" => version[:display_version],
      "resolvedFlutterCommand" => resolved_flutter_command,
      "availableFlavors" => available_flavors
    }
  end

  def get_development_version_data(payload)
    project_path = required_string(payload["projectPath"], name: "projectPath")
    expanded_path = File.expand_path(project_path)
    raise BridgeError, "Klasor bulunamadi: #{expanded_path}" unless Dir.exist?(expanded_path)

    profile = detect_development_project(expanded_path)
    available_flavors = detect_project_flavors(profile)
    resolved_flutter_command = resolve_flutter_command(
      expanded_path,
      preferred_command: payload["flutterCommand"],
      allow_missing: true
    )
    requested_flavor = payload["flavor"].to_s.strip
    requested_flavor = nil if requested_flavor.empty?

    report = collect_version_report(profile, expanded_path)
    report["resolvedFlutterCommand"] = resolved_flutter_command
    report["availableFlavors"] = available_flavors
    report["flavor"] = requested_flavor
    report["summary"] = format_version_summary(report)
    report
  end

  def update_development_pubspec_version(payload)
    before = get_development_version_data(payload)

    if before["projectType"] != "flutter"
      raise BridgeError, "update_pubspec_version sadece Flutter projede kullanilir."
    end

    pubspec_before = before["pubspec"] || {}
    bump_result = bump_flutter_pubspec_build_number(before["projectPath"])

    after = get_development_version_data(payload)

    change = {
      "field" => "buildNumber",
      "rule" => "buildNumber = (mevcut buildNumber || 0) + 1; versionName degismez.",
      "from" => pubspec_before["buildNumber"],
      "to" => bump_result[:build_number],
      "displayFrom" => pubspec_before["displayVersion"],
      "displayTo" => bump_result[:display_version],
      "fileUpdated" => pubspec_before["path"],
      "writeStrategy" => "pubspec.yaml icindeki 'version: X.Y.Z+N' satiri 'version: X.Y.Z+(N+1)' olarak yazildi."
    }

    after["previous"] = before
    after["change"] = change
    after["summary"] = format_update_summary(before, after, change)

    warn(after["summary"])
    after
  end

  def build_development_project(payload)
    project_path = required_string(payload["projectPath"], name: "projectPath")
    platform = required_string(payload["platform"], name: "platform").downcase
    increment_version = bool_value(payload["incrementVersion"], default: false)
    flavor = payload["flavor"].to_s.strip
    expanded_path = File.expand_path(project_path)
    raise BridgeError, "Klasor bulunamadi: #{expanded_path}" unless Dir.exist?(expanded_path)

    unless %w[ios android].include?(platform)
      raise BridgeError, "platform ios veya android olmali"
    end

    profile = detect_development_project(expanded_path)
    artifact_path = nil
    version_data = read_local_version(profile)
    resolved_flutter_command = nil

    case profile[:project_type]
    when "flutter"
      resolved_flutter_command = resolve_flutter_command(
        expanded_path,
        preferred_command: payload["flutterCommand"]
      )
      if increment_version
        version_data = bump_flutter_pubspec_build_number(expanded_path)
      end
      run_shell_command!("#{resolved_flutter_command} pub get", chdir: expanded_path)

      if platform == "android"
        flavor_option = flavor.empty? ? "" : " --flavor #{Shellwords.escape(flavor)}"
        run_shell_command!(
          "#{resolved_flutter_command} build appbundle --release#{flavor_option}",
          chdir: expanded_path
        )
        artifact_path = latest_aab_artifact(expanded_path)
      else
        flavor_option = flavor.empty? ? "" : " --flavor #{Shellwords.escape(flavor)}"
        run_shell_command!(
          "#{resolved_flutter_command} build ipa --release --no-codesign#{flavor_option}",
          chdir: expanded_path
        )
        ios_ipa_dir = File.expand_path(File.join(expanded_path, "build", "ios", "ipa"))
        ipa_file = Dir.glob(File.join(ios_ipa_dir, "*.ipa")).sort.last
        artifact_path = first_non_empty([ipa_file, ios_ipa_dir])
      end
    when "android_only"
      raise BridgeError, "Bu proje yalnizca Android destekliyor." if platform != "android"

      gradle_root = profile[:android_root]
      gradlew_path = File.join(gradle_root, "gradlew")
      unless File.exist?(gradlew_path)
        raise BridgeError, "gradlew bulunamadi: #{gradlew_path}"
      end

      FileUtils.chmod("+x", gradlew_path)
      task_name = flavor.empty? ? "bundleRelease" : "bundle#{gradle_flavor_task_fragment(flavor)}Release"
      run_command!([gradlew_path, task_name], chdir: gradle_root)
      artifact_path = latest_aab_artifact(gradle_root)
    when "ios_only"
      raise BridgeError, "Bu proje yalnizca iOS destekliyor." if platform != "ios"

      raise BridgeError,
            "Native iOS build henuz otomatiklestirilmedi. Flutter proje veya lane bazli iOS build kullan."
    else
      raise BridgeError,
            "Proje tipi desteklenmiyor. Flutter, iOS-only veya Android-only klasor secmelisin."
    end

    {
      "platform" => platform,
      "message" => "Yeni build tamamlandi.",
      "artifactPath" => artifact_path,
      "versionName" => version_data[:version_name],
      "buildNumber" => version_data[:build_number],
      "resolvedFlutterCommand" => resolved_flutter_command,
      "flavor" => (flavor.empty? ? nil : flavor)
    }
  end

  def detect_development_project(root_path)
    resolved_root_path = File.expand_path(root_path)
    resolved_root_path = File.dirname(resolved_root_path) if safe_file?(resolved_root_path)

    best_profile = nil
    best_score = -1

    development_root_candidates(resolved_root_path).each do |candidate|
      profile = detect_development_project_at(candidate)
      score = project_type_priority(profile[:project_type])
      if score > best_score
        best_profile = profile
        best_score = score
      end
      break if best_score >= 3
    end

    best_profile || detect_development_project_at(resolved_root_path)
  end

  def detect_development_project_at(root_path)
    flutter_pubspec_path = File.join(root_path, "pubspec.yaml")
    is_flutter = flutter_project?(flutter_pubspec_path)

    ios_root = resolve_ios_root(root_path)
    android_root = resolve_android_root(root_path)

    project_type = if is_flutter
                     "flutter"
                   elsif !ios_root.nil? && android_root.nil?
                     "ios_only"
                   elsif ios_root.nil? && !android_root.nil?
                     "android_only"
                   else
                     "unknown"
                   end

    {
      root_path: root_path,
      project_type: project_type,
      flutter_pubspec_path: flutter_pubspec_path,
      ios_root: ios_root,
      android_root: android_root
    }
  end

  def development_root_candidates(root_path, max_levels: 5)
    candidates = []
    current = File.expand_path(root_path)

    (max_levels + 1).times do
      break if current.to_s.strip.empty?

      candidates << current unless candidates.include?(current)
      parent = File.dirname(current)
      break if parent == current

      current = parent
    end

    candidates
  end

  def project_type_priority(project_type)
    case project_type.to_s
    when "flutter"
      3
    when "ios_only", "android_only"
      2
    else
      0
    end
  end

  def flutter_project?(pubspec_path)
    return false unless File.file?(pubspec_path)

    content = File.read(pubspec_path)
    content.match?(/^\s*flutter\s*:/)
  rescue StandardError
    false
  end

  def resolve_ios_root(root_path)
    candidates = [
      root_path,
      File.join(root_path, "ios")
    ]

    candidates.find do |candidate|
      next false unless safe_dir_exist?(candidate)

      safe_glob(File.join(candidate, "*.xcodeproj")).any? ||
        safe_file?(File.join(candidate, "Runner", "Info.plist")) ||
        safe_file?(File.join(candidate, "Info.plist"))
    end
  end

  def resolve_android_root(root_path)
    candidates = [
      root_path,
      File.join(root_path, "android")
    ]

    candidates.find do |candidate|
      next false unless safe_dir_exist?(candidate)

      safe_file?(File.join(candidate, "app", "build.gradle")) ||
        safe_file?(File.join(candidate, "app", "build.gradle.kts"))
    end
  end

  def detect_project_flavors(profile)
    ios_flavors = detect_ios_flavors(profile[:ios_root])
    android_flavors = detect_android_flavors(profile[:android_root])
    (ios_flavors + android_flavors)
      .map { |value| value.to_s.strip }
      .reject(&:empty?)
      .uniq
      .sort
  end

  def detect_ios_flavors(ios_root)
    return [] if ios_root.nil? || !safe_dir_exist?(ios_root)

    patterns = [
      File.join(ios_root, "*.xcodeproj", "xcshareddata", "xcschemes", "*.xcscheme"),
      File.join(ios_root, "*.xcworkspace", "xcshareddata", "xcschemes", "*.xcscheme")
    ]

    schemes = patterns.flat_map { |pattern| safe_glob(pattern) }.map do |path|
      File.basename(path, ".xcscheme")
    end

    schemes.reject { |scheme| scheme.to_s.strip.empty? || scheme == "Runner" }.uniq.sort
  rescue StandardError
    []
  end

  def detect_android_flavors(android_root)
    return [] if android_root.nil? || !safe_dir_exist?(android_root)

    gradle_file = first_existing_file(
      File.join(android_root, "app", "build.gradle"),
      File.join(android_root, "app", "build.gradle.kts")
    )
    return [] if gradle_file.nil? || !safe_file?(gradle_file)

    content = File.read(gradle_file)
    block = extract_named_block(content, "productFlavors")
    return [] if block.to_s.strip.empty?

    block.scan(/^\s*([A-Za-z0-9_]+)\s*\{/).flatten.uniq.sort
  rescue StandardError
    []
  end

  def extract_named_block(content, block_name)
    anchor = content.index(/\b#{Regexp.escape(block_name)}\s*\{/)
    return nil if anchor.nil?

    brace_start = content.index("{", anchor)
    return nil if brace_start.nil?

    depth = 0
    index = brace_start
    while index < content.length
      character = content[index]
      depth += 1 if character == "{"
      depth -= 1 if character == "}"
      if depth.zero?
        return content[(brace_start + 1)...index]
      end
      index += 1
    end

    nil
  rescue StandardError
    nil
  end

  def safe_dir_exist?(path)
    Dir.exist?(path)
  rescue Errno::EPERM, Errno::EACCES
    false
  end

  def safe_file?(path)
    File.file?(path)
  rescue Errno::EPERM, Errno::EACCES
    false
  end

  def safe_glob(pattern)
    Dir.glob(pattern)
  rescue Errno::EPERM, Errno::EACCES
    []
  end

  def gradle_flavor_task_fragment(flavor)
    flavor
      .to_s
      .split(/[^A-Za-z0-9]+/)
      .reject(&:empty?)
      .map { |part| part[0].upcase + part[1..].to_s }
      .join
  end

  def latest_aab_artifact(root_path)
    candidates = safe_glob(File.join(root_path, "**", "*.aab"))
    return nil if candidates.empty?

    candidates.max_by do |path|
      File.mtime(path)
    rescue StandardError
      Time.at(0)
    end
  rescue StandardError
    nil
  end

  def read_local_version(profile)
    case profile[:project_type]
    when "flutter"
      read_flutter_pubspec_version(profile[:flutter_pubspec_path])
    when "android_only"
      read_android_gradle_version(profile[:android_root])
    when "ios_only"
      read_ios_plist_version(profile[:ios_root])
    else
      {
        version_name: nil,
        build_number: nil,
        display_version: nil
      }
    end
  end

  def collect_version_report(profile, expanded_path)
    pubspec_path = profile[:flutter_pubspec_path]
    pubspec_exists = !pubspec_path.nil? && File.file?(pubspec_path)
    pubspec_report = nil
    if pubspec_exists
      pubspec_data = read_flutter_pubspec_version(pubspec_path)
      pubspec_report = build_source_report("pubspec.yaml", pubspec_path, pubspec_data)
    end

    ios_root = profile[:ios_root]
    ios_report = nil
    unless ios_root.nil?
      ios_path = first_existing_file(
        File.join(ios_root, "Runner", "Info.plist"),
        File.join(ios_root, "Info.plist")
      )
      ios_data = read_ios_plist_version(ios_root)
      ios_report = build_source_report("iOS Info.plist", ios_path, ios_data)
    end

    android_root = profile[:android_root]
    android_report = nil
    unless android_root.nil?
      android_path = first_existing_file(
        File.join(android_root, "app", "build.gradle"),
        File.join(android_root, "app", "build.gradle.kts")
      )
      android_data = read_android_gradle_version(android_root)
      android_report = build_source_report("Android build.gradle", android_path, android_data)
    end

    primary_data = read_local_version(profile)
    primary_source = case profile[:project_type]
                     when "flutter" then "pubspec"
                     when "ios_only" then "ios"
                     when "android_only" then "android"
                     end

    {
      "appName" => read_pubspec_app_name(pubspec_path),
      "projectPath" => expanded_path,
      "projectType" => profile[:project_type],
      "primarySource" => primary_source,
      "versionName" => primary_data[:version_name],
      "buildNumber" => primary_data[:build_number],
      "displayVersion" => primary_data[:display_version],
      "pubspec" => pubspec_report,
      "ios" => ios_report,
      "android" => android_report
    }
  end

  def build_source_report(label, source_path, version_data)
    found = !version_data[:version_name].to_s.strip.empty? ||
            !version_data[:build_number].to_s.strip.empty?
    {
      "label" => label,
      "path" => source_path,
      "exists" => !source_path.nil? && File.file?(source_path.to_s),
      "found" => found,
      "versionName" => version_data[:version_name],
      "buildNumber" => version_data[:build_number],
      "displayVersion" => version_data[:display_version]
    }
  end

  def read_pubspec_app_name(pubspec_path)
    return nil if pubspec_path.nil? || !File.file?(pubspec_path)

    content = File.read(pubspec_path)
    match = content.match(/^\s*name:\s*([^\s#]+)\s*$/)
    match.nil? ? nil : match[1].to_s.strip
  rescue StandardError
    nil
  end

  def format_version_summary(report)
    app_label = report["appName"].to_s.strip
    app_label = "(isimsiz)" if app_label.empty?

    primary_label = case report["primarySource"]
                    when "pubspec" then "pubspec.yaml"
                    when "ios" then "iOS Info.plist"
                    when "android" then "Android build.gradle"
                    else "bilinmiyor"
                    end

    lines = []
    lines << "App     : #{app_label}  [#{report['projectType']}]"
    lines << "Path    : #{report['projectPath']}"
    if (flavor = report["flavor"]) && !flavor.to_s.strip.empty?
      lines << "Flavor  : #{flavor}"
    end
    lines << "Aktif   : #{primary_label}  →  #{report['displayVersion'] || '-'}"
    lines << :sep
    %w[pubspec ios android].each do |key|
      src = report[key]
      next if src.nil?

      status = src["found"] ? "OK" : "BULUNAMADI"
      lines << "#{src['label']} [#{status}]"
      lines << "  versionName=#{src['versionName'] || '-'}  buildNumber=#{src['buildNumber'] || '-'}  display=#{src['displayVersion'] || '-'}"
      lines << "  path: #{src['path'] || '-'}"
    end
    if (flavors = report["availableFlavors"]) && !flavors.empty?
      lines << :sep
      lines << "Flavor’lar       : #{flavors.join(', ')}"
    end
    if (cmd = report["resolvedFlutterCommand"])
      lines << "Flutter komutu   : #{cmd}"
    end

    FastlaneCliConfig.summary_box("Version data", lines).join("\n")
  end

  def format_update_summary(before, after, change)
    head = []
    head << "Dosya     : #{change['fileUpdated'] || '-'}"
    head << "Önceki    : #{change['displayFrom'] || '-'}"
    head << "Yeni      : #{change['displayTo'] || '-'}"
    head << "Alan      : #{change['field']} (#{change['from'] || '-'} → #{change['to'] || '-'})"
    head << "Kural     : #{change['rule']}"
    head << "Yazım     : #{change['writeStrategy']}"

    [
      FastlaneCliConfig.summary_box("Pubspec versiyon güncellendi", head).join("\n"),
      "",
      "-- ÖNCE --",
      before["summary"],
      "",
      "-- SONRA --",
      after["summary"]
    ].join("\n")
  end

  def read_flutter_pubspec_version(pubspec_path)
    return empty_version_data unless File.file?(pubspec_path)

    content = File.read(pubspec_path)
    match = content.match(/^\s*version:\s*([^\s#]+)\s*$/)
    return empty_version_data if match.nil?

    parse_combined_version(match[1].to_s.strip)
  rescue StandardError
    empty_version_data
  end

  def bump_flutter_pubspec_build_number(root_path)
    pubspec_path = File.join(root_path, "pubspec.yaml")
    raise BridgeError, "pubspec.yaml bulunamadi: #{pubspec_path}" unless File.file?(pubspec_path)

    content = File.read(pubspec_path)
    match = content.match(/^\s*version:\s*([^\s#]+)\s*$/)
    raise BridgeError, "pubspec.yaml icinde version satiri bulunamadi." if match.nil?

    parsed = parse_combined_version(match[1].to_s.strip)
    version_name = parsed[:version_name]
    build_number = parsed[:build_number]
    raise BridgeError, "Flutter version name bulunamadi." if version_name.to_s.strip.empty?

    next_build_number = build_number.to_i <= 0 ? 1 : build_number.to_i + 1
    next_combined = "#{version_name}+#{next_build_number}"
    updated_content = content.sub(
      /^\s*version:\s*[^\s#]+\s*$/,
      "version: #{next_combined}"
    )

    File.write(pubspec_path, updated_content)

    {
      version_name: version_name,
      build_number: next_build_number.to_s,
      display_version: next_combined
    }
  rescue StandardError => e
    raise BridgeError, "Flutter version guncellenemedi: #{e.message}"
  end

  def read_android_gradle_version(android_root)
    return empty_version_data if android_root.nil?

    gradle_file = first_existing_file(
      File.join(android_root, "app", "build.gradle"),
      File.join(android_root, "app", "build.gradle.kts")
    )
    return empty_version_data if gradle_file.nil?

    content = File.read(gradle_file)
    version_name = first_non_empty(
      [
        content[/versionName\s+["']([^"']+)["']/, 1],
        content[/versionName\s*=\s*["']([^"']+)["']/, 1]
      ]
    )
    build_number = first_non_empty(
      [
        content[/versionCode\s+(\d+)/, 1],
        content[/versionCode\s*=\s*(\d+)/, 1]
      ]
    )

    display = if !version_name.to_s.strip.empty? && !build_number.to_s.strip.empty?
                "#{version_name}+#{build_number}"
              else
                first_non_empty([version_name, build_number])
              end

    {
      version_name: version_name,
      build_number: build_number,
      display_version: display
    }
  rescue StandardError
    empty_version_data
  end

  def read_ios_plist_version(ios_root)
    return empty_version_data if ios_root.nil?

    plist_path = first_existing_file(
      File.join(ios_root, "Runner", "Info.plist"),
      File.join(ios_root, "Info.plist")
    )
    return empty_version_data if plist_path.nil?

    version_name = read_plist_value(plist_path, "CFBundleShortVersionString")
    build_number = read_plist_value(plist_path, "CFBundleVersion")
    display = if !version_name.to_s.strip.empty? && !build_number.to_s.strip.empty?
                "#{version_name}+#{build_number}"
              else
                first_non_empty([version_name, build_number])
              end

    {
      version_name: version_name,
      build_number: build_number,
      display_version: display
    }
  rescue StandardError
    empty_version_data
  end

  def read_plist_value(plist_path, key)
    _stdout, stderr, status = Open3.capture3(
      "/usr/libexec/PlistBuddy",
      "-c",
      "Print :#{key}",
      plist_path
    )
    return nil unless status.success?

    value = _stdout.to_s.strip
    return nil if value.empty? || value.start_with?("$(")

    value
  rescue StandardError
    error_message = stderr.to_s.strip
    raise BridgeError, "Info.plist okunamadi (#{key}): #{error_message}" unless error_message.empty?

    nil
  end

  def resolve_flutter_command(root_path, preferred_command: nil, allow_missing: false)
    command = preferred_command.to_s.strip
    return command unless command.empty?

    env_fallback = ENV["FLUTTER_BIN"].to_s.strip
    return env_fallback unless env_fallback.empty?

    local_flutter = File.join(root_path, ".fvm", "flutter_sdk", "bin", "flutter")
    return Shellwords.escape(local_flutter) if File.executable?(local_flutter)

    return "fvm flutter" if executable_on_path?("fvm")
    return "flutter" if executable_on_path?("flutter")
    return nil if allow_missing

    raise BridgeError,
          "Flutter komutu bulunamadi. Build ekranindan 'flutter command' alani doldur."
  end

  def executable_on_path?(binary_name)
    path_env = ENV.fetch("PATH", "")
    path_env.split(File::PATH_SEPARATOR).any? do |directory|
      candidate = File.join(directory, binary_name)
      File.executable?(candidate) && !File.directory?(candidate)
    end
  rescue StandardError
    false
  end

  def bool_value(raw, default:)
    return default if raw.nil?

    case raw
    when true, false
      raw
    else
      normalized = raw.to_s.strip.downcase
      return true if %w[1 true yes y on].include?(normalized)
      return false if %w[0 false no n off].include?(normalized)
      default
    end
  end

  def parse_combined_version(raw)
    text = raw.to_s.strip
    return empty_version_data if text.empty?

    name_part, build_part = text.split("+", 2)
    name = name_part.to_s.strip
    build = build_part.to_s.strip

    {
      version_name: (name.empty? ? nil : name),
      build_number: (build.empty? ? nil : build),
      display_version: text
    }
  end

  def empty_version_data
    {
      version_name: nil,
      build_number: nil,
      display_version: nil
    }
  end

  def run_command!(command_parts, chdir:)
    stdout, stderr, status = Open3.capture3(*command_parts, chdir: chdir)
    return stdout if status.success?

    command_label = command_parts.join(" ")
    raise BridgeError,
          "Komut basarisiz: #{command_label}\n#{truncate(stderr, max: 1200)}"
  rescue StandardError => e
    raise BridgeError, e.message if e.is_a?(BridgeError)

    raise BridgeError, "Komut calistirilamadi: #{command_parts.join(' ')} (#{e.message})"
  end

  def run_shell_command!(command, chdir:)
    stdout, stderr, status = Open3.capture3("/bin/zsh", "-lc", command, chdir: chdir)
    return stdout if status.success?

    raise BridgeError,
          "Komut basarisiz: #{command}\n#{truncate(stderr, max: 1200)}"
  rescue StandardError => e
    raise BridgeError, e.message if e.is_a?(BridgeError)

    raise BridgeError, "Komut calistirilamadi: #{command} (#{e.message})"
  end

  def first_existing_file(*candidates)
    candidates.each do |candidate|
      return candidate if File.file?(candidate)
    end
    nil
  end

  def authenticate_apple(credential)
    key_id = required_string(credential["keyId"], name: "credential.keyId")
    issuer_id = required_string(credential["issuerId"], name: "credential.issuerId")
    private_key = required_string(
      credential["privateKeyPem"],
      name: "credential.privateKeyPem"
    )

    token = Spaceship::ConnectAPI::Token.create(
      key_id: key_id,
      issuer_id: issuer_id,
      key: private_key,
      duration: 20 * 60
    )

    Spaceship::ConnectAPI.token = token
  end

  def supply_client_for(credential, package_name:)
    json_payload = google_service_account_payload(credential)
    Supply::Client.make_from_config(
      params: {
        json_key_data: JSON.generate(json_payload),
        package_name: package_name,
        timeout: 120
      }
    )
  end

  def google_reporting_apps_search(access_token:, page_token:)
    uri = URI("https://playdeveloperreporting.googleapis.com/v1beta1/apps:search")
    params = { "pageSize" => "200" }
    params["pageToken"] = page_token unless page_token.to_s.strip.empty?
    uri.query = URI.encode_www_form(params)

    body = http_get(
      uri,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Accept" => "application/json"
      }
    )

    JSON.parse(body)
  rescue JSON::ParserError => e
    raise BridgeError, "Google apps search yaniti parse edilemedi: #{e.message}"
  end

  def fetch_google_access_token(credential, scope:)
    creds = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(JSON.generate(google_service_account_payload(credential))),
      scope: scope
    )
    token_hash = creds.fetch_access_token!
    token = token_hash["access_token"].to_s.strip
    raise BridgeError, "Google access_token alinmadi" if token.empty?

    token
  rescue Signet::AuthorizationError => e
    raise BridgeError, "Google yetkilendirme hatasi: #{e.message}"
  end

  def google_service_account_payload(credential)
    client_email = required_string(
      credential["clientEmail"] || credential["client_email"],
      name: "credential.clientEmail"
    )
    private_key = required_string(
      credential["privateKeyPem"] || credential["private_key"],
      name: "credential.privateKeyPem"
    )
    token_uri = normalize_google_token_uri(
      credential["tokenUri"] || credential["token_uri"]
    )

    {
      "type" => "service_account",
      "project_id" => first_non_empty([credential["projectId"], credential["project_id"]]),
      "client_email" => client_email,
      "private_key" => private_key,
      "token_uri" => token_uri
    }.compact
  end

  def normalize_google_token_uri(raw_token_uri)
    candidate = raw_token_uri.to_s.strip
    return DEFAULT_GOOGLE_TOKEN_URI if candidate.empty?

    parsed = URI.parse(candidate)
    return DEFAULT_GOOGLE_TOKEN_URI unless parsed.is_a?(URI::HTTPS)

    host = parsed.host.to_s.downcase
    allowed = %w[oauth2.googleapis.com www.googleapis.com]
    return DEFAULT_GOOGLE_TOKEN_URI unless allowed.include?(host)

    parsed.to_s
  rescue URI::InvalidURIError
    DEFAULT_GOOGLE_TOKEN_URI
  end

  def fetch_public_ios_store_data(bundle_id)
    return {} if bundle_id.to_s.strip.empty?

    uri = URI("https://itunes.apple.com/lookup")
    uri.query = URI.encode_www_form(
      "bundleId" => bundle_id,
      "country" => "us"
    )

    body = http_get(uri, headers: { "Accept" => "application/json" })
    parsed = JSON.parse(body)
    first = Array(parsed["results"]).first
    return {} unless first.is_a?(Hash)

    {
      "trackName" => first_non_empty([first["trackName"], first["trackCensoredName"]]),
      "iconUrl" => first_non_empty([first["artworkUrl512"], first["artworkUrl100"]]),
      "description" => first_non_empty([first["description"]]),
      "screenshotUrls" => Array(first["screenshotUrls"])
        .filter_map { |item| first_non_empty([item]) }
        .uniq,
      "version" => first_non_empty([first["version"]])
    }
  rescue StandardError
    {}
  end

  def fetch_google_play_icon(package_name)
    return nil if package_name.to_s.strip.empty?

    uri = URI("https://play.google.com/store/apps/details")
    uri.query = URI.encode_www_form(
      "id" => package_name,
      "hl" => "en",
      "gl" => "US"
    )

    body = http_get(
      uri,
      headers: {
        "Accept" => "text/html",
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
      }
    )

    match = body.match(/<meta\s+property=["']og:image["']\s+content=["']([^"']+)["']/i)
    icon_url = match&.captures&.first.to_s.strip
    return nil if icon_url.empty?

    icon_url.gsub("&amp;", "&")
  rescue StandardError
    nil
  end

  def http_get(uri, headers: {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 30
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    headers.each do |key, value|
      request[key] = value
    end

    response = http.request(request)
    code = response.code.to_i
    body = response.body.to_s

    return body if code >= 200 && code < 300

    raise BridgeError, "HTTP #{code} (#{uri.host}) - #{truncate(body)}"
  end

  def select_by_locale(collection)
    array = Array(collection)
    return nil if array.empty?

    normalized = array.map do |item|
      locale = yield(item).to_s.strip.downcase.tr("_", "-")
      [item, locale]
    end

    PREFERRED_LOCALES.each do |preferred|
      match = normalized.find { |(_, locale)| locale == preferred }
      return match.first if match
    end

    array.first
  end

  def parse_time(raw)
    Time.parse(raw.to_s)
  rescue ArgumentError, TypeError
    Time.at(0)
  end

  def normalize_asc_state_chip(raw_state)
    case raw_state.to_s.upcase
    when "READY_FOR_SALE"
      "PROD"
    when "PENDING_DEVELOPER_RELEASE"
      "READY"
    when "WAITING_FOR_REVIEW", "IN_REVIEW"
      "REVIEW"
    when "PREPARE_FOR_SUBMISSION", "DEVELOPER_REMOVED_FROM_SALE"
      "DRAFT"
    when "REJECTED", "METADATA_REJECTED"
      "REJECTED"
    else
      raw_state.to_s.gsub("_", " ").strip
    end
  end

  def normalize_google_track_chip(raw_track)
    case raw_track.to_s.downcase
    when "production"
      "PROD"
    when "internal"
      "INTERNAL"
    when "alpha"
      "ALPHA"
    when "beta"
      "BETA"
    else
      raw_track.to_s.upcase
    end
  end

  def normalize_google_release_status_chip(raw_status)
    case raw_status.to_s.downcase
    when "completed"
      "LIVE"
    when "draft"
      "DRAFT"
    when "inprogress", "in_progress"
      "ROLLOUT"
    when "halted"
      "HALTED"
    else
      raw_status.to_s.upcase
    end
  end

  def extract_map(payload, key, allow_missing: false)
    value = payload[key]
    return {} if value.nil? && allow_missing

    unless value.is_a?(Hash)
      raise BridgeError, "#{key} map formatinda olmali"
    end

    value
  end

  def required_string(raw, name:)
    value = raw.to_s.strip
    raise BridgeError, "#{name} gerekli" if value.empty?

    value
  end

  def first_non_empty(values)
    Array(values).each do |value|
      next if value.nil?

      text = value.to_s.strip
      return text unless text.empty?
    end
    nil
  end

  def truncate(text, max: 300)
    value = text.to_s.gsub(/\s+/, " ").strip
    return value if value.length <= max

    "#{value[0...max]}..."
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    command = ARGV[0].to_s.strip
    raise StorePilotBridge::BridgeError, "Command gerekli" if command.empty?

    encoded_payload = ARGV[1].to_s.strip
    payload = if encoded_payload.empty?
                {}
              else
                JSON.parse(Base64.strict_decode64(encoded_payload))
              end

    response = StorePilotBridge.run(command, payload)
    puts JSON.generate({ "ok" => true, "data" => response })
  rescue StandardError => e
    error_message = if e.is_a?(StorePilotBridge::BridgeError)
                      e.message
                    else
                      "#{e.class}: #{e.message}"
                    end

    puts JSON.generate(
      {
        "ok" => false,
        "error" => error_message,
        "backtrace" => Array(e.backtrace).first(12)
      }
    )
    exit 1
  end
end
