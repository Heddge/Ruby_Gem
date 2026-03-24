# frozen_string_literal: true

require "tmpdir"

RSpec.describe CLIDownloader::Tagger do
  around do |example|
    Dir.mktmpdir("cli_downloader_tagger") do |directory|
      @workspace = directory
      example.run
    end
  end

  it "writes tags and infers the title from the file name" do
    source_path = File.join(@workspace, "numb.mp3")
    File.binwrite(source_path, "binary-data")

    tagger = described_class.new

    expect(tagger.tag_present?(source_path)).to be(false)

    result = tagger.write(
      source_path,
      artist: "Linkin Park",
      album: "Meteora",
      year: 2003,
      comment: "demo"
    )

    expect(result).to eq(
      title: "numb",
      artist: "Linkin Park",
      album: "Meteora",
      year: "2003",
      comment: "demo"
    )
    expect(tagger.tag_present?(source_path)).to be(true)
  end

  it "updates existing tags while keeping the previous metadata" do
    source_path = File.join(@workspace, "track.mp3")
    File.binwrite(source_path, "binary-data")

    tagger = described_class.new
    tagger.write(
      source_path,
      artist: "Linkin Park",
      album: "Meteora",
      year: 2003
    )

    result = tagger.update(
      source_path,
      title: "Numb",
      track: 13,
      genre: "Rock",
      comment: "updated"
    )

    expect(result).to eq(
      title: "Numb",
      artist: "Linkin Park",
      album: "Meteora",
      year: "2003",
      comment: "updated",
      track: 13,
      genre: "Rock"
    )
  end

  it "returns an empty hash when the file has no tag yet" do
    source_path = File.join(@workspace, "untagged.mp3")
    File.binwrite(source_path, "binary-data")

    tagger = described_class.new

    expect(tagger.read(source_path)).to eq({})
  end

  it "raises an error for unsupported file formats" do
    source_path = File.join(@workspace, "cover.jpg")
    File.binwrite(source_path, "image-data")

    tagger = described_class.new

    expect do
      tagger.write(source_path, title: "Cover")
    end.to raise_error(CLIDownloader::Tagger::UnsupportedFormatError, /unsupported file format/)
  end

  it "raises an error for unsupported metadata keys" do
    source_path = File.join(@workspace, "song.mp3")
    File.binwrite(source_path, "binary-data")

    tagger = described_class.new

    expect do
      tagger.write(source_path, composer: "Unknown")
    end.to raise_error(CLIDownloader::Tagger::TaggerError, /unsupported metadata key/)
  end
end
