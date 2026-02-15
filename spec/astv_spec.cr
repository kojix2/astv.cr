require "./spec_helper"
require "../src/astv/core"
require "json"

describe Astv::Core do
  describe "#parse_response" do
    Dir.glob("spec/fixtures/*.cr").each do |fixture_file|
      basename = File.basename(fixture_file, ".cr")
      expected_file = "spec/fixtures/#{basename}.json"

      it "correctly parses #{basename}.cr" do
        source = File.read(fixture_file)
        actual_json = Astv::Core.parse_response(source)
        expected_json = File.read(expected_file)

        # Parse both JSONs to compare as objects (ignoring formatting differences)
        actual = JSON.parse(actual_json)
        expected = JSON.parse(expected_json)

        actual.should eq(expected)
      end
    end
  end

  describe "#lex_response" do
    it "returns JSON with errors for macro syntax instead of raising" do
      source = File.read("spec/fixtures/macros.cr")
      response = Astv::Core.lex_response(source)
      json = JSON.parse(response)

      json["source"].as_s.should eq(source)
      json["errors"].as_a.size.should be > 0
    end

    it "returns JSON without errors for plain syntax" do
      source = File.read("spec/fixtures/types.cr")
      response = Astv::Core.lex_response(source)
      json = JSON.parse(response)

      json["source"].as_s.should eq(source)
      json["errors"].as_a.size.should eq(0)
    end
  end
end
