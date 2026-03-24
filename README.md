# CLI Downloader

CLI Downloader is a Ruby gem for downloading media and preparing files for further processing.

## Features

- `Fetcher`: downloads media from YouTube/SoundCloud through `yt-dlp` or direct URLs through HTTP.
- `Tagger`: writes and updates ID3v1 tags for MP3 files.
- `Organizer`: moves files into a predictable folder structure and safely renames files.
- `CLI`: command line entrypoint for quick downloads.

## Installation

```bash
bundle install
```

## Quick Start

### CLI mode

```bash
ruby exe/cli_downloader -o downloads https://youtu.be/dQw4w9WgXcQ
```

Options:

- `-o, --output DIR`: output directory for downloaded files.
- `-n, --name FILE`: custom output filename/template.
- `-s, --strategy STRATEGY`: force strategy (`http` or `yt_dlp`).
- `--header KEY:VALUE`: add HTTP headers for direct URL mode.

### Ruby API

```ruby
require "CLI_downloader"

fetcher = CLIDownloader::Fetcher.new(output_directory: "downloads")
result = fetcher.download("https://example.com/music/track.mp3")
puts result.file_path

tagger = CLIDownloader::Tagger.new
tagger.update(result.file_path, artist: "Artist", album: "Album", year: 2025)

organizer = CLIDownloader::Organizer.new(base_directory: "library")
organized = organizer.organize(source_path: result.file_path, metadata: {
  artist: "Artist",
  album: "Album",
  year: 2025,
  title: "Track"
})
puts organized.destination_path
```

## Running Tests

```bash
bundle exec rspec
```

## Notes

- `yt-dlp` must be installed and available in `PATH` for YouTube/SoundCloud downloads.
- Direct URL downloads work without `yt-dlp`.
