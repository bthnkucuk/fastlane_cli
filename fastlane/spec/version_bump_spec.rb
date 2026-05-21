# frozen_string_literal: true

# Specs for the component-wise-max version-bump computation (v0.7.0).
#
# The algorithm takes the maximum of each version component (major/minor/
# patch/build) independently across all three sources (Android Play, iOS App
# Store, local pubspec), then applies a selectable bump level. The build
# number is always max_build + 1. See `resolve_bumped_version` /
# `parse_version_components` in common_helpers.rb.
#
# These functions are PURE — no file/network I/O — so everything below is a
# straight input → output assertion.

RSpec.describe "FastlaneCliConfig version bump" do
  describe ".parse_version_components" do
    it "splits MAJOR.MINOR.PATCH+BUILD into integers" do
      expect(FastlaneCliConfig.parse_version_components("1.2.3+400")).to eq(
        major: 1, minor: 2, patch: 3, build: 400
      )
    end

    it "defaults a missing +BUILD suffix to 0" do
      expect(FastlaneCliConfig.parse_version_components("2.3.1")).to eq(
        major: 2, minor: 3, patch: 1, build: 0
      )
    end

    it "tolerates an inline `# comment` after the version (v0.3.2 regex parity)" do
      expect(FastlaneCliConfig.parse_version_components("1.4.2+57  # do not edit")).to eq(
        major: 1, minor: 4, patch: 2, build: 57
      )
    end

    it "treats nil / blank / unknown / 0 as 0.0.0+0" do
      [nil, "", "   ", "unknown", "UNKNOWN", "0"].each do |raw|
        expect(FastlaneCliConfig.parse_version_components(raw)).to eq(
          major: 0, minor: 0, patch: 0, build: 0
        ), "expected #{raw.inspect} to fold to zeros"
      end
    end

    it "raises on a non-numeric component" do
      expect { FastlaneCliConfig.parse_version_components("1.x.3+4") }
        .to raise_error(ArgumentError, /Invalid version string/)
    end

    it "raises on a missing component" do
      expect { FastlaneCliConfig.parse_version_components("1.2+4") }
        .to raise_error(ArgumentError, /Invalid version string/)
    end
  end

  describe ".normalize_bump_level" do
    it "accepts patch / minor / major (string or symbol, any case)" do
      expect(FastlaneCliConfig.normalize_bump_level("patch")).to eq(:patch)
      expect(FastlaneCliConfig.normalize_bump_level(:minor)).to eq(:minor)
      expect(FastlaneCliConfig.normalize_bump_level("MAJOR")).to eq(:major)
    end

    it "defaults a blank value to :patch" do
      expect(FastlaneCliConfig.normalize_bump_level("")).to eq(:patch)
      expect(FastlaneCliConfig.normalize_bump_level(nil)).to eq(:patch)
    end

    it "raises a clear error listing the three accepted values" do
      expect { FastlaneCliConfig.normalize_bump_level("hotfix") }
        .to raise_error(ArgumentError, /accepted values: patch, minor, major/)
    end
  end

  describe ".resolve_bumped_version" do
    # The canonical worked example from the v0.7.0 spec.
    WORKED_EXAMPLE_SOURCES = [
      { version: "1.2.3", build: 400 },
      { version: "1.2.4", build: 399 },
      { version: "2.3.1", build: 100 }
    ].freeze

    it "patch bump → 2.3.5+401 for the worked example" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: WORKED_EXAMPLE_SOURCES, bump: :patch
      )
      expect(result[:full]).to eq("2.3.5+401")
      expect(result[:version_name]).to eq("2.3.5")
      expect(result[:build_number]).to eq(401)
      expect(result[:maxes]).to eq(major: 2, minor: 3, patch: 4, build: 400)
    end

    it "minor bump → 2.4.0+401 for the worked example" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: WORKED_EXAMPLE_SOURCES, bump: :minor
      )
      expect(result[:full]).to eq("2.4.0+401")
    end

    it "major bump → 3.0.0+401 for the worked example" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: WORKED_EXAMPLE_SOURCES, bump: :major
      )
      expect(result[:full]).to eq("3.0.0+401")
    end

    it "accepts combined `version: X.Y.Z+N` strings (no separate build key)" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: ["1.2.3+400", "1.2.4+399", "2.3.1+100"], bump: :patch
      )
      expect(result[:full]).to eq("2.3.5+401")
    end

    it "lets an explicit `build:` override a +BUILD parsed from `version:`" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: [{ version: "1.2.3+1", build: 400 }], bump: :patch
      )
      expect(result[:build_number]).to eq(401)
    end

    it "folds an `unknown|0` source in as 0.0.0+0 without breaking the max" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: [
          { version: "unknown", build: "0" }, # store not reachable / unpublished
          { version: "1.2.4", build: 399 },
          { version: "2.3.1", build: 100 }
        ],
        bump: :patch
      )
      # Same maxes as if the unknown source contributed zeros.
      expect(result[:maxes]).to eq(major: 2, minor: 3, patch: 4, build: 399)
      expect(result[:full]).to eq("2.3.5+400")
    end

    it "still bumps when all three sources are equal" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: ["1.5.2+30", "1.5.2+30", "1.5.2+30"], bump: :patch
      )
      expect(result[:full]).to eq("1.5.3+31")

      minor = FastlaneCliConfig.resolve_bumped_version(
        sources: ["1.5.2+30", "1.5.2+30", "1.5.2+30"], bump: :minor
      )
      expect(minor[:full]).to eq("1.6.0+31")

      major = FastlaneCliConfig.resolve_bumped_version(
        sources: ["1.5.2+30", "1.5.2+30", "1.5.2+30"], bump: :major
      )
      expect(major[:full]).to eq("2.0.0+31")
    end

    it "always moves forward when pubspec is already ahead of both stores" do
      # pubspec at 9.9.9+999 dwarfs both stores; the result is still
      # component-max + increment — the algorithm never stands still.
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: [
          { version: "1.0.0", build: 10 }, # android (behind)
          { version: "1.0.1", build: 11 }, # ios (behind)
          { version: "9.9.9", build: 999 } # pubspec (ahead)
        ],
        bump: :patch
      )
      expect(result[:full]).to eq("9.9.10+1000")
    end

    it "treats an empty sources array as a single 0.0.0+0 source" do
      result = FastlaneCliConfig.resolve_bumped_version(sources: [], bump: :patch)
      expect(result[:full]).to eq("0.0.1+1")
    end

    it "raises on an invalid bump value" do
      expect do
        FastlaneCliConfig.resolve_bumped_version(
          sources: ["1.0.0+1"], bump: "sideways"
        )
      end.to raise_error(ArgumentError, /accepted values: patch, minor, major/)
    end

    it "raises on a malformed version component in a source" do
      expect do
        FastlaneCliConfig.resolve_bumped_version(
          sources: ["1.2.3+4", "bad.version"], bump: :patch
        )
      end.to raise_error(ArgumentError, /Invalid version string/)
    end

    it "still parses a source whose version line carries an inline comment" do
      result = FastlaneCliConfig.resolve_bumped_version(
        sources: ["1.2.3+400  # bumped by CI", "1.2.4+399", "2.3.1+100"],
        bump: :patch
      )
      expect(result[:full]).to eq("2.3.5+401")
    end
  end

  describe ".parse_build_component" do
    it "parses a plain integer build number" do
      expect(FastlaneCliConfig.parse_build_component("42")).to eq(42)
      expect(FastlaneCliConfig.parse_build_component(42)).to eq(42)
    end

    it "treats blank / unknown as 0" do
      expect(FastlaneCliConfig.parse_build_component("")).to eq(0)
      expect(FastlaneCliConfig.parse_build_component("unknown")).to eq(0)
      expect(FastlaneCliConfig.parse_build_component(nil)).to eq(0)
    end

    it "raises on a non-numeric build number" do
      expect { FastlaneCliConfig.parse_build_component("1.2") }
        .to raise_error(ArgumentError, /Invalid build number/)
    end
  end
end
