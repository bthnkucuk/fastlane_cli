# frozen_string_literal: true

# Specs for fastlane/storepilot_bridge.rb.
#
# Constraint: storepilot_bridge.rb top-of-file requires `fastlane`, `spaceship`,
# `supply`, `googleauth` — none of which we want to load into the test bundle.
# Instead of requiring the file directly we extract its `StorePilotBridge`
# module by reading the source, stubbing the heavy requires, then evaling the
# rest. This is brittle on purpose: if someone moves things around at the top
# of the file, this spec will fail loudly and the diff will show why.

require "json"
require "base64"
require "net/http"

BRIDGE_PATH = File.expand_path("../storepilot_bridge.rb", __dir__)

# Stub gem-level requires by defining placeholder constants the bridge expects.
# The bridge itself touches Spaceship.Client.logger, Spaceship::ConnectAPI,
# Supply::Client, Google::Auth::ServiceAccountCredentials, Signet::AuthorizationError
# — we provide minimal scaffolding so the file parses, and per-example we
# stub the actual call sites with RSpec.
unless defined?(Spaceship)
  module Spaceship
    class Client
      def logger; @logger ||= Logger.new(File::NULL); end
    end
    module ConnectAPI
      class App
        def self.all(**_); []; end
        def self.get(app_id:); nil; end
      end
      class Token
        def self.create(**_); :stub_token; end
      end
      def self.token=(_); end
      module Platform
        IOS = :ios
      end
    end
  end
end

unless defined?(Supply)
  module Supply
    class Client
      def self.make_from_config(**_); new; end
      def begin_edit(**_); end
      def listings; []; end
      def tracks; []; end
      def current_edit; nil; end
      def abort_current_edit; end
      def fetch_images(**_); []; end
    end
  end
end

unless defined?(Google)
  module Google
    module Auth
      class ServiceAccountCredentials
        def self.make_creds(**_); new; end
        def fetch_access_token!; { "access_token" => "stub" }; end
      end
    end
  end
  module Signet
    class AuthorizationError < StandardError; end
  end
end

unless defined?(FastlaneCore)
  # Already defined by spec_helper, but the bridge doesn't depend on UI here.
end

# The bridge file calls `require "fastlane"` etc. Override Kernel#require for
# those names only, then load.
unless $LOAD_PATH_PATCHED_FOR_BRIDGE_SPEC
  $LOAD_PATH_PATCHED_FOR_BRIDGE_SPEC = true

  stubbed_libs = %w[bundler/setup fastlane spaceship supply googleauth]
  original_require = Kernel.instance_method(:require)
  Kernel.send(:define_method, :require) do |name|
    if stubbed_libs.include?(name.to_s)
      true
    else
      original_require.bind(self).call(name)
    end
  end

  # Suppress ENV writes the bridge does at top-of-file from clobbering test ENV.
  saved_env = ENV.to_h
  begin
    load BRIDGE_PATH
  ensure
    # Restore any env entries the bridge set if they weren't there before.
    bridge_keys = %w[
      FASTLANE_SKIP_UPDATE_CHECK FASTLANE_DISABLE_COLORS
      SPACESHIP_AVOID_XCODE_API BUNDLE_GEMFILE BUNDLE_PATH
      SPACESHIP_COOKIE_PATH SSL_CERT_FILE SSL_CERT_DIR
    ]
    bridge_keys.each do |k|
      if saved_env.key?(k)
        ENV[k] = saved_env[k]
      end
    end
  end
end

