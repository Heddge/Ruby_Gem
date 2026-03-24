# frozen_string_literal: true

require_relative "CLI_downloader/version"

module CLIDownloader
  class Error < StandardError; end
end

require_relative "CLI_downloader/organizer"
