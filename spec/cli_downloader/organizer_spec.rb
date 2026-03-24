# frozen_string_literal: true

require "tmpdir"

RSpec.describe CLIDownloader::Organizer do
  around do |example|
    Dir.mktmpdir("cli_downloader") do |directory|
      @workspace = directory
      example.run
    end
  end

  it "organizes a file by directory and filename templates" do
    downloads_dir = File.join(@workspace, "downloads")
    library_dir = File.join(@workspace, "library")
    FileUtils.mkdir_p(downloads_dir)

    source_path = File.join(downloads_dir, "raw_song.mp3")
    File.write(source_path, "binary-data")

    organizer = described_class.new(base_directory: library_dir)

    result = organizer.organize(
      source_path: source_path,
      metadata: {
        artist: "Daft Punk",
        album: "Discovery",
        year: 2001,
        title: "Harder Better Faster Stronger"
      }
    )

    expect(result.destination_path).to eq(
      File.join(library_dir, "music", "Daft Punk", "Discovery", "2001 - Harder Better Faster Stronger.mp3")
    )
    expect(File.exist?(result.destination_path)).to be(true)
    expect(File.exist?(source_path)).to be(false)
    expect(result.created_directories).to include(
      File.join(library_dir, "music"),
      File.join(library_dir, "music", "Daft Punk"),
      File.join(library_dir, "music", "Daft Punk", "Discovery")
    )
  end

  it "sanitizes unsafe symbols and fills fallback values" do
    source_path = File.join(@workspace, "cover.jpg")
    File.write(source_path, "image")

    organizer = described_class.new(base_directory: File.join(@workspace, "sorted"))

    result = organizer.organize(
      source_path: source_path,
      metadata: {
        artist: "AC/DC",
        album: "Hits: 2024",
        title: "Summer?Cover"
      }
    )

    expect(result.destination_path).to eq(
      File.join(@workspace, "sorted", "images", "AC DC", "Hits 2024", "Unknown - Summer Cover.jpg")
    )
  end

  it "adds a suffix when file names collide" do
    source_path = File.join(@workspace, "clip.mp4")
    File.write(source_path, "video")

    base_directory = File.join(@workspace, "videos")
    existing_directory = File.join(base_directory, "videos", "Unknown", "Unknown")
    FileUtils.mkdir_p(existing_directory)
    File.write(File.join(existing_directory, "2024 - Trailer.mp4"), "existing")

    organizer = described_class.new(base_directory: base_directory)

    result = organizer.organize(
      source_path: source_path,
      metadata: {
        year: 2024,
        title: "Trailer"
      }
    )

    expect(result.destination_path).to eq(
      File.join(existing_directory, "2024 - Trailer (1).mp4")
    )
  end

  it "supports preview without moving the file" do
    source_path = File.join(@workspace, "track.flac")
    File.write(source_path, "audio")

    organizer = described_class.new(
      base_directory: File.join(@workspace, "collection"),
      directory_template: "%{artist}/%{album}",
      filename_template: "%{title}"
    )

    preview = organizer.preview(
      source_path: source_path,
      metadata: {
        artist: "Massive Attack",
        album: "Mezzanine",
        title: "Teardrop"
      }
    )

    expect(preview).to eq(
      File.join(@workspace, "collection", "Massive Attack", "Mezzanine", "Teardrop.flac")
    )
    expect(File.exist?(source_path)).to be(true)
  end
end
