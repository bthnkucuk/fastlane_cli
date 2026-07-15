# frozen_string_literal: true

# Specs for fastlane/play_setup_helpers.rb — the pure helpers behind the
# Android Play Console "Set up your app" lanes (`store_setup`,
# `update_app_details`, `upload_data_safety`). play_setup_helpers.rb has no
# fastlane/supply/google-apis dependency, so — like promote_helpers_spec.rb —
# we can require it directly. The Google API surfaces are INJECTED
# (publisher:/details_class:/request_class:), so everything is spec-able with
# plain doubles.
#
# Fixture hygiene (pre-push leak guard): only `@example.com` emails and the
# `+10000000000` placeholder phone number. No brand names.

require_relative "../play_setup_helpers"

RSpec.describe PlaySetupHelpers do
  TRACKED_PLAY_SETUP_ENV_KEYS = %w[
    ANDROID_CONTACT_EMAIL
    ANDROID_CONTACT_PHONE
    ANDROID_CONTACT_WEBSITE
    ANDROID_DEFAULT_LANGUAGE
    ANDROID_DATA_SAFETY_CSV_PATH
  ].freeze

  around(:each) do |ex|
    saved = TRACKED_PLAY_SETUP_ENV_KEYS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    TRACKED_PLAY_SETUP_ENV_KEYS.each { |k| ENV.delete(k) }
    begin
      ex.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  # A minimal AppDetails-like double: plain accessors, no Google gems.
  FakeAppDetails = Struct.new(:contact_email, :contact_phone, :contact_website, :default_language,
                              keyword_init: true)

  describe ".resolve_contact_details" do
    it "prefers an explicit option over env and file" do
      with_tmpdir do |dir|
        write_file(File.join(dir, "contactEmail.txt"), "file@example.com\n")
        ENV["ANDROID_CONTACT_EMAIL"] = "env@example.com"

        details = described_class.resolve_contact_details(
          { contact_email: "option@example.com" }, metadata_path: dir
        )

        expect(details[:contact_email]).to eq(
          value: "option@example.com", source: "option contact_email"
        )
      end
    end

    it "prefers env over file when no option is given" do
      with_tmpdir do |dir|
        write_file(File.join(dir, "contactPhone.txt"), "+10000000000\n")
        ENV["ANDROID_CONTACT_PHONE"] = "+10000000000"

        details = described_class.resolve_contact_details({}, metadata_path: dir)

        expect(details[:contact_phone]).to eq(
          value: "+10000000000", source: "env ANDROID_CONTACT_PHONE"
        )
      end
    end

    it "falls back to the metadata-root file and strips whitespace" do
      with_tmpdir do |dir|
        write_file(File.join(dir, "contactWebsite.txt"), "  https://example.com  \n")

        details = described_class.resolve_contact_details({}, metadata_path: dir)

        expect(details[:contact_website]).to eq(
          value: "https://example.com", source: "file contactWebsite.txt"
        )
      end
    end

    it "treats a blank file as unresolved (value nil, source nil)" do
      with_tmpdir do |dir|
        write_file(File.join(dir, "defaultLanguage.txt"), "   \n")

        details = described_class.resolve_contact_details({}, metadata_path: dir)

        expect(details[:default_language]).to eq(value: nil, source: nil)
      end
    end

    it "resolves every field independently and tolerates string option keys" do
      with_tmpdir do |dir|
        write_file(File.join(dir, "contactEmail.txt"), "file@example.com\n")
        ENV["ANDROID_DEFAULT_LANGUAGE"] = "en-US"

        details = described_class.resolve_contact_details(
          { "contact_website" => "https://example.com" }, metadata_path: dir
        )

        expect(details[:contact_email][:value]).to eq("file@example.com")
        expect(details[:contact_website][:value]).to eq("https://example.com")
        expect(details[:default_language][:value]).to eq("en-US")
        expect(details[:contact_phone]).to eq(value: nil, source: nil)
      end
    end

    it "skips the file tier gracefully when metadata_path is nil" do
      details = described_class.resolve_contact_details({}, metadata_path: nil)

      expect(details.values).to all(eq(value: nil, source: nil))
    end
  end

  describe ".any_contact_value?" do
    it "is true when at least one field resolved" do
      details = described_class.resolve_contact_details(
        { contact_email: "a@example.com" }, metadata_path: nil
      )
      expect(described_class.any_contact_value?(details)).to be true
    end

    it "is false when nothing resolved" do
      details = described_class.resolve_contact_details({}, metadata_path: nil)
      expect(described_class.any_contact_value?(details)).to be false
    end
  end

  describe ".listing_not_ready_error?" do
    it "matches the real 'could not find release for version code' error (any case)" do
      expect(
        described_class.listing_not_ready_error?(
          "Could not find release for version code '' to update changelog"
        )
      ).to be true
    end

    it "matches the 'unable to find the requested track' phrase" do
      expect(
        described_class.listing_not_ready_error?("Unable to find the requested track: alpha")
      ).to be true
    end

    it "matches a 'was not found' track-not-found variant" do
      expect(
        described_class.listing_not_ready_error?("Track 'alpha' was not found.")
      ).to be true
    end

    it "is false for an unrelated error" do
      expect(described_class.listing_not_ready_error?("boom")).to be false
    end

    it "is false for nil and empty input" do
      expect(described_class.listing_not_ready_error?(nil)).to be false
      expect(described_class.listing_not_ready_error?("")).to be false
      expect(described_class.listing_not_ready_error?("   ")).to be false
    end
  end

  describe ".changed_fields" do
    let(:current) do
      FakeAppDetails.new(
        contact_email: "old@example.com",
        contact_phone: nil,
        contact_website: "https://example.com",
        default_language: "en-US"
      )
    end

    it "returns only the fields that actually differ" do
      changes = described_class.changed_fields(
        current: current,
        desired: {
          contact_email: "new@example.com",
          contact_website: "https://example.com"
        }
      )

      expect(changes).to eq(
        contact_email: { from: "old@example.com", to: "new@example.com" }
      )
    end

    it "returns an empty hash when nothing differs" do
      changes = described_class.changed_fields(
        current: current,
        desired: { contact_email: "old@example.com", default_language: "en-US" }
      )

      expect(changes).to be_empty
    end

    it "ignores nil desired values (field left untouched)" do
      changes = described_class.changed_fields(
        current: current,
        desired: { contact_email: nil, contact_phone: "+10000000000" }
      )

      expect(changes.keys).to eq([:contact_phone])
      expect(changes[:contact_phone]).to eq(from: nil, to: "+10000000000")
    end

    it "reads current values from a plain hash too" do
      changes = described_class.changed_fields(
        current: { contact_email: "old@example.com" },
        desired: { contact_email: "new@example.com" }
      )

      expect(changes[:contact_email]).to eq(from: "old@example.com", to: "new@example.com")
    end
  end

  describe ".detail_values" do
    it "snapshots the four contact fields into a plain hash" do
      current = FakeAppDetails.new(contact_email: "a@example.com", default_language: "tr-TR")

      expect(described_class.detail_values(current)).to eq(
        contact_email: "a@example.com",
        contact_phone: nil,
        contact_website: nil,
        default_language: "tr-TR"
      )
    end
  end

  describe ".apply_app_details!" do
    let(:current) do
      FakeAppDetails.new(contact_email: "old@example.com", default_language: "en-US")
    end

    it "does NOT patch when nothing changed (pure-GET mode)" do
      publisher = double("publisher")
      expect(publisher).to receive(:get_edit_detail).with("com.example.app", "edit-1")
                                                    .and_return(current)
      expect(publisher).not_to receive(:patch_edit_detail)

      result = described_class.apply_app_details!(
        publisher: publisher,
        details_class: FakeAppDetails,
        package_name: "com.example.app",
        edit_id: "edit-1",
        desired: { contact_email: "old@example.com" }
      )

      expect(result[:patched]).to be false
      expect(result[:changes]).to be_empty
      expect(result[:current_values][:contact_email]).to eq("old@example.com")
    end

    it "patches with ONLY the changed fields set" do
      details_class = Class.new do
        attr_accessor :contact_email, :contact_phone, :contact_website, :default_language
      end

      captured_patch = nil
      publisher = double("publisher")
      allow(publisher).to receive(:get_edit_detail).and_return(current)
      expect(publisher).to receive(:patch_edit_detail) do |package_name, edit_id, patch|
        expect(package_name).to eq("com.example.app")
        expect(edit_id).to eq("edit-1")
        captured_patch = patch
      end

      result = described_class.apply_app_details!(
        publisher: publisher,
        details_class: details_class,
        package_name: "com.example.app",
        edit_id: "edit-1",
        desired: {
          contact_email: "new@example.com",
          default_language: "en-US" # unchanged → must NOT be set on the patch
        }
      )

      expect(result[:patched]).to be true
      expect(result[:changes].keys).to eq([:contact_email])
      expect(captured_patch.contact_email).to eq("new@example.com")
      expect(captured_patch.default_language).to be_nil
      expect(captured_patch.contact_phone).to be_nil
    end
  end

  describe ".ensure_default_language_listed!" do
    it "passes when the language is listed" do
      expect(
        described_class.ensure_default_language_listed!(
          default_language: "en-US", listed_locales: %w[en-US tr-TR]
        )
      ).to eq("en-US")
    end

    it "is a no-op for blank input" do
      expect(
        described_class.ensure_default_language_listed!(
          default_language: "  ", listed_locales: %w[en-US]
        )
      ).to eq("")
    end

    it "raises naming the available locales on a mismatch" do
      expect do
        described_class.ensure_default_language_listed!(
          default_language: "de-DE", listed_locales: %w[en-US tr-TR]
        )
      end.to raise_error(FastlaneCore::UIError, /de-DE.*en-US, tr-TR/)
    end

    it "says when the listing has no locales at all" do
      expect do
        described_class.ensure_default_language_listed!(
          default_language: "en-US", listed_locales: []
        )
      end.to raise_error(FastlaneCore::UIError, /no locales on the listing yet/)
    end
  end

  describe ".write_contact_files" do
    it "writes each non-blank value to its metadata-root file" do
      with_tmpdir do |dir|
        written = described_class.write_contact_files(
          metadata_path: dir,
          details: {
            contact_email: "a@example.com",
            contact_phone: nil,
            contact_website: "https://example.com",
            default_language: ""
          }
        )

        expect(written).to eq(%w[contactEmail.txt contactWebsite.txt])
        expect(File.read(File.join(dir, "contactEmail.txt"))).to eq("a@example.com\n")
        expect(File.exist?(File.join(dir, "contactPhone.txt"))).to be false
      end
    end

    it "accepts the {value:, source:} entry shape from resolve_contact_details" do
      with_tmpdir do |dir|
        written = described_class.write_contact_files(
          metadata_path: dir,
          details: { contact_email: { value: "a@example.com", source: "option" } }
        )

        expect(written).to eq(%w[contactEmail.txt])
        expect(File.read(File.join(dir, "contactEmail.txt"))).to eq("a@example.com\n")
      end
    end

    it "creates the metadata directory when missing" do
      with_tmpdir do |dir|
        nested = File.join(dir, "android", "metadata")
        described_class.write_contact_files(
          metadata_path: nested, details: { contact_email: "a@example.com" }
        )

        expect(File.file?(File.join(nested, "contactEmail.txt"))).to be true
      end
    end

    it "raises for a blank metadata_path" do
      expect do
        described_class.write_contact_files(metadata_path: nil, details: {})
      end.to raise_error(ArgumentError, /metadata_path/)
    end
  end

  describe ".resolve_data_safety_csv_path" do
    it "prefers the explicit option (returned even when the file is missing)" do
      with_tmpdir do |dir|
        ENV["ANDROID_DATA_SAFETY_CSV_PATH"] = File.join(dir, "env.csv")

        resolved = described_class.resolve_data_safety_csv_path(
          { data_safety_csv_path: "custom/safety.csv" },
          fastlane_root: File.join(dir, "fastlane"),
          runner_root: File.join(dir, "runner"),
          base_dir: dir
        )

        expect(resolved).to eq(
          path: File.join(dir, "custom/safety.csv"),
          source: "option data_safety_csv_path"
        )
      end
    end

    it "falls back to the env var next" do
      with_tmpdir do |dir|
        ENV["ANDROID_DATA_SAFETY_CSV_PATH"] = File.join(dir, "env.csv")

        resolved = described_class.resolve_data_safety_csv_path(
          {},
          fastlane_root: File.join(dir, "fastlane"),
          runner_root: File.join(dir, "runner")
        )

        expect(resolved).to eq(
          path: File.join(dir, "env.csv"),
          source: "env ANDROID_DATA_SAFETY_CSV_PATH"
        )
      end
    end

    it "uses the app override when it exists" do
      with_tmpdir do |dir|
        fastlane_root = File.join(dir, "fastlane")
        write_file(File.join(fastlane_root, "android", "data_safety.csv"), "csv")

        resolved = described_class.resolve_data_safety_csv_path(
          {}, fastlane_root: fastlane_root, runner_root: File.join(dir, "runner")
        )

        expect(resolved[:path]).to eq(File.join(fastlane_root, "android", "data_safety.csv"))
        expect(resolved[:source]).to eq("app override (android/data_safety.csv)")
      end
    end

    it "prefers the app override over the CLI default when BOTH files exist" do
      # The feature's #1 risk mitigation: an app's own Data safety export
      # must ALWAYS beat the generic CLI template — a swap of these two
      # tiers would silently upload generic answers over a hand-filled form
      # (whole-form replacement, no read counterpart to recover from).
      with_tmpdir do |dir|
        fastlane_root = File.join(dir, "fastlane")
        runner_root = File.join(dir, "runner")
        app_csv = write_file(File.join(fastlane_root, "android", "data_safety.csv"), "app csv")
        write_file(File.join(runner_root, "android", "defaults", "data_safety.csv"), "cli csv")

        resolved = described_class.resolve_data_safety_csv_path(
          {}, fastlane_root: fastlane_root, runner_root: runner_root
        )

        expect(resolved).to eq(
          path: app_csv,
          source: "app override (android/data_safety.csv)"
        )
      end
    end

    it "falls back to the CLI default template last" do
      with_tmpdir do |dir|
        runner_root = File.join(dir, "runner")
        write_file(File.join(runner_root, "android", "defaults", "data_safety.csv"), "csv")

        resolved = described_class.resolve_data_safety_csv_path(
          {}, fastlane_root: File.join(dir, "fastlane"), runner_root: runner_root
        )

        expect(resolved[:path]).to eq(File.join(runner_root, "android", "defaults", "data_safety.csv"))
        expect(resolved[:source]).to eq("CLI default şablon")
      end
    end

    it "returns a nil path with source bulunamadı when nothing resolves" do
      with_tmpdir do |dir|
        resolved = described_class.resolve_data_safety_csv_path(
          {}, fastlane_root: File.join(dir, "fastlane"), runner_root: File.join(dir, "runner")
        )

        expect(resolved).to eq(path: nil, source: "bulunamadı")
      end
    end
  end

  describe ".user_provided_csv?" do
    # Gates the composite store_setup auto-upload and the standalone
    # upload_data_safety hard-fail: only a user-supplied CSV (option / env /
    # app override) may be pushed automatically; the generic CLI template and
    # a missing file must NOT be. The labels mirror resolve_data_safety_csv_path.
    it "is true for a CSV supplied via the data_safety_csv_path option" do
      expect(described_class.user_provided_csv?("option data_safety_csv_path")).to be true
    end

    it "is true for a CSV supplied via the env var" do
      expect(described_class.user_provided_csv?("env ANDROID_DATA_SAFETY_CSV_PATH")).to be true
    end

    it "is true for the app override file" do
      expect(described_class.user_provided_csv?("app override (android/data_safety.csv)")).to be true
    end

    it "is false for the bundled CLI-default template" do
      expect(described_class.user_provided_csv?("CLI default şablon")).to be false
    end

    it "is false when nothing resolved" do
      expect(described_class.user_provided_csv?("bulunamadı")).to be false
    end

    it "is false for nil" do
      expect(described_class.user_provided_csv?(nil)).to be false
    end
  end

  describe ".upload_data_safety!" do
    FakeSafetyRequest = Struct.new(:safety_labels, keyword_init: true)

    it "raises for a missing CSV path" do
      publisher = double("publisher")
      expect(publisher).not_to receive(:data_application_safety)

      expect do
        described_class.upload_data_safety!(
          publisher: publisher,
          request_class: FakeSafetyRequest,
          package_name: "com.example.app",
          csv_path: "/nonexistent/data_safety.csv"
        )
      end.to raise_error(FastlaneCore::UIError, /not found/)
    end

    it "raises for an empty CSV (would wipe the form)" do
      with_tmpdir do |dir|
        path = write_file(File.join(dir, "data_safety.csv"), "   \n")
        publisher = double("publisher")
        expect(publisher).not_to receive(:data_application_safety)

        expect do
          described_class.upload_data_safety!(
            publisher: publisher,
            request_class: FakeSafetyRequest,
            package_name: "com.example.app",
            csv_path: path
          )
        end.to raise_error(FastlaneCore::UIError, /empty/)
      end
    end

    it "POSTs the CSV content and returns line/byte stats" do
      with_tmpdir do |dir|
        csv = "Question ID,Response ID,Response value\nPSL_X,,TRUE\n"
        path = write_file(File.join(dir, "data_safety.csv"), csv)

        captured = nil
        publisher = double("publisher")
        expect(publisher).to receive(:data_application_safety) do |package_name, request|
          expect(package_name).to eq("com.example.app")
          captured = request
        end

        stats = described_class.upload_data_safety!(
          publisher: publisher,
          request_class: FakeSafetyRequest,
          package_name: "com.example.app",
          csv_path: path
        )

        expect(captured.safety_labels).to eq(csv)
        expect(stats).to eq(lines: 2, bytes: csv.bytesize)
      end
    end
  end

  describe "MANUAL_CONSOLE_ITEMS / .manual_checklist_lines" do
    it "lists exactly 9 console-only items with the privacy policy URL first" do
      expect(described_class::MANUAL_CONSOLE_ITEMS.size).to eq(9)
      expect(described_class::MANUAL_CONSOLE_ITEMS.first).to match(/privacy policy/i)
    end

    it "renders a :sep divider, all 9 numbered items, and the precondition note" do
      lines = described_class.manual_checklist_lines

      expect(lines.first).to eq(:sep)
      numbered = lines.grep(String).select { |l| l =~ /\A\s+\d+\)/ }
      expect(numbered.size).to eq(9)
      expect(numbered.first).to match(/1\).*privacy policy/i)
      expect(lines.last).to match(/Play Console'da önceden oluşturulmuş/)
    end
  end
end
