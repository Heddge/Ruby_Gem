# frozen_string_literal: true

module CLIDownloader
  class Tagger
    TAG_SIGNATURE = "TAG"
    TAG_SIZE = 128
    TEXT_ENCODING = Encoding::ISO_8859_1

    def tag(file_path, metadata = {})
      write(file_path, metadata)
    end

    def write(file_path, metadata = {})
      path = File.expand_path(file_path.to_s)
      data = symbolize_keys(metadata)
      data[:title] = default_title(path) unless data.key?(:title)

      File.open(path, "r+b") do |file|
        if tag_present_on_disk?(path)
          file.seek(-TAG_SIZE, IO::SEEK_END)
        else
          file.seek(0, IO::SEEK_END)
        end

        file.write(build_tag(data))
      end

      read(path)
    end

    def read(file_path)
      path = File.expand_path(file_path.to_s)
      return {} unless tag_present_on_disk?(path)

      File.open(path, "rb") do |file|
        file.seek(-TAG_SIZE, IO::SEEK_END)
        parse_tag(file.read(TAG_SIZE))
      end
    end

    def tag_present?(file_path)
      path = File.expand_path(file_path.to_s)
      tag_present_on_disk?(path)
    end

    private

    def build_tag(metadata)
      tag = String.new(TAG_SIGNATURE, encoding: Encoding::BINARY)
      tag << encode_text(metadata[:title], 30)
      tag << encode_text(metadata[:artist], 30)
      tag << encode_text(metadata[:album], 30)
      tag << encode_text(metadata[:year], 4)
      tag << encode_text(metadata[:comment], 30)
      tag << [255].pack("C")
      tag
    end

    def parse_tag(raw_tag)
      return {} unless raw_tag&.bytesize == TAG_SIZE
      return {} unless raw_tag.start_with?(TAG_SIGNATURE)

      {
        title: decode_text(raw_tag.byteslice(3, 30)),
        artist: decode_text(raw_tag.byteslice(33, 30)),
        album: decode_text(raw_tag.byteslice(63, 30)),
        year: decode_text(raw_tag.byteslice(93, 4)),
        comment: decode_text(raw_tag.byteslice(97, 30))
      }.reject { |_key, value| value.nil? || value.empty? }
    end

    def encode_text(value, length)
      text = value.to_s.encode(TEXT_ENCODING, invalid: :replace, undef: :replace, replace: "?")
      text = text.byteslice(0, length).to_s
      text.ljust(length, "\x00").b
    end

    def decode_text(value)
      return nil if value.nil?

      value
        .delete("\x00")
        .force_encoding(TEXT_ENCODING)
        .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
        .strip
    end

    def symbolize_keys(metadata)
      metadata.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value
      end
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
  end
end
