# frozen_string_literal: true

require "optparse"

module CLIDownloader
  class CLI
    DEFAULT_OPTIONS = {
      output_directory: Dir.pwd,
      filename: nil,
      force_strategy: nil,
      headers: {}
    }.freeze

    def self.start(argv = ARGV, out: $stdout, err: $stderr, fetcher_factory: Fetcher)
      new(argv, out: out, err: err, fetcher_factory: fetcher_factory).start
    end

    def initialize(argv, out:, err:, fetcher_factory:)
      @argv = argv.dup
      @out = out
      @err = err
      @fetcher_factory = fetcher_factory
    end

    def start
      options = DEFAULT_OPTIONS.dup
      options[:headers] = {}
      parser = build_parser(options)
      parser.parse!(@argv)

      url = @argv.shift
      raise OptionParser::MissingArgument, "url" if url.nil? || url.strip.empty?

      fetcher = fetcher_factory.new(output_directory: options[:output_directory])
      result = fetcher.download(
        url,
        filename: options[:filename],
        force_strategy: options[:force_strategy],
        headers: options[:headers]
      )

      out.puts(result.file_path)
      0
    rescue OptionParser::ParseError => e
      err.puts(e.message)
      err.puts(parser_usage)
      1
    rescue Fetcher::FetcherError => e
      err.puts("Download error: #{e.message}")
      1
    end

    private

    attr_reader :out, :err, :fetcher_factory

    def build_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: cli_downloader [options] URL"

        parser.on("-o", "--output DIR", "Directory for downloaded files") do |value|
          options[:output_directory] = value
        end

        parser.on("-n", "--name FILE", "Custom output name (for direct URL or yt-dlp template)") do |value|
          options[:filename] = value
        end

        parser.on("-s", "--strategy STRATEGY", "Force strategy: http or yt_dlp") do |value|
          options[:force_strategy] = value.to_sym
        end

        parser.on("--header KEY:VALUE", "Add HTTP header (for direct URL mode)") do |pair|
          key, value = pair.split(":", 2).map { |part| part&.strip }
          raise OptionParser::InvalidArgument, "header must be KEY:VALUE" if key.to_s.empty? || value.to_s.empty?

          options[:headers][key] = value
        end

        parser.on("-h", "--help", "Show help") do
          out.puts(parser)
          throw :help_requested
        end
      end
    end

    def parser_usage
      "Use --help to see CLI options"
    end
  end
end
