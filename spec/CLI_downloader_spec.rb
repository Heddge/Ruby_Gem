# frozen_string_literal: true

RSpec.describe CLIDownloader do
  it "has a version number" do
    expect(CLIDownloader::VERSION).not_to be nil
  end

  it "loads organizer API" do
    expect(CLIDownloader::Organizer).to be_a(Class)
  end

  it "loads tagger API" do
    expect(CLIDownloader::Tagger).to be_a(Class)
  end
end
