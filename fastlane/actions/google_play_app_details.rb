module Fastlane
  module Actions
    # Custom action that reads/updates the Play Console "contact details"
    # (edits.details: contactEmail / contactPhone / contactWebsite /
    # defaultLanguage). supply has NO surface for edits.details — the stock
    # fastlane gem can neither read nor write it — so this action drives the
    # raw AndroidPublisherService exposed by `Supply::Client#client`, while
    # reusing supply's auth/edit lifecycle (make_from_config, begin_edit,
    # commit_current_edit! with its built-in changesNotSentForReview rescue).
    #
    # Modes:
    #   - No setter field provided (or nothing differs from Play) → pure GET:
    #     the edit is aborted, nothing is written. Used as the read path by
    #     the `download_store_listing` contact-files pull.
    #   - validate_only:true → validate the edit, then abort (no commit).
    #   - Otherwise → PATCH only the changed fields + commit.
    #
    # The GET → diff → PATCH logic is pure and lives in
    # PlaySetupHelpers.apply_app_details! (spec-able with doubles).
    class GooglePlayAppDetailsAction < Action
      # Supply::Options keys reused verbatim (auth + edit-commit behaviour).
      SUPPLY_OPTIONS = [
        :package_name,
        :key,
        :issuer,
        :json_key,
        :json_key_data,
        :root_url,
        :timeout,
        :validate_only,
        :changes_not_sent_for_review,
        :rescue_changes_not_sent_for_review
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
        # fastlane installs) predate the edits.details methods.
        unless publisher.respond_to?(:get_edit_detail) && publisher.respond_to?(:patch_edit_detail)
          UI.user_error!(
            "This fastlane installation's google-apis-androidpublisher_v3 gem does not " \
            "expose edits.details (get_edit_detail/patch_edit_detail). Upgrade fastlane " \
            "(`brew upgrade fastlane` or `gem update fastlane`) and retry."
          )
        end

        desired = {
          contact_email: params[:contact_email],
          contact_phone: params[:contact_phone],
          contact_website: params[:contact_website],
          default_language: params[:default_language]
        }.reject { |_field, value| value.to_s.strip.empty? }
        desired = desired.transform_values { |value| value.to_s.strip }

        client.begin_edit(package_name: params[:package_name])
        begin
          # An unknown defaultLanguage is rejected by the API with an opaque
          # error — pre-validate against the locales actually on the listing.
          if desired.key?(:default_language)
            locales = client.listings.map(&:language)
            PlaySetupHelpers.ensure_default_language_listed!(
              default_language: desired[:default_language],
              listed_locales: locales
            )
          end

          result = PlaySetupHelpers.apply_app_details!(
            publisher: publisher,
            details_class: AndroidPublisher::AppDetails,
            package_name: params[:package_name],
            edit_id: client.current_edit.id,
            desired: desired
          )

          if !result[:patched]
            client.abort_current_edit
            result[:mode] = "read-only (değişiklik yok)"
            UI.message("ℹ️ Play Console contact details already up to date — nothing committed.")
          elsif params[:validate_only]
            client.validate_current_edit!
            client.abort_current_edit
            result[:mode] = "validate_only (commit edilmedi)"
            UI.important("🔍 validate_only — changes validated but NOT committed: #{result[:changes].keys.join(', ')}")
          else
            client.commit_current_edit!
            result[:mode] = "commit"
            UI.success("✅ Play Console contact details updated: #{result[:changes].keys.join(', ')}")
          end

          result
        rescue Google::Apis::Error => e
          abort_edit_quietly(client)
          UI.user_error!(
            "Google Play app-details update failed: #{e.message}. " \
            "A 403 usually means the service account lacks app-access / store-settings " \
            "permissions in Play Console → Users and permissions."
          )
        rescue StandardError
          abort_edit_quietly(client)
          raise
        end
      end

      # Aborting a dangling edit is best-effort cleanup — never let it mask
      # the original error.
      def self.abort_edit_quietly(client)
        client.abort_current_edit if client.current_edit
      rescue StandardError
        nil
      end

      def self.description
        "Reads/updates Play Console contact details (edits.details) — email, phone, website, default language"
      end

      def self.available_options
        require 'supply'
        require 'supply/options'

        supply_options = Supply::Options.available_options.select do |option|
          SUPPLY_OPTIONS.include?(option.key)
        end

        # NOTE: deliberately NO env_name on the setter fields. The lanes
        # resolve option → ANDROID_CONTACT_* env → metadata-root file
        # themselves (PlaySetupHelpers.resolve_contact_details); wiring env
        # pickup here too would make the read-only mode (no setter fields
        # passed) silently start writing whenever the env vars are set.
        custom_options = [
          FastlaneCore::ConfigItem.new(
            key: :contact_email,
            description: "Play Console contact email (leave unset to keep the current value)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :contact_phone,
            description: "Play Console contact phone (leave unset to keep the current value)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :contact_website,
            description: "Play Console contact website (leave unset to keep the current value)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :default_language,
            description: "Play Console default language in BCP-47 (e.g. en-US); validated against the listing's locales",
            optional: true,
            type: String
          )
        ]

        supply_options + custom_options
      end

      def self.return_value
        "Hash with :current_values, :changes ({field => {from:, to:}}), :patched, and :mode"
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
