# frozen_string_literal: true

require "fileutils"
require "net/http"
require "open3"
require "pathname"
require "uri"

module CLIDownloader
  class Fetcher
    YOUTUBE_HOSTS = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"].freeze
    SOUNDCLOUD_HOSTS = ["soundcloud.com", "www.soundcloud.com", "m.soundcloud.com"].freeze
    REMOTE_STRATEGY_HOSTS = (YOUTUBE_HOSTS + SOUNDCLOUD_HOSTS).freeze
    DEFAULT_OUTPUT_TEMPLATE = "%(title)s.%(ext)s"

    Result = Struct.new(:source_url, :file_path, :strategy, :stdout, :stderr, keyword_init: true) do
      def filename
        File.basename(file_path)
      end
    end

    class FetcherError < Error; end
    class InvalidURLError < FetcherError; end
    class DownloadFailedError < FetcherError
      attr_reader :exit_status

      def initialize(message, exit_status: nil)
        @exit_status = exit_status
        super(message)
      end
    end

    class MissingDependencyError < FetcherError; end

    def initialize(output_directory: Dir.pwd, yt_dlp_bin: "yt-dlp", runner: Open3)
      @output_directory = prepare_output_directory(output_directory)
      @yt_dlp_bin = yt_dlp_bin
      @runner = runner
    end

    def download(url, filename: nil, output_template: DEFAULT_OUTPUT_TEMPLATE, force_strategy: nil, headers: {})
      uri = parse_url(url)
      strategy = pick_strategy(uri, force_strategy)

      case strategy
      when :yt_dlp
        download_with_yt_dlp(uri, filename: filename, output_template: output_template)
      when :http
        download_with_http(uri, filename: filename, headers: headers)
      else
        raise FetcherError, "unsupported strategy: #{strategy.inspect}"
      end
    end

    private

    attr_reader :output_directory, :yt_dlp_bin, :runner

    def prepare_output_directory(path)
      normalized = path.to_s.strip
      raise FetcherError, "output_directory can't be empty" if normalized.empty?

      expanded = File.expand_path(normalized)
      FileUtils.mkdir_p(expanded)
      expanded
    end

    def parse_url(url)
      raw = url.to_s.strip
      raise InvalidURLError, "url can't be empty" if raw.empty?

      uri = URI.parse(raw)
      raise InvalidURLError, "unsupported URL format: #{raw}" unless uri.is_a?(URI::HTTP) && uri.host

      uri
    rescue URI::InvalidURIError
      raise InvalidURLError, "invalid URL: #{raw}"
    end

    def pick_strategy(uri, force_strategy)
      return normalize_strategy(force_strategy) if force_strategy
      return :yt_dlp if yt_dlp_source?(uri)

      :http
    end

    def normalize_strategy(strategy)
      normalized = strategy.to_sym
      return normalized if %i[yt_dlp http].include?(normalized)

      raise FetcherError, "unsupported strategy override: #{strategy.inspect}"
    end

    def yt_dlp_source?(uri)
      host = uri.host.to_s.downcase
      REMOTE_STRATEGY_HOSTS.any? do |supported_host|
        host == supported_host || host.end_with?(".#{supported_host}")
      end
    end

    def download_with_yt_dlp(uri, filename:, output_template:)
      output_value = filename && !filename.strip.empty? ? filename.strip : output_template
      output_path_template = File.join(output_directory, output_value)

      command = [
        yt_dlp_bin,
        "--no-playlist",
        "--restrict-filenames",
        "--print", "after_move:filepath",
        "-o", output_path_template,
        uri.to_s
      ]

      stdout, stderr, status = runner.capture3(*command)
      unless status.success?
        raise DownloadFailedError.new(
          "yt-dlp failed with status #{status.exitstatus}: #{stderr.to_s.strip}",
          exit_status: status.exitstatus
        )
      end

      file_path = detect_yt_dlp_path(stdout, stderr)
      file_path = File.expand_path(file_path, output_directory) unless Pathname.new(file_path).absolute?

      Result.new(
        source_url: uri.to_s,
        file_path: file_path,
        strategy: :yt_dlp,
        stdout: stdout,
        stderr: stderr
      )
    rescue Errno::ENOENT
      raise MissingDependencyError, "yt-dlp executable not found: #{yt_dlp_bin}"
    end

    def download_with_http(uri, filename:, headers: {})
      target_filename = normalized_filename(filename) || infer_filename_from_uri(uri)
      destination = File.join(output_directory, target_filename)

      response_body = nil
      response_code = nil

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        headers.each { |key, value| request[key] = value.to_s }

        response = http.request(request)
        response_code = response.code.to_i

        unless response.is_a?(Net::HTTPSuccess)
          raise DownloadFailedError.new(
            "http download failed with status #{response.code} for #{uri}",
            exit_status: response_code
          )
        end

        response_body = response.body
      end

      File.binwrite(destination, response_body.to_s)

      Result.new(
        source_url: uri.to_s,
        file_path: destination,
        strategy: :http,
        stdout: "",
        stderr: ""
      )
    rescue SocketError, IOError, SystemCallError => e
      raise DownloadFailedError, "http download failed: #{e.message}"
    end

    def detect_yt_dlp_path(stdout, stderr)
      candidates = []
      candidates.concat(parse_ytdlp_destination_lines(stdout))
      candidates.concat(parse_ytdlp_destination_lines(stderr))

      path = candidates.reverse.find { |value| !value.to_s.strip.empty? }
      raise DownloadFailedError, "yt-dlp did not report downloaded file path" unless path

      path
    end

    def parse_ytdlp_destination_lines(output)
      output.to_s.each_line.filter_map do |line|
        stripped = line.strip
        next if stripped.empty?

        if stripped.start_with?("[download] Destination:")
          stripped.split(":", 2).last.to_s.strip
        elsif stripped.start_with?("[download]") && stripped.include?("has already been downloaded")
          stripped.split("has already been downloaded", 2).last.to_s.strip
        elsif stripped.start_with?("/") || stripped.match?(%r{^[A-Za-z]:[\\/]})
          stripped
        end
      end
    end

    def normalized_filename(filename)
      return nil if filename.nil?

      value = filename.to_s.strip
      return nil if value.empty?

      File.basename(value)
    end

    def infer_filename_from_uri(uri)
      basename = File.basename(uri.path.to_s)
      return basename unless basename.nil? || basename.empty? || basename == "/"

      "downloaded_file"
    end
  end
end
