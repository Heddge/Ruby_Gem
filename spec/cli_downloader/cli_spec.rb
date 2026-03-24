# frozen_string_literal: true

require "stringio"

RSpec.describe CLIDownloader::CLI do
  it "prints downloaded path and returns success code" do
    fetcher = instance_double(CLIDownloader::Fetcher)
    fetcher_factory = class_double(CLIDownloader::Fetcher, new: fetcher)
    result = CLIDownloader::Fetcher::Result.new(
      source_url: "https://example.com/audio.mp3",
      file_path: "C:/tmp/audio.mp3",
      strategy: :http,
      stdout: "",
      stderr: ""
    )

    allow(fetcher).to receive(:download).and_return(result)

    out = StringIO.new
    err = StringIO.new

    exit_code = described_class.start(
      ["-o", "C:/tmp", "https://example.com/audio.mp3"],
      out: out,
      err: err,
      fetcher_factory: fetcher_factory
    )

    expect(exit_code).to eq(0)
    expect(out.string).to include("C:/tmp/audio.mp3")
    expect(err.string).to eq("")
    expect(fetcher).to have_received(:download).with(
      "https://example.com/audio.mp3",
      filename: nil,
      force_strategy: nil,
      headers: {}
    )
  end

  it "returns a parse error when url is missing" do
    out = StringIO.new
    err = StringIO.new

    exit_code = described_class.start([], out: out, err: err, fetcher_factory: CLIDownloader::Fetcher)

    expect(exit_code).to eq(1)
    expect(err.string).to include("missing argument: url")
  end

  it "returns non-zero code when fetcher fails" do
    fetcher = instance_double(CLIDownloader::Fetcher)
    fetcher_factory = class_double(CLIDownloader::Fetcher, new: fetcher)

    allow(fetcher).to receive(:download).and_raise(CLIDownloader::Fetcher::DownloadFailedError, "boom")

    out = StringIO.new
    err = StringIO.new

    exit_code = described_class.start(
      ["https://example.com/audio.mp3"],
      out: out,
      err: err,
      fetcher_factory: fetcher_factory
    )

    expect(exit_code).to eq(1)
    expect(err.string).to include("Download error: boom")
  end
end
