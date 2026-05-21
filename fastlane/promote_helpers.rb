# frozen_string_literal: true

# Pure helpers for the iOS `promote_to_app_store` lane.
#
# This module deliberately contains NO spaceship / deliver / fastlane calls —
# only string/array transforms — so it is unit-testable in isolation
# (see fastlane/spec/promote_helpers_spec.rb) without a real App Store
# Connect account or the fastlane gem.
#
# The lane (fastlane/ios/Fastfile `promote_to_app_store`) handles the
# side-effecting parts (querying ASC builds via Spaceship, prompting, and
# `upload_to_app_store`); everything that can be a pure function lives here.
module PromoteHelpers
  module_function

  # App Store Connect build `processingState` value that means the binary is
  # done processing and is eligible to be attached to an App Store version.
  PROCESSING_STATE_VALID = "VALID"

  # Normalises one App Store Connect build into a plain Hash with exactly the
  # fields the picker / summary need. `build` is anything that responds to the
  # spaceship `Build` accessors; the indirection keeps this function pure and
  # testable with a simple struct/double.
  #
  # Returns a Hash:
  #   {
  #     build_number:   "404"        — the buildNumber (App Store "Build")
  #     version:        "2.61.22"    — the pre-release version string
  #     uploaded_date:  "2026-05-19" — yyyy-mm-dd (date portion only) or "(unknown)"
  #     processing_state: "VALID"    — VALID / PROCESSING / INVALID / ...
  #     valid:          true/false   — convenience: processing_state == VALID
  #     attached:       true/false   — already linked to an App Store version
  #   }
  def normalize_build(build_number:, version:, uploaded_date:, processing_state:, attached:)
    state = processing_state.to_s.strip.empty? ? "UNKNOWN" : processing_state.to_s.strip.upcase
    {
      build_number: build_number.to_s.strip,
      version: version.to_s.strip,
      uploaded_date: format_uploaded_date(uploaded_date),
      processing_state: state,
      valid: state == PROCESSING_STATE_VALID,
      attached: attached ? true : false
    }
  end

  # Reduces a raw uploaded-date value (ISO8601 string, Time, Date, or nil)
  # to a `yyyy-mm-dd` string. Returns "(unknown)" for blank input.
  def format_uploaded_date(value)
    return "(unknown)" if value.nil?

    text = value.to_s.strip
    return "(unknown)" if text.empty?

    # ISO8601 timestamps start with the date; take the first 10 chars when
    # they look like a date, otherwise return the raw text.
    if text =~ /\A(\d{4}-\d{2}-\d{2})/
      Regexp.last_match(1)
    else
      text
    end
  end

  # Renders one numbered list line for a normalized build Hash.
  # `index` is 1-based. Example output:
  #   "  1) 2.61.22 (404) — uploaded 2026-05-19, VALID"
  # Non-VALID builds get a trailing marker so the user sees they can't be
  # submitted:
  #   "  2) 2.61.21 (403) — uploaded 2026-05-18, PROCESSING (seçilemez)"
  # Builds already attached to an App Store version are flagged too.
  def format_build_line(index, build)
    marker = []
    marker << "seçilemez" unless build[:valid]
    marker << "App Store sürümüne bağlı" if build[:attached]
    suffix = marker.empty? ? "" : " (#{marker.join(', ')})"

    format(
      "  %d) %s (%s) — uploaded %s, %s%s",
      index,
      blank_to_dash(build[:version]),
      blank_to_dash(build[:build_number]),
      build[:uploaded_date],
      build[:processing_state],
      suffix
    )
  end

  def blank_to_dash(value)
    text = value.to_s.strip
    text.empty? ? "-" : text
  end

  # Builds the exact selection-prompt string the fastlane_cli TUI's
  # `chooseIndex` prompt parser recognises. The Dart parser regex is
  # `Please choose:?\s*(\d+)\s*-\s*(\d+)` (see
  # lib/src/services/run_prompt_parser.dart). The string produced here MUST
  # keep matching that regex — the spec locks the format.
  #
  # `count` is the number of selectable entries (the list is 1-based, so the
  # prompt spans `1 - count`). Raises if count < 1.
  def choose_prompt(count)
    n = Integer(count)
    raise ArgumentError, "choose_prompt needs at least 1 entry (got #{n})" if n < 1

    "Please choose: 1 - #{n}"
  end

  # Maps a 1-based user selection index onto a build_number from a list of
  # normalized builds. Returns the build_number String. Raises ArgumentError
  # for an out-of-range or non-integer index — the lane translates that into
  # a `UI.user_error!`.
  def build_number_for_index(builds, index)
    list = Array(builds)
    raise ArgumentError, "no builds to choose from" if list.empty?

    idx = Integer(index)
    if idx < 1 || idx > list.size
      raise ArgumentError, "selection #{idx} out of range (1 - #{list.size})"
    end

    list[idx - 1][:build_number]
  end

  # Finds a build by its build_number in a list of normalized builds.
  # Returns the build Hash, or nil when not present. Used by the
  # non-interactive `build_number:` override path so the lane can still show
  # the resolved build's version / state in the summary box.
  def find_build_by_number(builds, build_number)
    target = build_number.to_s.strip
    return nil if target.empty?

    Array(builds).find { |b| b[:build_number].to_s.strip == target }
  end
end
