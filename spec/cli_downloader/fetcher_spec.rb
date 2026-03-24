# frozen_string_literal: true

require "tmpdir"

RSpec.describe CLIDownloader::Fetcher do
  FakeSuccessResponse = Struct.new(:code, :body) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  FakeErrorResponse = Struct.new(:code) do
    def is_a?(_klass)
      false
    end

    def body
      ""
    end
  end

  around do |example|
    Dir.mktmpdir("fetcher") do |directory|
      @workspace = directory
      example.run
    end
  end

  it "downloads YouTube links via yt-dlp strategy" do
    runner = double("runner")
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    downloaded_path = File.join(@workspace, "track.mp3")

    allow(runner).to receive(:capture3).and_return(["#{downloaded_path}\n", "", status])

    fetcher = described_class.new(output_directory: @workspace, runner: runner)
    result = fetcher.download("https://youtu.be/demo123")

    expect(runner).to have_received(:capture3).with(
      "yt-dlp",
      "--no-playlist",
      "--restrict-filenames",
      "--print",
      "after_move:filepath",
      "-o",
      File.join(@workspace, "%(title)s.%(ext)s"),
      "https://youtu.be/demo123"
    )
    expect(result.strategy).to eq(:yt_dlp)
    expect(result.file_path).to eq(downloaded_path)
    expect(result.filename).to eq("track.mp3")
  end

  it "downloads direct links via HTTP strategy" do
    fetcher = described_class.new(output_directory: @workspace)
    response = FakeSuccessResponse.new("200", "video-bytes")
    http = instance_double(Net::HTTP)

    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(http)

    result = fetcher.download("https://example.com/media/video.mp4")

    expect(result.strategy).to eq(:http)
    expect(result.file_path).to eq(File.join(@workspace, "video.mp4"))
    expect(File.binread(result.file_path)).to eq("video-bytes")
  end

  it "raises a clear error when yt-dlp is missing" do
    runner = double("runner")
    allow(runner).to receive(:capture3).and_raise(Errno::ENOENT, "No such file or directory")

    fetcher = described_class.new(output_directory: @workspace, runner: runner)

    expect do
      fetcher.download("https://soundcloud.com/example/track")
    end.to raise_error(CLIDownloader::Fetcher::MissingDependencyError, /yt-dlp executable not found/)
  end

  it "raises a download error for non-success HTTP responses" do
    fetcher = described_class.new(output_directory: @workspace)
    response = FakeErrorResponse.new("404")
    http = instance_double(Net::HTTP)

    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(http)

    expect do
      fetcher.download("https://example.com/file.mp3")
    end.to raise_error(CLIDownloader::Fetcher::DownloadFailedError, /status 404/)
  end

  it "validates URL format" do
    fetcher = described_class.new(output_directory: @workspace)

    expect do
      fetcher.download("not-a-url")
    end.to raise_error(CLIDownloader::Fetcher::InvalidURLError)
  end
end
