# frozen_string_literal: true

require "fileutils"

module CLIDownloader
  class Organizer
    DEFAULT_DIRECTORY_TEMPLATE = "%{media_type}/%{artist}/%{album}".freeze
    DEFAULT_FILENAME_TEMPLATE = "%{year} - %{title}".freeze
    DEFAULT_PLACEHOLDER = "Unknown".freeze
    INVALID_FILENAME_CHARS = /[<>:"\/\\|?*\u0000-\u001F]/.freeze
    WINDOWS_RESERVED_NAMES = %w[
      CON PRN AUX NUL
      COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9
      LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9
    ].freeze

    AUDIO_EXTENSIONS = %w[.aac .flac .m4a .mp3 .ogg .wav].freeze
    VIDEO_EXTENSIONS = %w[.avi .mkv .mov .mp4 .webm].freeze
    IMAGE_EXTENSIONS = %w[.bmp .gif .jpeg .jpg .png .webp].freeze

    Result = Struct.new(
      :source_path,
      :destination_path,
      :created_directories,
      :renamed,
      :moved,
      keyword_init: true
    ) do
      def destination
        destination_path
      end
    end

    class OrganizerError < Error; end
    class FileMissingError < OrganizerError; end
    class InvalidTemplateError < OrganizerError; end
    class InvalidBaseDirectoryError < OrganizerError; end

    def self.call(...)
      new(...).call
    end

    attr_reader :base_directory, :collision_strategy, :directory_template, :filename_template, :placeholder

    def initialize(
      base_directory:,
      directory_template: DEFAULT_DIRECTORY_TEMPLATE,
      filename_template: DEFAULT_FILENAME_TEMPLATE,
      placeholder: DEFAULT_PLACEHOLDER,
      collision_strategy: :increment
    )
      @base_directory = prepare_base_directory(base_directory)
      @directory_template = directory_template
      @filename_template = filename_template
      @placeholder = sanitize_segment(placeholder)
      @collision_strategy = collision_strategy

      validate_collision_strategy!
    end

    def call(source_path:, metadata: {})
      organize(source_path:, metadata:)
    end

    def organize(source_path:, metadata: {})
      source = expand_source_path(source_path)
      values = build_template_values(source, metadata)
      destination_directory = build_destination_directory(values)
      created_directories = directories_to_create(destination_directory)
      FileUtils.mkdir_p(destination_directory)

      destination_path = resolve_destination(File.join(destination_directory, render_filename(values)))
      FileUtils.mv(source, destination_path)

      Result.new(
        source_path: source,
        destination_path: destination_path,
        created_directories: created_directories,
        renamed: File.basename(source) != File.basename(destination_path),
        moved: File.dirname(source) != File.dirname(destination_path)
      )
    end

    def preview(source_path:, metadata: {})
      source = expand_source_path(source_path)
      values = build_template_values(source, metadata)
      destination_directory = build_destination_directory(values)

      resolve_destination(File.join(destination_directory, render_filename(values)))
    end

    private

    def prepare_base_directory(base_directory)
      path = base_directory.to_s.strip
      raise InvalidBaseDirectoryError, "base_directory can't be empty" if path.empty?

      File.expand_path(path)
    end

    def expand_source_path(source_path)
      path = File.expand_path(source_path.to_s)
      raise FileMissingError, "File not found: #{path}" unless File.file?(path)

      path
    end

    def validate_collision_strategy!
      return if collision_strategy == :increment

      raise OrganizerError, "Unsupported collision strategy: #{collision_strategy}"
    end

    def build_template_values(source_path, metadata)
      metadata = normalize_metadata(metadata)
      extension = normalize_extension(metadata[:extension] || File.extname(source_path))
      original_name = File.basename(source_path, File.extname(source_path))

      raw_values = {
        media_type: metadata[:media_type] || detect_media_type(extension),
        artist: metadata[:artist],
        album: metadata[:album],
        year: metadata[:year],
        title: metadata[:title] || original_name,
        original_filename: metadata[:original_filename] || original_name,
        extension: extension
      }

      raw_values.each_with_object({}) do |(key, value), normalized|
        normalized[key] = key == :extension ? value : sanitize_segment(value || placeholder)
      end
    end

    def build_destination_directory(values)
      relative_path = render_directory_template(values)
      File.join(base_directory, relative_path)
    end

    def render_directory_template(values)
      rendered = render_template(directory_template, values)
      segments = rendered.split(%r{[\\/]+}).map { |segment| sanitize_segment(segment) }.reject(&:empty?)
      return placeholder if segments.empty?

      File.join(*segments)
    end

    def render_filename(values)
      base_name = sanitize_segment(render_template(filename_template, values))
      extension = values.fetch(:extension)

      return base_name if extension.empty? || base_name.downcase.end_with?(extension.downcase)

      "#{base_name}#{extension}"
    end

    def render_template(template, values)
      template % values.transform_values { |value| value.nil? || value.to_s.empty? ? placeholder : value.to_s }
    rescue KeyError => e
      raise InvalidTemplateError, "Template contains unknown key: #{e.key}"
    end

    def resolve_destination(path)
      return path unless File.exist?(path)
      return resolve_incremented_destination(path) if collision_strategy == :increment

      path
    end

    def resolve_incremented_destination(path)
      directory = File.dirname(path)
      extension = File.extname(path)
      basename = File.basename(path, extension)
      counter = 1

      loop do
        candidate = File.join(directory, "#{basename} (#{counter})#{extension}")
        return candidate unless File.exist?(candidate)

        counter += 1
      end
    end

    def directories_to_create(destination_directory)
      directories = []
      current = destination_directory

      until Dir.exist?(current)
        directories << current
        parent = File.dirname(current)
        break if parent == current

        current = parent
      end

      directories.reverse
    end

    def normalize_metadata(metadata)
      metadata.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_sym] = value
      end
    end

    def normalize_extension(extension)
      value = extension.to_s.strip
      return "" if value.empty?

      value.start_with?(".") ? value.downcase : ".#{value.downcase}"
    end

    def detect_media_type(extension)
      return "music" if AUDIO_EXTENSIONS.include?(extension)
      return "videos" if VIDEO_EXTENSIONS.include?(extension)
      return "images" if IMAGE_EXTENSIONS.include?(extension)

      "other"
    end

    def sanitize_segment(value)
      sanitized = value.to_s.gsub(INVALID_FILENAME_CHARS, " ")
      sanitized = sanitized.gsub(/\s+/, " ").strip
      sanitized = sanitized.gsub(/[. ]+\z/, "")
      sanitized = placeholder if sanitized.empty?

      return "#{sanitized}_" if WINDOWS_RESERVED_NAMES.include?(sanitized.upcase)

      sanitized
    end
  end
end
