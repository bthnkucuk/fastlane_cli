module Fastlane
  module Actions
    # Custom action that uploads the Play Console "Data safety" form from a
    # Play-Console-format CSV via applications.dataSafety. supply has NO
    # surface for this endpoint, so this action drives the raw
    # AndroidPublisherService exposed by `Supply::Client#client` (auth reused
    # from supply's make_from_config).
    #
    # IMPORTANT semantics of the underlying API:
    #   - The POST REPLACES the ENTIRE Data safety form with the CSV content.
    #   - There is NO read/GET counterpart — the form cannot be pulled.
    # Callers must therefore treat this as a whole-form overwrite (the lanes
    # surface that warning in their summary boxes and the profile action is
    # flagged requires_confirmation).
    #
    # No edit lifecycle: applications.dataSafety is an app-level call, not an
    # edits.* call — there is nothing to begin/commit/abort.
    class GooglePlayDataSafetyAction < Action
      # Supply::Options keys reused verbatim (auth/transport only).
      SUPPLY_OPTIONS = [
        :package_name,
        :key,
        :issuer,
        :json_key,
        :json_key_data,
        :root_url,
        :timeout
      ].freeze

      def self.run(params)
        require 'supply'
        require 'supply/options'
        require 'supply/client'
        require_relative '../play_setup_helpers'

        Supply.config = params

        client = Supply::Client.make_from_config
        publisher = client.client

        # Older google-apis-androidpublisher_v3 gems (bundled with old
        # fastlane installs) predate applications.dataSafety.
        unless publisher.respond_to?(:data_application_safety)
          UI.user_error!(
            "This fastlane installation's google-apis-androidpublisher_v3 gem does not " \
            "support applications.dataSafety. Upgrade fastlane " \
            "(`brew upgrade fastlane` or `gem update fastlane`) and retry."
          )
        end

        begin
          stats = PlaySetupHelpers.upload_data_safety!(
            publisher: publisher,
            request_class: AndroidPublisher::SafetyLabelsUpdateRequest,
            package_name: params[:package_name],
            csv_path: params[:csv_path]
          )
          UI.success(
            "✅ Play Console Data safety form replaced from #{params[:csv_path]} " \
            "(#{stats[:lines]} lines, #{stats[:bytes]} bytes)"
          )
          stats
        rescue Google::Apis::Error => e
          # Google::Apis::ClientError / ServerError expose #status_code (the
          # raw HTTP status). Surface it so a 400 vs 403 is obvious at a
          # glance; omit the "(HTTP …)" part gracefully when unavailable.
          status = e.respond_to?(:status_code) ? e.status_code : nil
          http_part = status ? " (HTTP #{status})" : ""
          UI.user_error!(
            "Google Play Data safety upload failed#{http_part}: #{e.message}. " \
            "A 403 usually means the service account lacks app-content permissions in " \
            "Play Console → Users and permissions; a 400 usually means the CSV does not " \
            "match the Play Console Data safety export format."
          )
        end
      end

      def self.description
        "Uploads (REPLACES) the Play Console Data safety form from a Play-Console-format CSV"
      end

      def self.available_options
        require 'supply'
        require 'supply/options'

        supply_options = Supply::Options.available_options.select do |option|
          SUPPLY_OPTIONS.include?(option.key)
        end

        supply_options + [
          FastlaneCore::ConfigItem.new(
            key: :csv_path,
            description: "Path to the Data safety CSV (Play Console export format) — the whole form is replaced with it",
            optional: false,
            type: String
          )
        ]
      end

      def self.return_value
        "Hash with :lines and :bytes of the uploaded CSV"
      end

      def self.is_supported?(platform)
        platform == :android
      end

      def self.category
        :misc
      end
    end
  end
end
