# frozen_string_literal: true

# Test bootstrap for fastlane_cli Ruby specs.
#
# These specs intentionally avoid loading the full `fastlane` gem (it's huge,
# slow to require, and would force the test group to depend on the production
# fastlane install). We stub out FastlaneCore::UI before requiring the files
# under test, then load common_helpers / storepilot_bridge selectively.

require "json"
require "tmpdir"
require "fileutils"
require "stringio"
require "webmock/rspec"

# Disable real network in specs — bridge HTTP code is stubbed via WebMock.
WebMock.disable_net_connect!(allow_localhost: false)

# --- Stub FastlaneCore::UI ---------------------------------------------------
# common_helpers.rb calls `FastlaneCore::UI.user_error!` and
# `FastlaneCore::UI.message` on resolution failures. We provide a thin double
# that raises a tagged error so specs can assert on it, without pulling in the
# real fastlane gem.

module FastlaneCore
  class UIError < StandardError; end

  module UI
    class << self
      attr_accessor :captured_messages

      def user_error!(message)
        raise UIError, message
      end

      def message(text)
        (@captured_messages ||= []) << text
      end

      def success(text)
        message(text)
      end

      def important(text)
        message(text)
      end

      def error(text)
        message(text)
      end

      def reset!
        @captured_messages = []
      end
    end
  end
end

RSPEC_ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(RSPEC_ROOT)

require_relative "../common_helpers"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    FastlaneCore::UI.reset!
  end
end

# Helper: build a throwaway directory tree for one example.
module FsHelpers
  def with_tmpdir
    Dir.mktmpdir("fastlane_cli_spec_") do |dir|
      yield dir
    end
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end
end

RSpec.configure { |c| c.include FsHelpers }