RSpec.describe StorePilotBridge do
  describe ".parse_combined_version" do
    it "splits 'X.Y.Z+N' into name + build" do
      out = described_class.parse_combined_version("1.4.2+57")
      expect(out).to eq(
        version_name: "1.4.2",
        build_number: "57",
        display_version: "1.4.2+57"
      )
    end

    it "handles no build number" do
      out = described_class.parse_combined_version("2.0.0")
      expect(out[:version_name]).to eq("2.0.0")
      expect(out[:build_number]).to be_nil
      expect(out[:display_version]).to eq("2.0.0")
    end

    it "returns nils for empty input" do
      out = described_class.parse_combined_version("")
      expect(out).to eq(version_name: nil, build_number: nil, display_version: nil)
    end

    it "handles 'X.Y.Z+' (trailing plus)" do
      out = described_class.parse_combined_version("1.0.0+")
      expect(out[:version_name]).to eq("1.0.0")
      expect(out[:build_number]).to be_nil
    end
  end

  describe ".bump_flutter_pubspec_build_number" do
    it "increments the build component and writes back" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.2.3+9\n")
        result = described_class.bump_flutter_pubspec_build_number(tmp)
        expect(result[:version_name]).to eq("1.2.3")
        expect(result[:build_number]).to eq("10")
        expect(result[:display_version]).to eq("1.2.3+10")
        expect(File.read(path)).to include("version: 1.2.3+10")
      end
    end

    it "starts a missing build number at 1 (X.Y.Z -> X.Y.Z+1)" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.2.3\n")
        result = described_class.bump_flutter_pubspec_build_number(tmp)
        expect(result[:build_number]).to eq("1")
        expect(File.read(path)).to include("version: 1.2.3+1")
      end
    end

    it "raises BridgeError when version line is absent" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\n")
        expect {
          described_class.bump_flutter_pubspec_build_number(tmp)
        }.to raise_error(StorePilotBridge::BridgeError, /version satiri/)
      end
    end

    it "raises BridgeError when version name is blank ('+5' only)" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: +5\n")
        expect {
          described_class.bump_flutter_pubspec_build_number(tmp)
        }.to raise_error(StorePilotBridge::BridgeError)
      end
    end

    it "raises BridgeError when the pubspec is missing entirely" do
      Dir.mktmpdir do |tmp|
        expect {
          described_class.bump_flutter_pubspec_build_number(tmp)
        }.to raise_error(StorePilotBridge::BridgeError, /pubspec\.yaml bulunamadi/)
      end
    end

    it "preserves the rest of the file untouched" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        original = <<~Y
          name: demo
          description: A test app.
          version: 0.5.0+12
          environment:
            sdk: ">=3.0.0 <4.0.0"
        Y
        File.write(path, original)
        described_class.bump_flutter_pubspec_build_number(tmp)
        body = File.read(path)
        expect(body).to include("name: demo")
        expect(body).to include("description: A test app.")
        expect(body).to include("version: 0.5.0+13")
        expect(body).to include("sdk:")
      end
    end

    it "matches a version line with an inline `# comment`" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.0.0+7 # bump for review\n")
        result = described_class.bump_flutter_pubspec_build_number(tmp)
        expect(result[:version_name]).to eq("1.0.0")
        expect(result[:build_number]).to eq("8")
        expect(result[:display_version]).to eq("1.0.0+8")
        expect(File.read(path)).to include("version: 1.0.0+8")
      end
    end

    it "matches a version line with no build number but an inline comment" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.0.0 # no build number\n")
        result = described_class.bump_flutter_pubspec_build_number(tmp)
        expect(result[:version_name]).to eq("1.0.0")
        expect(result[:build_number]).to eq("1")
        expect(File.read(path)).to include("version: 1.0.0+1")
      end
    end

    it "lets the inner BridgeError reach the caller without an outer prefix" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\n")
        expect {
          described_class.bump_flutter_pubspec_build_number(tmp)
        }.to raise_error(StorePilotBridge::BridgeError) do |err|
          # The inner message must reach the caller verbatim, without the
          # "Flutter version guncellenemedi: " wrapper.
          expect(err.message).to eq("pubspec.yaml icinde version satiri bulunamadi.")
          expect(err.message).not_to include("Flutter version guncellenemedi")
        end
      end
    end
  end

  describe ".read_flutter_pubspec_version" do
    it "returns empty data when file is missing" do
      out = described_class.read_flutter_pubspec_version("/nope/pubspec.yaml")
      expect(out).to eq(version_name: nil, build_number: nil, display_version: nil)
    end

    it "parses a normal version" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 3.4.5+99\n")
        out = described_class.read_flutter_pubspec_version(path)
        expect(out[:version_name]).to eq("3.4.5")
        expect(out[:build_number]).to eq("99")
      end
    end

    it "parses a version line with an inline `# comment`" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.0.0+7 # bump for review\n")
        out = described_class.read_flutter_pubspec_version(path)
        expect(out[:version_name]).to eq("1.0.0")
        expect(out[:build_number]).to eq("7")
        expect(out[:display_version]).to eq("1.0.0+7")
      end
    end

    it "parses a version line with no build number and a trailing comment" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: demo\nversion: 1.0.0 # no build number\n")
        out = described_class.read_flutter_pubspec_version(path)
        expect(out[:version_name]).to eq("1.0.0")
        expect(out[:build_number]).to be_nil
        expect(out[:display_version]).to eq("1.0.0")
      end
    end
  end

  describe ".read_pubspec_app_name" do
    it "returns nil for missing files" do
      expect(described_class.read_pubspec_app_name("/no/such")).to be_nil
    end

    it "extracts a simple name" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: example_app\nversion: 1.0.0+1\n")
        expect(described_class.read_pubspec_app_name(path)).to eq("example_app")
      end
    end

    it "extracts a double-quoted name" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, %(name: "my_app"\nversion: 1.0.0+1\n))
        expect(described_class.read_pubspec_app_name(path)).to eq("my_app")
      end
    end

    it "extracts a single-quoted name" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: 'my-app'\nversion: 1.0.0+1\n")
        expect(described_class.read_pubspec_app_name(path)).to eq("my-app")
      end
    end

    it "extracts a name with a trailing inline comment" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: example_app # internal slug\nversion: 1.0.0+1\n")
        expect(described_class.read_pubspec_app_name(path)).to eq("example_app")
      end
    end
  end

  describe ".bool_value" do
    it "passes booleans through" do
      expect(described_class.bool_value(true, default: false)).to be true
      expect(described_class.bool_value(false, default: true)).to be false
    end

    it "returns default for nil" do
      expect(described_class.bool_value(nil, default: true)).to be true
      expect(described_class.bool_value(nil, default: false)).to be false
    end

    it "parses common string truthies/falsies" do
      %w[1 true yes y on].each { |v| expect(described_class.bool_value(v, default: false)).to be true }
      %w[0 false no n off].each { |v| expect(described_class.bool_value(v, default: true)).to be false }
    end

    it "returns the default for unknown strings" do
      expect(described_class.bool_value("maybe", default: true)).to be true
    end
  end

  describe ".normalize_google_token_uri" do
    it "returns the default for blank input" do
      expect(described_class.normalize_google_token_uri(""))
        .to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
      expect(described_class.normalize_google_token_uri(nil))
        .to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
    end

    it "passes oauth2.googleapis.com through" do
      uri = "https://oauth2.googleapis.com/token"
      expect(described_class.normalize_google_token_uri(uri)).to eq(uri)
    end

    it "rejects non-HTTPS schemes" do
      expect(described_class.normalize_google_token_uri("http://oauth2.googleapis.com/token"))
        .to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
    end

    it "rejects unknown hosts (SSRF protection)" do
      expect(described_class.normalize_google_token_uri("https://evil.example.com/token"))
        .to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
    end

    it "rejects malformed URIs" do
      expect(described_class.normalize_google_token_uri("ht!tp://broken"))
        .to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
    end
  end

  describe ".gradle_flavor_task_fragment" do
    it "PascalCases multi-word flavors" do
      expect(described_class.gradle_flavor_task_fragment("staging")).to eq("Staging")
      expect(described_class.gradle_flavor_task_fragment("staging_qa")).to eq("StagingQa")
      expect(described_class.gradle_flavor_task_fragment("staging-qa")).to eq("StagingQa")
    end

    it "handles empty input as empty fragment" do
      expect(described_class.gradle_flavor_task_fragment("")).to eq("")
    end
  end

  describe ".first_non_empty" do
    it "returns the first non-blank stringified value" do
      expect(described_class.first_non_empty([nil, "", "  ", "found"])).to eq("found")
    end

    it "returns nil when all values are blank" do
      expect(described_class.first_non_empty([nil, "", "  "])).to be_nil
    end
  end

  describe ".truncate" do
    it "compacts whitespace and trims to max" do
      expect(described_class.truncate("hello   world", max: 100)).to eq("hello world")
    end

    it "appends ellipsis when over max" do
      out = described_class.truncate("a" * 50, max: 10)
      expect(out).to eq("aaaaaaaaaa...")
    end
  end

  describe ".extract_map" do
    it "returns the nested hash when present" do
      out = described_class.extract_map({ "credential" => { "keyId" => "k" } }, "credential")
      expect(out).to eq("keyId" => "k")
    end

    it "returns {} when missing and allow_missing is true" do
      expect(described_class.extract_map({}, "credential", allow_missing: true)).to eq({})
    end

    it "raises BridgeError when value is not a hash" do
      expect {
        described_class.extract_map({ "credential" => "not a hash" }, "credential")
      }.to raise_error(StorePilotBridge::BridgeError, /map formatinda/)
    end
  end

  describe ".required_string" do
    it "returns the stripped value when present" do
      expect(described_class.required_string("  hello  ", name: "x")).to eq("hello")
    end

    it "raises with field name when blank" do
      expect {
        described_class.required_string("  ", name: "credential.keyId")
      }.to raise_error(StorePilotBridge::BridgeError, /credential\.keyId gerekli/)
    end
  end

  describe ".normalize_asc_state_chip" do
    it "maps known ASC states to short chips" do
      expect(described_class.normalize_asc_state_chip("READY_FOR_SALE")).to eq("PROD")
      expect(described_class.normalize_asc_state_chip("WAITING_FOR_REVIEW")).to eq("REVIEW")
      expect(described_class.normalize_asc_state_chip("REJECTED")).to eq("REJECTED")
    end

    it "humanises unknown states" do
      expect(described_class.normalize_asc_state_chip("SOME_OTHER_STATE")).to eq("SOME OTHER STATE")
    end
  end

  describe ".normalize_google_track_chip / .normalize_google_release_status_chip" do
    it "maps known tracks and statuses" do
      expect(described_class.normalize_google_track_chip("production")).to eq("PROD")
      expect(described_class.normalize_google_track_chip("internal")).to eq("INTERNAL")
      expect(described_class.normalize_google_release_status_chip("completed")).to eq("LIVE")
      expect(described_class.normalize_google_release_status_chip("inprogress")).to eq("ROLLOUT")
    end

    it "uppercases unknown values" do
      expect(described_class.normalize_google_track_chip("custom_track")).to eq("CUSTOM_TRACK")
    end
  end

  describe ".select_by_locale" do
    it "returns the first PREFERRED_LOCALES match" do
      collection = [
        OpenStruct_for_test("locale" => "de-DE"),
        OpenStruct_for_test("locale" => "tr-TR"),
        OpenStruct_for_test("locale" => "en-US")
      ]
      picked = described_class.select_by_locale(collection) { |item| item.locale }
      # PREFERRED is en-us, en-gb, tr-tr — en-US wins after normalization
      expect(picked.locale).to eq("en-US")
    end

    it "falls back to the first element when no preferred locale matches" do
      collection = [OpenStruct_for_test("locale" => "ja-JP"), OpenStruct_for_test("locale" => "fr-FR")]
      picked = described_class.select_by_locale(collection) { |item| item.locale }
      expect(picked.locale).to eq("ja-JP")
    end

    it "returns nil for empty input" do
      expect(described_class.select_by_locale([]) { |_| "x" }).to be_nil
    end
  end

  describe ".http_get" do
    it "returns the body on a 2xx response" do
      stub_request(:get, "https://itunes.apple.com/lookup?bundleId=com.example&country=us")
        .to_return(status: 200, body: '{"resultCount":0,"results":[]}', headers: { "Content-Type" => "application/json" })

      uri = URI("https://itunes.apple.com/lookup?bundleId=com.example&country=us")
      body = described_class.http_get(uri, headers: { "Accept" => "application/json" })
      expect(body).to include("resultCount")
    end

    it "raises BridgeError on non-2xx" do
      stub_request(:get, "https://itunes.apple.com/lookup?bundleId=fail&country=us")
        .to_return(status: 503, body: "server error")
      uri = URI("https://itunes.apple.com/lookup?bundleId=fail&country=us")
      expect {
        described_class.http_get(uri)
      }.to raise_error(StorePilotBridge::BridgeError, /HTTP 503/)
    end
  end

  describe ".fetch_public_ios_store_data" do
    it "returns shaped metadata when iTunes lookup succeeds" do
      response = {
        resultCount: 1,
        results: [
          {
            trackName: "Demo App",
            version: "1.5.2",
            description: "An example app.",
            artworkUrl512: "https://cdn/icon@2x.jpg",
            artworkUrl100: "https://cdn/icon.jpg",
            screenshotUrls: ["https://cdn/s1.jpg", "https://cdn/s1.jpg", "https://cdn/s2.jpg"]
          }
        ]
      }.to_json

      stub_request(:get, "https://itunes.apple.com/lookup")
        .with(query: { bundleId: "com.example.demo", country: "us" })
        .to_return(status: 200, body: response)

      out = described_class.fetch_public_ios_store_data("com.example.demo")
      expect(out["trackName"]).to eq("Demo App")
      expect(out["version"]).to eq("1.5.2")
      expect(out["iconUrl"]).to eq("https://cdn/icon@2x.jpg")
      expect(out["screenshotUrls"]).to eq(["https://cdn/s1.jpg", "https://cdn/s2.jpg"])
    end

    it "returns {} for blank bundle id" do
      expect(described_class.fetch_public_ios_store_data("")).to eq({})
      expect(described_class.fetch_public_ios_store_data(nil)).to eq({})
    end

    it "swallows HTTP/JSON errors and returns {}" do
      stub_request(:get, /itunes\.apple\.com/).to_return(status: 500, body: "boom")
      expect(described_class.fetch_public_ios_store_data("com.example.demo")).to eq({})
    end
  end

  describe ".fetch_google_play_icon" do
    it "extracts og:image content" do
      html = '<html><meta property="og:image" content="https://cdn.example/icon.png?a=1&amp;b=2"/></html>'
      stub_request(:get, /play\.google\.com/).to_return(status: 200, body: html)
      expect(described_class.fetch_google_play_icon("com.example.demo"))
        .to eq("https://cdn.example/icon.png?a=1&b=2")
    end

    it "returns nil when og:image missing" do
      stub_request(:get, /play\.google\.com/).to_return(status: 200, body: "<html></html>")
      expect(described_class.fetch_google_play_icon("com.example.demo")).to be_nil
    end

    it "returns nil for blank package name without hitting the network" do
      expect(described_class.fetch_google_play_icon("")).to be_nil
      expect(described_class.fetch_google_play_icon(nil)).to be_nil
    end
  end

  describe ".google_reporting_apps_search" do
    it "issues a GET with paging params and bearer auth" do
      stub_request(:get, "https://playdeveloperreporting.googleapis.com/v1beta1/apps:search?pageSize=200")
        .with(headers: { "Authorization" => "Bearer abc", "Accept" => "application/json" })
        .to_return(status: 200, body: { apps: [{ packageName: "com.example" }] }.to_json)

      out = described_class.google_reporting_apps_search(access_token: "abc", page_token: nil)
      expect(out["apps"]).to be_an(Array)
      expect(out["apps"].first["packageName"]).to eq("com.example")
    end

    it "includes pageToken when present" do
      stub_request(:get, "https://playdeveloperreporting.googleapis.com/v1beta1/apps:search?pageSize=200&pageToken=tok")
        .to_return(status: 200, body: '{"apps":[]}')
      described_class.google_reporting_apps_search(access_token: "x", page_token: "tok")
    end

    it "raises BridgeError on malformed JSON" do
      stub_request(:get, /playdeveloperreporting/)
        .to_return(status: 200, body: "{not json")
      expect {
        described_class.google_reporting_apps_search(access_token: "x", page_token: nil)
      }.to raise_error(StorePilotBridge::BridgeError, /parse edilemedi/)
    end
  end

  describe ".google_service_account_payload" do
    it "builds the canonical service-account hash" do
      credential = {
        "clientEmail" => "svc@proj.iam.gserviceaccount.com",
        "privateKeyPem" => "-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----\n",
        "projectId" => "proj"
      }
      out = described_class.google_service_account_payload(credential)
      expect(out["type"]).to eq("service_account")
      expect(out["client_email"]).to eq("svc@proj.iam.gserviceaccount.com")
      expect(out["project_id"]).to eq("proj")
      expect(out["token_uri"]).to eq(StorePilotBridge::DEFAULT_GOOGLE_TOKEN_URI)
    end

    it "raises BridgeError when client_email is missing" do
      expect {
        described_class.google_service_account_payload("privateKeyPem" => "x")
      }.to raise_error(StorePilotBridge::BridgeError, /clientEmail gerekli/)
    end

    it "accepts snake_case fields too" do
      out = described_class.google_service_account_payload(
        "client_email" => "x@y.iam",
        "private_key" => "k",
        "token_uri" => "https://oauth2.googleapis.com/token"
      )
      expect(out["client_email"]).to eq("x@y.iam")
      expect(out["token_uri"]).to eq("https://oauth2.googleapis.com/token")
    end
  end

  describe ".detect_project_flavors / .detect_android_flavors" do
    it "parses productFlavors blocks from build.gradle" do
      Dir.mktmpdir do |tmp|
        android_app = File.join(tmp, "app")
        FileUtils.mkdir_p(android_app)
        File.write(File.join(android_app, "build.gradle"), <<~G)
          android {
            productFlavors {
              dev { applicationIdSuffix ".dev" }
              staging { applicationIdSuffix ".staging" }
              production { }
            }
          }
        G
        out = described_class.detect_android_flavors(tmp)
        expect(out).to eq(%w[dev production staging])
      end
    end

    it "returns [] when there is no android root" do
      expect(described_class.detect_android_flavors(nil)).to eq([])
    end

    it "returns [] when productFlavors block is absent" do
      Dir.mktmpdir do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "app"))
        File.write(File.join(tmp, "app", "build.gradle"), "android { }\n")
        expect(described_class.detect_android_flavors(tmp)).to eq([])
      end
    end
  end

  describe ".flutter_project?" do
    it "returns true when pubspec mentions flutter:" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: x\nflutter:\n  uses-material-design: true\n")
        expect(described_class.flutter_project?(path)).to be true
      end
    end

    it "returns false when pubspec does not mention flutter:" do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, "pubspec.yaml")
        File.write(path, "name: x\n")
        expect(described_class.flutter_project?(path)).to be false
      end
    end

    it "returns false for a missing file" do
      expect(described_class.flutter_project?("/no/such")).to be false
    end
  end

  describe ".extract_named_block" do
    it "extracts the body inside a named gradle block" do
      content = <<~G
        android {
          defaultConfig { applicationId "com.example" }
          productFlavors {
            dev { }
            staging { }
          }
        }
      G
      block = described_class.extract_named_block(content, "productFlavors")
      expect(block).to include("dev")
      expect(block).to include("staging")
    end

    it "returns nil for missing blocks" do
      expect(described_class.extract_named_block("plain", "productFlavors")).to be_nil
    end
  end

  describe ".executable_on_path?" do
    it "returns false when PATH does not contain the binary" do
      original = ENV["PATH"]
      ENV["PATH"] = Dir.mktmpdir
      begin
        expect(described_class.executable_on_path?("definitely_not_a_real_binary_xyz123"))
          .to be false
      ensure
        ENV["PATH"] = original
      end
    end
  end

  describe ".read_plist_value" do
    it "does not raise NameError when Open3.capture3 itself raises" do
      # If Open3 raises BEFORE the multiple-assignment binds `stderr`, the
      # rescue must not reference an unbound local. Prior implementation
      # raised `NameError: undefined local variable or method 'stderr'`
      # in this scenario, masking the original error.
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
      expect {
        described_class.read_plist_value("/tmp/whatever.plist", "CFBundleVersion")
      }.not_to raise_error
      expect(described_class.read_plist_value("/tmp/whatever.plist", "CFBundleVersion"))
        .to be_nil
    end

    it "returns nil when PlistBuddy exits non-zero" do
      fake_status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_return(["", "Does Not Exist", fake_status])
      expect(described_class.read_plist_value("/tmp/whatever.plist", "Missing"))
        .to be_nil
    end

    it "returns the trimmed stdout when PlistBuddy succeeds" do
      fake_status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(["1.4.2\n", "", fake_status])
      expect(described_class.read_plist_value("/tmp/whatever.plist", "CFBundleShortVersionString"))
        .to eq("1.4.2")
    end
  end

  describe "run command dispatch" do
    it "raises BridgeError for unsupported commands" do
      expect {
        described_class.run("not_a_command", {})
      }.to raise_error(StorePilotBridge::BridgeError, /Unsupported command/)
    end
  end
end

# Lightweight stand-in for OpenStruct without requiring the gem.
def OpenStruct_for_test(attrs)
  Class.new do
    attrs.each do |k, v|
      define_method(k) { v }
    end
  end.new
end
