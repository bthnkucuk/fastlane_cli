# frozen_string_literal: true

# Specs for the Crashlytics symbol-upload auto-discovery helpers added in
# v0.8.0: resolve_upload_symbols_script / resolve_google_service_info_plist.
#
# All examples are hermetic — the DerivedData root and the per-user cache root
# are injected as temp dirs, and the app root is a temp dir, so no real
# `~/Library` access ever happens.

RSpec.describe "FastlaneCliConfig Crashlytics discovery" do
  TRACKED_CRASHLYTICS_ENV_KEYS = %w[
    FASTLANE_ROOT FASTLANE_DIRECTORY APP_FASTLANE_PATH
    FASTLANE_APP_ROOT APP_ROOT
    FASTLANE_FLAVOR APP_FLAVOR FLAVOR
    IOS_UPLOAD_SYMBOLS_SCRIPT IOS_GOOGLE_SERVICE_INFO_PLIST
    BUNDLE_GEMFILE
  ].freeze

  around(:each) do |ex|
    saved = TRACKED_CRASHLYTICS_ENV_KEYS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    TRACKED_CRASHLYTICS_ENV_KEYS.each { |k| ENV.delete(k) }
    begin
      ex.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  # Make an executable upload-symbols stub at `path`, with optional mtime.
  def make_binary(path, mtime: nil)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\necho upload-symbols\n")
    FileUtils.chmod(0o755, path)
    File.utime(mtime, mtime, path) if mtime
    path
  end

  describe ".resolve_upload_symbols_script" do
    it "prefers an explicit override when the file exists" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        override = make_binary(File.join(app_root, "custom/upload-symbols"))
        # Also put a Pods copy to prove the override wins over it.
        make_binary(File.join(app_root, "ios/Pods/FirebaseCrashlytics/upload-symbols"))

        result = FastlaneCliConfig.resolve_upload_symbols_script(
          { upload_symbols_script: "custom/upload-symbols" }
        )
        expect(result).to eq(override)
      end
    end

    it "honours the IOS_UPLOAD_SYMBOLS_SCRIPT env var as an override" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        override = make_binary(File.join(app_root, "env-symbols"))
        ENV["IOS_UPLOAD_SYMBOLS_SCRIPT"] = "env-symbols"

        expect(FastlaneCliConfig.resolve_upload_symbols_script({})).to eq(override)
      end
    end

    it "skips a non-existent explicit override and falls through to Pods" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        pods = make_binary(File.join(app_root, "ios/Pods/FirebaseCrashlytics/upload-symbols"))

        result = FastlaneCliConfig.resolve_upload_symbols_script(
          { upload_symbols_script: "does/not/exist" }
        )
        expect(result).to eq(pods)
      end
    end

    it "finds the CocoaPods Firebase binary" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        pods = make_binary(File.join(app_root, "ios/Pods/FirebaseCrashlytics/upload-symbols"))

        expect(FastlaneCliConfig.resolve_upload_symbols_script({})).to eq(pods)
      end
    end

    it "globs DerivedData and picks the most-recently-modified SwiftPM match" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          with_tmpdir do |cache_root|
            ENV["FASTLANE_APP_ROOT"] = app_root

            old_glob = "Runner-aaa/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            new_glob = "Runner-bbb/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            old_path = make_binary(File.join(dd_root, old_glob), mtime: Time.now - 3600)
            new_path = make_binary(File.join(dd_root, new_glob), mtime: Time.now)

            result = FastlaneCliConfig.resolve_upload_symbols_script(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )

            # It returns the CACHED copy, not the DerivedData path directly.
            cached = File.join(cache_root, "upload-symbols")
            expect(result).to eq(cached)
            # Cached content matches the NEWEST DerivedData binary.
            expect(File.read(result)).to eq(File.read(new_path))
            expect(File.read(result)).not_to eq("#{File.read(old_path)}X")
          end
        end
      end
    end

    it "copies the SwiftPM binary into the cache on first discovery" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          with_tmpdir do |cache_root|
            ENV["FASTLANE_APP_ROOT"] = app_root
            glob = "Runner-x/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            make_binary(File.join(dd_root, glob))

            cached = File.join(cache_root, "upload-symbols")
            expect(File.exist?(cached)).to be false

            result = FastlaneCliConfig.resolve_upload_symbols_script(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )
            expect(result).to eq(cached)
            expect(File.exist?(cached)).to be true
            expect(File.executable?(cached)).to be true
          end
        end
      end
    end

    it "reuses the cached copy without re-copying when it is fresh" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          with_tmpdir do |cache_root|
            ENV["FASTLANE_APP_ROOT"] = app_root
            glob = "Runner-x/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            discovered = make_binary(File.join(dd_root, glob), mtime: Time.now - 7200)

            cached = File.join(cache_root, "upload-symbols")
            FastlaneCliConfig.resolve_upload_symbols_script(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )
            first_mtime = File.mtime(cached)

            # Discovered binary is OLDER than the cache → no re-copy.
            FastlaneCliConfig.resolve_upload_symbols_script(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )
            expect(File.mtime(cached)).to eq(first_mtime)
            expect(discovered).to be_a(String)
          end
        end
      end
    end

    it "re-copies the cache when the discovered binary is newer (stale cache)" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          with_tmpdir do |cache_root|
            ENV["FASTLANE_APP_ROOT"] = app_root
            glob = "Runner-x/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            dd_path = File.join(dd_root, glob)

            cached = File.join(cache_root, "upload-symbols")
            FileUtils.mkdir_p(cache_root)
            File.write(cached, "OLD CONTENT")
            File.utime(Time.now - 7200, Time.now - 7200, cached)

            # Discovered binary is NEWER than the stale cache.
            make_binary(dd_path, mtime: Time.now)

            result = FastlaneCliConfig.resolve_upload_symbols_script(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )
            expect(result).to eq(cached)
            expect(File.read(cached)).to eq(File.read(dd_path))
            expect(File.read(cached)).not_to eq("OLD CONTENT")
          end
        end
      end
    end

    it "falls back to a vendored ios/scripts copy" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          ENV["FASTLANE_APP_ROOT"] = app_root
          vendored = make_binary(File.join(app_root, "ios/scripts/upload-symbols"))

          result = FastlaneCliConfig.resolve_upload_symbols_script(
            {}, derived_data_root: dd_root
          )
          expect(result).to eq(vendored)
        end
      end
    end

    it "returns nil when nothing exists anywhere" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          ENV["FASTLANE_APP_ROOT"] = app_root
          result = FastlaneCliConfig.resolve_upload_symbols_script(
            {}, derived_data_root: dd_root
          )
          expect(result).to be_nil
        end
      end
    end

    it "tolerates a missing DerivedData root and falls through to nil" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        result = FastlaneCliConfig.resolve_upload_symbols_script(
          {}, derived_data_root: "/no/such/derived/data/root"
        )
        expect(result).to be_nil
      end
    end

    it "tolerates a DerivedData root with zero matches" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          ENV["FASTLANE_APP_ROOT"] = app_root
          FileUtils.mkdir_p(File.join(dd_root, "Runner-x/Build"))
          result = FastlaneCliConfig.resolve_upload_symbols_script(
            {}, derived_data_root: dd_root
          )
          expect(result).to be_nil
        end
      end
    end
  end

  describe ".resolve_upload_symbols_script_with_source" do
    it "reports the explicit-override source" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        make_binary(File.join(app_root, "ovr"))
        result = FastlaneCliConfig.resolve_upload_symbols_script_with_source(
          { upload_symbols_script: "ovr" }
        )
        expect(result[:source]).to eq("explicit override")
      end
    end

    it "reports the CocoaPods source" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        make_binary(File.join(app_root, "ios/Pods/FirebaseCrashlytics/upload-symbols"))
        result = FastlaneCliConfig.resolve_upload_symbols_script_with_source({})
        expect(result[:source]).to eq("CocoaPods")
      end
    end

    it "reports the SwiftPM→cache source when caching succeeds" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          with_tmpdir do |cache_root|
            ENV["FASTLANE_APP_ROOT"] = app_root
            glob = "Runner-x/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
            make_binary(File.join(dd_root, glob))
            result = FastlaneCliConfig.resolve_upload_symbols_script_with_source(
              {}, derived_data_root: dd_root, cache_root: cache_root
            )
            expect(result[:source]).to eq("SwiftPM DerivedData → cache")
          end
        end
      end
    end

    it "reports 'bulunamadı' when nothing resolves" do
      with_tmpdir do |app_root|
        with_tmpdir do |dd_root|
          ENV["FASTLANE_APP_ROOT"] = app_root
          result = FastlaneCliConfig.resolve_upload_symbols_script_with_source(
            {}, derived_data_root: dd_root
          )
          expect(result[:path]).to be_nil
          expect(result[:source]).to eq("bulunamadı")
        end
      end
    end
  end

  describe ".cache_upload_symbols_binary" do
    it "falls back to the discovered path when the cache copy fails" do
      with_tmpdir do |dd_root|
        glob = "Runner-x/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
        discovered = make_binary(File.join(dd_root, glob))
        # An unwritable cache root forces FileUtils.cp to raise; helper must
        # swallow it and return the discovered path.
        result = FastlaneCliConfig.cache_upload_symbols_binary(
          discovered, "/proc/nonexistent/cannot/create"
        )
        expect(result).to eq(discovered)
      end
    end
  end

  describe ".resolve_google_service_info_plist" do
    def make_plist(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "<plist></plist>")
      path
    end

    it "prefers an explicit override when the file exists" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        override = make_plist(File.join(app_root, "config/GSP.plist"))
        make_plist(File.join(app_root, "ios/Runner/GoogleService-Info.plist"))

        result = FastlaneCliConfig.resolve_google_service_info_plist(
          { google_service_info_plist: "config/GSP.plist" }
        )
        expect(result).to eq(override)
      end
    end

    it "honours the IOS_GOOGLE_SERVICE_INFO_PLIST env var as an override" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        override = make_plist(File.join(app_root, "env-gsp.plist"))
        ENV["IOS_GOOGLE_SERVICE_INFO_PLIST"] = "env-gsp.plist"

        expect(FastlaneCliConfig.resolve_google_service_info_plist({})).to eq(override)
      end
    end

    it "skips a non-existent override and falls through to the Runner default" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        default = make_plist(File.join(app_root, "ios/Runner/GoogleService-Info.plist"))

        result = FastlaneCliConfig.resolve_google_service_info_plist(
          { google_service_info_plist: "missing.plist" }
        )
        expect(result).to eq(default)
      end
    end

    it "uses the flavor-convention path when a flavor resolves" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        allow(FastlaneCliConfig).to receive(:resolve_flavor).and_return("staging")
        flavor_plist = make_plist(
          File.join(app_root, "ios/flavors/staging/GoogleService-Info.plist")
        )
        # Runner default also present — flavor path must win.
        make_plist(File.join(app_root, "ios/Runner/GoogleService-Info.plist"))

        result = FastlaneCliConfig.resolve_google_service_info_plist({})
        expect(result).to eq(flavor_plist)
      end
    end

    it "falls back to the Runner default when the flavor path is absent" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        allow(FastlaneCliConfig).to receive(:resolve_flavor).and_return("staging")
        default = make_plist(File.join(app_root, "ios/Runner/GoogleService-Info.plist"))

        result = FastlaneCliConfig.resolve_google_service_info_plist({})
        expect(result).to eq(default)
      end
    end

    it "uses the Runner default for a single-flavor app (no flavor)" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        allow(FastlaneCliConfig).to receive(:resolve_flavor).and_return(nil)
        default = make_plist(File.join(app_root, "ios/Runner/GoogleService-Info.plist"))

        result = FastlaneCliConfig.resolve_google_service_info_plist({})
        expect(result).to eq(default)
      end
    end

    it "returns nil when no plist exists anywhere" do
      with_tmpdir do |app_root|
        ENV["FASTLANE_APP_ROOT"] = app_root
        allow(FastlaneCliConfig).to receive(:resolve_flavor).and_return(nil)
        expect(FastlaneCliConfig.resolve_google_service_info_plist({})).to be_nil
      end
    end
  end
end
