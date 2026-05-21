# frozen_string_literal: true

# Specs for fastlane/promote_helpers.rb — the pure helpers behind the iOS
# `promote_to_app_store` lane. `promote_helpers.rb` has no fastlane/spaceship
# dependency, so unlike storepilot_bridge_spec.rb we can require it directly.

require_relative "../promote_helpers"

RSpec.describe PromoteHelpers do
  describe ".format_uploaded_date" do
    it "reduces an ISO8601 timestamp to yyyy-mm-dd" do
      expect(described_class.format_uploaded_date("2026-05-19T14:33:21.000+00:00"))
        .to eq("2026-05-19")
    end

    it "passes through a bare yyyy-mm-dd string" do
      expect(described_class.format_uploaded_date("2026-05-19")).to eq("2026-05-19")
    end

    it "returns (unknown) for nil or blank input" do
      [nil, "", "   "].each do |value|
        expect(described_class.format_uploaded_date(value)).to eq("(unknown)")
      end
    end

    it "returns the raw text when it is not date-shaped" do
      expect(described_class.format_uploaded_date("yesterday")).to eq("yesterday")
    end
  end

  describe ".normalize_build" do
    it "builds a normalized hash and derives :valid from the processing state" do
      build = described_class.normalize_build(
        build_number: " 404 ",
        version: " 2.61.22 ",
        uploaded_date: "2026-05-19T10:00:00Z",
        processing_state: "valid",
        attached: false
      )

      expect(build).to include(
        build_number: "404",
        version: "2.61.22",
        uploaded_date: "2026-05-19",
        processing_state: "VALID",
        valid: true,
        attached: false
      )
    end

    it "marks non-VALID builds as not valid" do
      build = described_class.normalize_build(
        build_number: "403",
        version: "2.61.21",
        uploaded_date: nil,
        processing_state: "PROCESSING",
        attached: true
      )

      expect(build[:valid]).to be false
      expect(build[:attached]).to be true
      expect(build[:processing_state]).to eq("PROCESSING")
      expect(build[:uploaded_date]).to eq("(unknown)")
    end

    it "defaults a blank processing state to UNKNOWN" do
      build = described_class.normalize_build(
        build_number: "1",
        version: "1.0.0",
        uploaded_date: "2026-01-01",
        processing_state: "",
        attached: false
      )

      expect(build[:processing_state]).to eq("UNKNOWN")
      expect(build[:valid]).to be false
    end
  end

  describe ".format_build_line" do
    let(:valid_build) do
      described_class.normalize_build(
        build_number: "404",
        version: "2.61.22",
        uploaded_date: "2026-05-19",
        processing_state: "VALID",
        attached: false
      )
    end

    it "renders a numbered line in the documented shape" do
      expect(described_class.format_build_line(1, valid_build))
        .to eq("  1) 2.61.22 (404) — uploaded 2026-05-19, VALID")
    end

    it "appends a (seçilemez) marker for non-VALID builds" do
      processing = described_class.normalize_build(
        build_number: "403",
        version: "2.61.21",
        uploaded_date: "2026-05-18",
        processing_state: "PROCESSING",
        attached: false
      )

      line = described_class.format_build_line(2, processing)
      expect(line).to start_with("  2) 2.61.21 (403) — uploaded 2026-05-18, PROCESSING")
      expect(line).to include("seçilemez")
    end

    it "flags builds already attached to an App Store version" do
      attached = described_class.normalize_build(
        build_number: "402",
        version: "2.61.20",
        uploaded_date: "2026-05-17",
        processing_state: "VALID",
        attached: true
      )

      expect(described_class.format_build_line(3, attached))
        .to include("App Store sürümüne bağlı")
    end

    it "substitutes a dash for blank version / build number" do
      blank = described_class.normalize_build(
        build_number: "",
        version: "",
        uploaded_date: "2026-05-16",
        processing_state: "VALID",
        attached: false
      )

      expect(described_class.format_build_line(4, blank))
        .to eq("  4) - (-) — uploaded 2026-05-16, VALID")
    end
  end

  describe ".choose_prompt" do
    # This is the load-bearing format test: the string MUST keep matching the
    # Dart `chooseIndex` parser regex in lib/src/services/run_prompt_parser.dart
    # — `Please choose:?\s*(\d+)\s*-\s*(\d+)`.
    CHOOSE_INDEX_REGEX = /Please choose:?\s*(\d+)\s*-\s*(\d+)/i.freeze

    it "produces the exact `Please choose: 1 - N` shape" do
      expect(described_class.choose_prompt(5)).to eq("Please choose: 1 - 5")
    end

    it "matches the fastlane_cli chooseIndex parser regex" do
      [1, 3, 12, 20].each do |count|
        prompt = described_class.choose_prompt(count)
        match = CHOOSE_INDEX_REGEX.match(prompt)
        expect(match).not_to be_nil, "choose_prompt(#{count}) -> #{prompt.inspect} did not match"
        expect(match[1].to_i).to eq(1)
        expect(match[2].to_i).to eq(count)
      end
    end

    it "accepts an integer-like string count" do
      expect(described_class.choose_prompt("7")).to eq("Please choose: 1 - 7")
    end

    it "raises when count is below 1" do
      expect { described_class.choose_prompt(0) }.to raise_error(ArgumentError)
    end

    it "raises when count is not an integer" do
      expect { described_class.choose_prompt("abc") }.to raise_error(ArgumentError)
    end
  end

  describe ".build_number_for_index" do
    let(:builds) do
      [
        described_class.normalize_build(build_number: "404", version: "2.61.22",
                                        uploaded_date: "2026-05-19", processing_state: "VALID", attached: false),
        described_class.normalize_build(build_number: "403", version: "2.61.21",
                                        uploaded_date: "2026-05-18", processing_state: "VALID", attached: false),
        described_class.normalize_build(build_number: "402", version: "2.61.20",
                                        uploaded_date: "2026-05-17", processing_state: "VALID", attached: false)
      ]
    end

    it "maps a 1-based index onto the build number" do
      expect(described_class.build_number_for_index(builds, 1)).to eq("404")
      expect(described_class.build_number_for_index(builds, 3)).to eq("402")
    end

    it "accepts an integer-like string index" do
      expect(described_class.build_number_for_index(builds, "2")).to eq("403")
    end

    it "raises for an index below 1" do
      expect { described_class.build_number_for_index(builds, 0) }
        .to raise_error(ArgumentError, /out of range/)
    end

    it "raises for an index past the end" do
      expect { described_class.build_number_for_index(builds, 4) }
        .to raise_error(ArgumentError, /out of range/)
    end

    it "raises for a non-integer index" do
      expect { described_class.build_number_for_index(builds, "x") }
        .to raise_error(ArgumentError)
    end

    it "raises for an empty build list" do
      expect { described_class.build_number_for_index([], 1) }
        .to raise_error(ArgumentError, /no builds/)
    end
  end

  describe ".find_build_by_number" do
    let(:builds) do
      [
        described_class.normalize_build(build_number: "404", version: "2.61.22",
                                        uploaded_date: "2026-05-19", processing_state: "VALID", attached: false),
        described_class.normalize_build(build_number: "403", version: "2.61.21",
                                        uploaded_date: "2026-05-18", processing_state: "PROCESSING", attached: false)
      ]
    end

    it "finds a build by its build number" do
      found = described_class.find_build_by_number(builds, "403")
      expect(found[:version]).to eq("2.61.21")
      expect(found[:valid]).to be false
    end

    it "tolerates surrounding whitespace in the query" do
      expect(described_class.find_build_by_number(builds, " 404 ")[:version]).to eq("2.61.22")
    end

    it "returns nil when the build number is not present" do
      expect(described_class.find_build_by_number(builds, "999")).to be_nil
    end

    it "returns nil for a blank query" do
      expect(described_class.find_build_by_number(builds, "")).to be_nil
      expect(described_class.find_build_by_number(builds, nil)).to be_nil
    end
  end
end
