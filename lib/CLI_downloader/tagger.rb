# frozen_string_literal: true

module CLIDownloader
  class Tagger
    class TaggerError < StandardError; end
    class UnsupportedFormatError < TaggerError; end

    TAG_SIGNATURE = "TAG"
    TAG_SIZE = 128
    TEXT_ENCODING = Encoding::ISO_8859_1
    SUPPORTED_EXTENSIONS = [".mp3"].freeze
    METADATA_KEYS = %i[title artist album year comment track genre].freeze
    GENRES = [
      "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
      "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
      "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
      "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient",
      "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical",
      "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
      "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative",
      "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave",
      "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream",
      "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40", "Christian Rap",
      "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
      "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal",
      "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll",
      "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion",
      "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
      "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock",
      "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour",
      "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony",
      "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam", "Club",
      "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul",
      "Freestyle", "Duet", "Punk Rock", "Drum Solo", "A capella",
      "Euro-House", "Dance Hall"
    ].freeze

    def tag(file_path, metadata = {})
      write(file_path, metadata)
    end

    def write(file_path, metadata = {})
      path = validate_file!(file_path)
      data = normalize_metadata(metadata)
      data[:title] = default_title(path) unless data.key?(:title)

      write_tag(path, data)
      read(path)
    end

    def update(file_path, metadata = {})
      path = validate_file!(file_path)
      merged_data = read(path).merge(normalize_metadata(metadata))
      merged_data[:title] = default_title(path) if blank_value?(merged_data[:title])

      write_tag(path, merged_data)
      read(path)
    end

    def read(file_path)
      path = validate_file!(file_path)
      return {} unless tag_present_on_disk?(path)

      File.open(path, "rb") do |file|
        file.seek(-TAG_SIZE, IO::SEEK_END)
        parse_tag(file.read(TAG_SIZE))
      end
    end

    def tag_present?(file_path)
      path = validate_file!(file_path)
      tag_present_on_disk?(path)
    end

    private

    def write_tag(file_path, metadata)
      File.open(file_path, "r+b") do |file|
        if tag_present_on_disk?(file_path)
          file.seek(-TAG_SIZE, IO::SEEK_END)
        else
          file.seek(0, IO::SEEK_END)
        end

        file.write(build_tag(metadata))
      end
    end

    def build_tag(metadata)
      tag = String.new(TAG_SIGNATURE, encoding: Encoding::BINARY)
      tag << encode_text(metadata[:title], 30)
      tag << encode_text(metadata[:artist], 30)
      tag << encode_text(metadata[:album], 30)
      tag << encode_year(metadata[:year])

      if metadata[:track]
        tag << encode_text(metadata[:comment], 28)
        tag << "\x00".b
        tag << [metadata[:track]].pack("C")
      else
        tag << encode_text(metadata[:comment], 30)
      end

      tag << [genre_index(metadata[:genre])].pack("C")
      tag
    end

    def parse_tag(raw_tag)
      return {} unless raw_tag&.bytesize == TAG_SIZE
      return {} unless raw_tag.start_with?(TAG_SIGNATURE)

      comment_chunk = raw_tag.byteslice(97, 30)
      track = parse_track(comment_chunk)
      comment_length = track ? 28 : 30

      metadata = {
        title: decode_text(raw_tag.byteslice(3, 30)),
        artist: decode_text(raw_tag.byteslice(33, 30)),
        album: decode_text(raw_tag.byteslice(63, 30)),
        year: decode_text(raw_tag.byteslice(93, 4)),
        comment: decode_text(comment_chunk.byteslice(0, comment_length)),
        track: track,
        genre: genre_name(raw_tag.getbyte(127))
      }

      metadata.reject { |_key, value| blank_value?(value) }
    end

    def parse_track(comment_chunk)
      return nil unless comment_chunk
      return nil unless comment_chunk.getbyte(28) == 0

      track = comment_chunk.getbyte(29)
      return nil if track.nil? || track.zero?

      track
    end

    def encode_text(value, length)
      text = value.to_s.encode(TEXT_ENCODING, invalid: :replace, undef: :replace, replace: "?")
      text = text.byteslice(0, length).to_s
      text.ljust(length, "\x00").b
    end

    def encode_year(value)
      encode_text(value.to_s.strip[0, 4], 4)
    end

    def decode_text(value)
      return nil if value.nil?

      value
        .delete("\x00")
        .force_encoding(TEXT_ENCODING)
        .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
        .strip
    end

    def genre_index(value)
      return 255 if blank_value?(value)
      return value if value.is_a?(Integer) && value.between?(0, 255)

      normalized = value.to_s.strip.downcase
      index = GENRES.index { |genre| genre.downcase == normalized }
      index || 255
    end

    def genre_name(index)
      return nil if index.nil? || index == 255

      GENRES[index]
    end

    def normalize_metadata(metadata)
      raise TaggerError, "metadata must be a Hash" unless metadata.is_a?(Hash)

      metadata.each_with_object({}) do |(key, value), normalized|
        normalized_key = key.to_sym
        raise TaggerError, "unsupported metadata key: #{key}" unless METADATA_KEYS.include?(normalized_key)

        normalized[normalized_key] = normalize_value(normalized_key, value)
      end
    end

    def normalize_value(key, value)
      case key
      when :track
        normalize_track(value)
      when :year
        normalize_year(value)
      when :genre
        normalize_genre(value)
      else
        value.nil? ? nil : value.to_s.strip
      end
    end

    def normalize_track(value)
      return nil if blank_value?(value)

      track = Integer(value, exception: false)
      raise TaggerError, "track must be an integer between 1 and 255" unless track&.between?(1, 255)

      track
    end

    def normalize_year(value)
      return nil if blank_value?(value)

      value.to_s.gsub(/\D/, "")[0, 4]
    end

    def normalize_genre(value)
      return nil if blank_value?(value)
      return value if value.is_a?(Integer)

      value.to_s.strip
    end

    def validate_file!(file_path)
      raise TaggerError, "file path can't be empty" if blank_value?(file_path)

      path = File.expand_path(file_path.to_s)
      raise TaggerError, "file does not exist: #{path}" unless File.file?(path)

      extension = File.extname(path).downcase
      return path if SUPPORTED_EXTENSIONS.include?(extension)

      raise UnsupportedFormatError, "unsupported file format: #{extension}"
    end

    def default_title(file_path)
      File.basename(file_path, File.extname(file_path))
    end

    def tag_present_on_disk?(file_path)
      return false unless File.exist?(file_path)
      return false if File.size(file_path) < TAG_SIZE

      File.open(file_path, "rb") do |file|
        file.seek(-TAG_SIZE, IO::SEEK_END)
        file.read(3) == TAG_SIGNATURE
      end
    end

    def blank_value?(value)
      value.nil? || blank_string?(value)
    end

    def blank_string?(value)
      value.is_a?(String) && value.strip.empty?
    end
  end
end
