# frozen_string_literal: true

require "tmpdir"

RSpec.describe CLIDownloader::Fetcher do
  FakeSuccessResponse = Struct.new(:code, :body) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end

    def [](_key)
      nil
    end
  end

  FakeTypedSuccessResponse = Struct.new(:code, :body, :content_type) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end

    def [](key)
      return content_type if key.downcase == "content-type"

      nil
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

  FakeRedirectResponse = Struct.new(:code, :location) do
    def is_a?(klass)
      klass == Net::HTTPRedirection || super
    end

    def [](key)
      return location if key.downcase == "location"

      nil
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

  it "adds an mp3 extension from HTTP content type" do
    fetcher = described_class.new(output_directory: @workspace)
    response = FakeTypedSuccessResponse.new("200", "audio-bytes", "audio/mpeg")
    http = instance_double(Net::HTTP)

    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(http)

    result = fetcher.download("https://example.com/song/72911331")

    expect(result.file_path).to eq(File.join(@workspace, "72911331.mp3"))
    expect(File.binread(result.file_path)).to eq("audio-bytes")
  end

  it "extracts an mp3 link when HTTP response is an HTML page" do
    fetcher = described_class.new(output_directory: @workspace)
    page = FakeTypedSuccessResponse.new(
      "200",
      '<a href="/get/music/20210416/song.mp3">download</a>',
      "text/html"
    )
    response = FakeTypedSuccessResponse.new("200", "audio-bytes", "audio/mpeg")
    first_http = instance_double(Net::HTTP)
    second_http = instance_double(Net::HTTP)

    allow(first_http).to receive(:request).and_return(page)
    allow(second_http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(first_http)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(second_http)

    result = fetcher.download("https://example.com/song/72911331")

    expect(result.file_path).to eq(File.join(@workspace, "72911331.mp3"))
    expect(File.binread(result.file_path)).to eq("audio-bytes")
  end

  it "follows HTTP redirects" do
    fetcher = described_class.new(output_directory: @workspace)
    redirect = FakeRedirectResponse.new("302", "https://cdn.example.com/media/song.mp3")
    response = FakeSuccessResponse.new("200", "audio-bytes")
    first_http = instance_double(Net::HTTP)
    second_http = instance_double(Net::HTTP)

    allow(first_http).to receive(:request).and_return(redirect)
    allow(second_http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).with("example.com", 443, use_ssl: true).and_yield(first_http)
    allow(Net::HTTP).to receive(:start).with("cdn.example.com", 443, use_ssl: true).and_yield(second_http)

    result = fetcher.download("https://example.com/get/music/song.mp3")

    expect(result.file_path).to eq(File.join(@workspace, "song.mp3"))
    expect(File.binread(result.file_path)).to eq("audio-bytes")
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
