module Fastlane
  module Actions
    # Custom action that exposes the full TrackRelease list for a Google Play
    # track. The stock fastlane gem only ships `google_play_track_release_names`
    # and `google_play_track_version_codes`, which return the two arrays
    # separately and cannot be paired reliably. This action returns hashes with
    # both `:name` and `:version_codes` so callers can map a release name to
    # its build numbers.
    class GooglePlayTrackReleasesAction < Action
      OPTIONS = [
        :package_name,
        :track,
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

        Supply.config = params

        client = Supply::Client.make_from_config
        client.begin_edit(package_name: params[:package_name])
        releases = client.track_releases(params[:track]) || []
        client.abort_current_edit

        releases.map do |release|
          {
            name: release.respond_to?(:name) ? release.name : nil,
            status: release.respond_to?(:status) ? release.status : nil,
            version_codes: Array(
              release.respond_to?(:version_codes) ? release.version_codes : nil
            ).map(&:to_i)
          }
        end
      end

      def self.description
        "Retrieves full release info (name + version_codes) for a Google Play track"
      end

      def self.available_options
        require 'supply'
        require 'supply/options'

        Supply::Options.available_options.select { |option| OPTIONS.include?(option.key) }
      end

      def self.return_value
        "Array of hashes with :name, :status, and :version_codes for each release in the track"
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
