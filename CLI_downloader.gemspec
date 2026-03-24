# frozen_string_literal: true

require_relative "lib/CLI_downloader/version"

Gem::Specification.new do |spec|
  spec.name = "CLI_downloader"
  spec.version = CLIDownloader::VERSION
  spec.authors = ["alexsim2007"]
  spec.email = ["aleksandrsimonov9622@gmail.com"]

  spec.summary     = "Media downloader tool"
  spec.description = "Automates downloading and tagging media files"
  spec.homepage    = "http://example.com"
  spec.required_ruby_version = ">= 3.2.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = begin
    IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls.readlines("\x0", chomp: true)
    end
  rescue Errno::EACCES, Errno::ENOENT
    Dir.glob("**/*", base: __dir__).select { |file| File.file?(File.join(__dir__, file)) }
  end.reject do |f|
    (f == gemspec) ||
      f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/])
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
