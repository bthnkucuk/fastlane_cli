# frozen_string_literal: true

require "fileutils"

# Pure helpers for the Android Play Console "Set up your app" lanes
# (`store_setup`, `update_app_details`, `upload_data_safety` in
# fastlane/android/Fastfile).
#
# This module deliberately contains NO fastlane / supply / google-apis
# requires — only string/hash/file transforms plus *injected* API surfaces
# (`publisher:` / `details_class:` / `request_class:`) — so it is
# unit-testable in isolation (see fastlane/spec/play_setup_helpers_spec.rb)
# without a Google Play service account or the fastlane gem. Mirrors the
# promote_helpers.rb pattern.
#
# The side-effecting parts (Supply::Client edit lifecycle, the custom
# `google_play_app_details` / `google_play_data_safety` actions, summary
# boxes) live in the lanes / fastlane/actions/*.
module PlaySetupHelpers
  module_function

  # ---------------------------------------------------------------------------
  # Contact details (Play Console "Store settings" → contact details)
  # ---------------------------------------------------------------------------

  CONTACT_FIELDS = %i[contact_email contact_phone contact_website default_language].freeze

  # Files live at the METADATA ROOT (e.g. `<fastlane>/android/metadata/`),
  # NOT inside a locale directory. supply's uploader only ever selects
  # *directories* under `metadata_path` as locales (uploader.rb `all_languages`),
  # so root-level files are inert to `supply` — this adopts the never-merged
  # upstream convention from fastlane discussion #21215 safely.
  CONTACT_FILES = {
    contact_email: "contactEmail.txt",
    contact_phone: "contactPhone.txt",
    contact_website: "contactWebsite.txt",
    default_language: "defaultLanguage.txt"
  }.freeze

  CONTACT_ENV = {
    contact_email: "ANDROID_CONTACT_EMAIL",
    contact_phone: "ANDROID_CONTACT_PHONE",
    contact_website: "ANDROID_CONTACT_WEBSITE",
    default_language: "ANDROID_DEFAULT_LANGUAGE"
  }.freeze

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Tolerant option lookup (string / symbol keys), mirroring
  # FastlaneCliConfig.option without depending on it.
  def option_value(options, key)
    return nil unless options.respond_to?(:key?)

    [key, key.to_s, key.to_sym].uniq.each do |candidate|
      next unless options.key?(candidate)

      value = options[candidate]
      return value unless blank?(value)
    end
    nil
  end

  # Resolves all four contact-detail fields with per-field precedence:
  #   option → env (CONTACT_ENV) → file at the metadata root (CONTACT_FILES).
  #
  # Returns a Hash keyed by field symbol:
  #   { contact_email: { value: "a@example.com", source: "option contact_email" },
  #     contact_phone: { value: nil, source: nil }, ... }
  #
  # The `source` labels feed the summary box so the user can see WHERE each
  # value came from. A blank/missing file (or blank option/env) contributes
  # nothing — the next tier is consulted.
  def resolve_contact_details(options, metadata_path:)
    CONTACT_FIELDS.each_with_object({}) do |field, acc|
      acc[field] = resolve_contact_field(options, field, metadata_path: metadata_path)
    end
  end

  def resolve_contact_field(options, field, metadata_path:)
    explicit = option_value(options, field)
    return { value: explicit.to_s.strip, source: "option #{field}" } unless blank?(explicit)

    env_key = CONTACT_ENV.fetch(field)
    env_value = ENV[env_key]
    return { value: env_value.to_s.strip, source: "env #{env_key}" } unless blank?(env_value)

    filename = CONTACT_FILES.fetch(field)
    file_value = read_contact_file(metadata_path, filename)
    return { value: file_value, source: "file #{filename}" } unless file_value.nil?

    { value: nil, source: nil }
  end

  # Reads `<metadata_path>/<filename>` and returns its stripped content, or
  # nil when the path is blank, the file is missing, or its content is blank.
  def read_contact_file(metadata_path, filename)
    return nil if blank?(metadata_path)

    path = File.join(metadata_path, filename)
    return nil unless File.file?(path)

    content = File.read(path).to_s.strip
    content.empty? ? nil : content
  end

  # True when at least one field resolved to a value.
  def any_contact_value?(details)
    details.values.any? { |entry| !entry[:value].nil? }
  end

  # ---------------------------------------------------------------------------
  # Composite store_setup — listing step error classification
  # ---------------------------------------------------------------------------

  # supply "the track/release isn't ready yet" phrases (case-insensitive
  # substrings). On a brand-new app the store_setup listing step pushes
  # images/screenshots to a track that has no release yet, and supply raises
  # one of these even when changelog upload is skipped. For a *setup* lane on
  # a fresh app that is a normal "not ready yet" condition, not a real error —
  # so the composite soft-skips instead of hard-failing (the standalone
  # update_metadata lane keeps hard-failing, which is correct for it).
  LISTING_NOT_READY_PHRASES = [
    "could not find release for version code",
    "unable to find the requested track",
    "was not found"
  ].freeze

  # True when `message` (case-insensitive) matches any known supply
  # "track/release not ready" phrase. Robust to nil / empty → false.
  def listing_not_ready_error?(message)
    text = message.to_s.downcase
    return false if text.strip.empty?

    LISTING_NOT_READY_PHRASES.any? { |phrase| text.include?(phrase) }
  end

  # ---------------------------------------------------------------------------
  # edits.details GET → diff → PATCH
  # ---------------------------------------------------------------------------

  # Reads one detail field from `current` — either an AndroidPublisher
  # AppDetails-like object (responds to the accessor) or a plain Hash.
  def read_detail(current, field)
    if current.respond_to?(field)
      current.public_send(field)
    elsif current.respond_to?(:[])
      current[field] || (current.respond_to?(:key?) && current.key?(field.to_s) ? current[field.to_s] : nil)
    end
  end

  # Snapshot the four contact fields from an AppDetails-like object / Hash
  # into a plain Hash (used by the pull direction and the summary box).
  def detail_values(current)
    CONTACT_FIELDS.each_with_object({}) do |field, acc|
      acc[field] = read_detail(current, field)
    end
  end

  # Diffs `desired` (Hash field → String, nil/absent = leave untouched)
  # against `current` (AppDetails-like or Hash). Returns only the fields that
  # actually differ, as { field => { from:, to: } }.
  def changed_fields(current:, desired:)
    desired.each_with_object({}) do |(field, value), acc|
      next if value.nil?

      current_value = read_detail(current, field)
      next if current_value.to_s == value.to_s

      acc[field] = { from: current_value, to: value }
    end
  end

  # GET the current app details, diff against `desired`, and PATCH only when
  # something actually changed (a PATCH with a partially-populated
  # `details_class` instance only sends the set fields).
  #
  # `publisher` / `details_class` are injected (the raw
  # Google::Apis::AndroidpublisherV3::AndroidPublisherService and
  # AndroidPublisher::AppDetails at runtime; doubles in specs).
  #
  # Returns { current:, current_values:, changes:, patched: }.
  # NEVER commits/aborts the edit — the caller owns the edit lifecycle.
  def apply_app_details!(publisher:, details_class:, package_name:, edit_id:, desired:)
    current = publisher.get_edit_detail(package_name, edit_id)
    changes = changed_fields(current: current, desired: desired)

    if changes.empty?
      return {
        current: current,
        current_values: detail_values(current),
        changes: changes,
        patched: false
      }
    end

    patch = details_class.new
    changes.each { |field, delta| patch.public_send("#{field}=", delta[:to]) }
    publisher.patch_edit_detail(package_name, edit_id, patch)

    {
      current: current,
      current_values: detail_values(current),
      changes: changes,
      patched: true
    }
  end

  # Validates an explicitly-provided default_language against the locales
  # that actually exist on the Play listing (an unknown default language is
  # rejected by the API with an opaque error — fail early with the available
  # locales named). Blank input is a no-op (nothing will be sent).
  def ensure_default_language_listed!(default_language:, listed_locales:)
    lang = default_language.to_s.strip
    return lang if lang.empty?

    locales = Array(listed_locales).map { |l| l.to_s.strip }.reject(&:empty?)
    return lang if locales.include?(lang)

    user_error!(
      "default_language '#{lang}' is not among the Play listing locales " \
      "(#{locales.empty? ? 'no locales on the listing yet' : locales.join(', ')}). " \
      "Push the listing for that locale first (update_metadata) or pick one of the listed locales."
    )
  end

  # ---------------------------------------------------------------------------
  # Contact-details pull direction (download_store_listing extension)
  # ---------------------------------------------------------------------------

  # Writes each non-blank detail value into its CONTACT_FILES file at the
  # metadata root. `details` is a Hash field → value (String/nil) — the
  # `{value:, source:}` entry shape from resolve_contact_details is also
  # accepted. Returns the list of written filenames.
  def write_contact_files(metadata_path:, details:)
    raise ArgumentError, "metadata_path is required" if blank?(metadata_path)

    FileUtils.mkdir_p(metadata_path)
    CONTACT_FIELDS.each_with_object([]) do |field, written|
      value = details[field]
      value = value[:value] if value.is_a?(Hash)
      next if blank?(value)

      filename = CONTACT_FILES.fetch(field)
      File.write(File.join(metadata_path, filename), "#{value.to_s.strip}\n")
      written << filename
    end
  end

  # ---------------------------------------------------------------------------
  # Data safety (applications.dataSafety)
  # ---------------------------------------------------------------------------

  DATA_SAFETY_ENV = "ANDROID_DATA_SAFETY_CSV_PATH"
  # App-level override, relative to the app's fastlane root.
  DATA_SAFETY_APP_RELATIVE = "android/data_safety.csv"
  # CLI-bundled default template, relative to the runner's fastlane root.
  DATA_SAFETY_DEFAULT_RELATIVE = "android/defaults/data_safety.csv"

  # Resolves the Data safety CSV path with the ladder:
  #   1. `data_safety_csv_path` option  (returned as-is even if missing —
  #      an explicit path that does not exist should hard-fail loudly in
  #      upload_data_safety!, not silently fall through)
  #   2. ANDROID_DATA_SAFETY_CSV_PATH env (same explicit-intent semantics)
  #   3. app override  <fastlane_root>/android/data_safety.csv  (if present)
  #   4. CLI default   <runner_root>/android/defaults/data_safety.csv (if present)
  #
  # Relative option/env paths expand against `base_dir` (the app root at
  # runtime — mirrors FastlaneCliConfig.resolve_path_in_fastlane), falling
  # back to `fastlane_root`. Returns { path:, source: } — `path` is nil and
  # `source` is "bulunamadı" when nothing resolves.
  def resolve_data_safety_csv_path(options, fastlane_root:, runner_root:, base_dir: nil)
    expansion_root = blank?(base_dir) ? fastlane_root : base_dir

    explicit = option_value(options, :data_safety_csv_path)
    unless blank?(explicit)
      return {
        path: File.expand_path(explicit.to_s, expansion_root),
        source: "option data_safety_csv_path"
      }
    end

    env_value = ENV[DATA_SAFETY_ENV]
    unless blank?(env_value)
      return {
        path: File.expand_path(env_value.to_s, expansion_root),
        source: "env #{DATA_SAFETY_ENV}"
      }
    end

    unless blank?(fastlane_root)
      app_path = File.expand_path(DATA_SAFETY_APP_RELATIVE, fastlane_root)
      return { path: app_path, source: "app override (#{DATA_SAFETY_APP_RELATIVE})" } if File.file?(app_path)
    end

    unless blank?(runner_root)
      default_path = File.expand_path(DATA_SAFETY_DEFAULT_RELATIVE, runner_root)
      return { path: default_path, source: "CLI default şablon" } if File.file?(default_path)
    end

    { path: nil, source: "bulunamadı" }
  end

  # True when the resolved Data safety CSV came from the USER — an explicit
  # `data_safety_csv_path` option, the ANDROID_DATA_SAFETY_CSV_PATH env, or
  # the app's own `<fastlane_root>/android/data_safety.csv` override — as
  # opposed to the bundled generic CLI-default template ("CLI default şablon")
  # or nothing ("bulunamadı"). The composite store_setup lane only
  # auto-uploads a user-provided CSV: the generic template is never pushed
  # automatically (Google rejects it with a 400 and it would overwrite a
  # hand-filled form with generic answers). Matches the `source` labels
  # produced by resolve_data_safety_csv_path.
  def user_provided_csv?(source)
    label = source.to_s
    label.start_with?("option ") ||
      label.start_with?("env ") ||
      label.start_with?("app override")
  end

  # POSTs the Data safety CSV via applications.dataSafety. `publisher` /
  # `request_class` are injected (AndroidPublisherService /
  # AndroidPublisher::SafetyLabelsUpdateRequest at runtime; doubles in specs).
  #
  # Hard-fails (user_error!) on a missing or empty CSV — an empty POST would
  # wipe the whole form. Returns { lines:, bytes: } for the summary box.
  #
  # NOTE: this endpoint REPLACES the entire Data safety form and has no read
  # counterpart — callers must surface that in their summary box.
  def upload_data_safety!(publisher:, request_class:, package_name:, csv_path:)
    path = csv_path.to_s
    if path.strip.empty? || !File.file?(path)
      user_error!("Data safety CSV not found at '#{path}'. Provide data_safety_csv_path, " \
                  "set #{DATA_SAFETY_ENV}, or place #{DATA_SAFETY_APP_RELATIVE} in the app's fastlane folder.")
    end

    csv = File.read(path)
    user_error!("Data safety CSV at '#{path}' is empty — uploading it would wipe the entire form.") if csv.strip.empty?

    publisher.data_application_safety(package_name, request_class.new(safety_labels: csv))
    { lines: csv.lines.size, bytes: csv.bytesize }
  end

  # ---------------------------------------------------------------------------
  # Manual remainder (no Play Developer API surface)
  # ---------------------------------------------------------------------------

  # The Play Console "Set up your app" items that CANNOT be automated —
  # there is no Play Developer API for any of them. Privacy policy URL is
  # FIRST deliberately: users expect it to be automatable (it is a URL, after
  # all) and it is not — it is neither in the Data safety CSV nor anywhere
  # else in the API.
  MANUAL_CONSOLE_ITEMS = [
    "Privacy policy URL (gizlilik politikası — API yok, Console'dan girilir)",
    "App access (test hesabı / erişim bilgileri)",
    "Ads (reklam beyanı)",
    "Content rating (içerik derecelendirme anketi)",
    "Target audience (hedef yaş grubu)",
    "Government apps (devlet uygulaması beyanı)",
    "Financial features (finansal özellik beyanı)",
    "Health (sağlık beyanı)",
    "App category (uygulama kategorisi)"
  ].freeze

  # Summary-box lines for the manual remainder: a `:sep` divider, a header,
  # the numbered MANUAL_CONSOLE_ITEMS, and the precondition note that the
  # app record itself must already exist in Play Console (creating the app
  # record has no API either).
  def manual_checklist_lines
    lines = [
      :sep,
      "Console'da manuel tamamlanmalı (Play Developer API desteklemiyor):"
    ]
    MANUAL_CONSOLE_ITEMS.each_with_index do |item, index|
      lines << "  #{index + 1}) #{item}"
    end
    lines << "Ön koşul: uygulama kaydı Play Console'da önceden oluşturulmuş olmalı."
    lines
  end

  # Raise through FastlaneCore::UI when available (lanes/actions), otherwise
  # a plain RuntimeError (bare-Ruby usage). Specs stub FastlaneCore::UI.
  def user_error!(message)
    if defined?(FastlaneCore::UI)
      FastlaneCore::UI.user_error!(message)
    else
      raise message.to_s
    end
  end
end
