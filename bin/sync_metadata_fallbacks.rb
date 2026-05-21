#!/usr/bin/env ruby
# frozen_string_literal: true

# Sprays root-level fallback files (support_url.txt, marketing_url.txt,
# privacy_url.txt) into every locale subfolder under an iOS `metadata/` dir.
#
# Same mechanic the iOS `update_metadata` lane uses at upload-time, exposed as
# a standalone command so the per-locale state can be committed to git instead
# of being magic-materialized only inside the lane.
#
# Usage:
#   ruby packages/fastlane_cli/bin/sync_metadata_fallbacks.rb <metadata_path>
#   ruby packages/fastlane_cli/bin/sync_metadata_fallbacks.rb --force <metadata_path>
#
# Default behavior: only writes to locale files that are missing or empty
# (i.e., an explicit per-locale override is preserved). `--force` overwrites
# every locale file with the root value.

require "optparse"
require_relative "../fastlane/common_helpers"

options = { force: false, filenames: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: sync_metadata_fallbacks.rb [options] <metadata_path>"
  opts.on("--force", "Overwrite locale files even when they have content") { options[:force] = true }
  opts.on("--files=LIST", "Comma-separated filenames (default: support_url.txt,marketing_url.txt,privacy_url.txt)") do |v|
    options[:filenames] = v.split(",").map(&:strip).reject(&:empty?)
  end
end.parse!

metadata_path = ARGV.shift
abort("metadata_path is required") if metadata_path.nil? || metadata_path.strip.empty?
metadata_path = File.expand_path(metadata_path)
abort("metadata_path does not exist: #{metadata_path}") unless Dir.exist?(metadata_path)

filenames = options[:filenames] || FastlaneCliConfig::LOCALISED_URL_FALLBACK_FILES

fallback_map = {}
filenames.each do |fname|
  root_path = File.join(metadata_path, fname)
  unless File.file?(root_path)
    warn("skip #{fname}: no root file at #{root_path}")
    next
  end
  content = File.read(root_path).to_s
  if content.strip.empty?
    warn("skip #{fname}: root file is empty")
    next
  end
  fallback_map[fname] = content
end

if fallback_map.empty?
  warn("nothing to sync — no non-empty root files found")
  exit 0
end

written = []
skipped_override = []
Dir.children(metadata_path).each do |entry|
  full = File.join(metadata_path, entry)
  next unless File.directory?(full)
  next if FastlaneCliConfig::METADATA_NON_LOCALE_DIRS.include?(entry)
  next if entry.start_with?(".")

  fallback_map.each do |fname, content|
    target = File.join(full, fname)
    has_content = File.file?(target) && !File.read(target).to_s.strip.empty?
    if has_content && !options[:force]
      skipped_override << target
      next
    end
    File.write(target, content)
    written << target
  end
end

puts "synced #{written.size} file(s) under #{metadata_path}"
puts "preserved #{skipped_override.size} per-locale override(s)" unless skipped_override.empty?
fallback_map.each_key { |fname| puts "  ✓ #{fname}" }
