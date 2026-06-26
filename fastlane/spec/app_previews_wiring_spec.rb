# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Wiring guard for the iOS App Preview upload feature.
#
# App Preview video upload lives in a DEDICATED lane (`upload_app_previews`),
# mirroring `upload_app_privacy_details` — not folded into `update_metadata` —
# so the large/slow video sync never piggybacks on a metadata text push. This
# spec pins the three things that must stay in sync for the
# `ios_upload_app_previews` action to actually run:
#   1. the lane exists in ios/Fastfile,
#   2. it passes `app_previews_path` to deliver and defaults overwrite to false,
#   3. profile.base.yaml exposes the action id and points it at the lane.
RSpec.describe "iOS App Preview upload wiring" do
  fastlane_dir = File.expand_path("..", __dir__)
  ios_fastfile = File.read(File.join(fastlane_dir, "ios", "Fastfile"))
  profile_base = YAML.safe_load(File.read(File.join(fastlane_dir, "profile.base.yaml")))

  it "defines the dedicated upload_app_previews lane" do
    expect(ios_fastfile).to match(/^\s*lane :upload_app_previews do/)
  end

  it "passes app_previews_path to deliver" do
    expect(ios_fastfile).to include("app_previews_path: previews_path")
  end

  it "defaults overwrite_preview_videos to false (non-destructive)" do
    expect(ios_fastfile).to match(/overwrite_preview_videos, default: false/)
  end

  it "skips metadata/screenshots/binary so only previews are touched" do
    lane = ios_fastfile[/lane :upload_app_previews do.*?^  end/m]
    expect(lane).to include("skip_metadata: true")
    expect(lane).to include("skip_screenshots: true")
    expect(lane).to include("skip_binary_upload: true")
  end

  it "registers the ios_upload_app_previews action pointing at the lane" do
    action = profile_base.fetch("actions").find { |a| a["id"] == "ios_upload_app_previews" }
    expect(action).not_to be_nil
    expect(action.dig("command", "platform")).to eq("ios")
    expect(action.dig("command", "lane")).to eq("upload_app_previews")
  end
end
