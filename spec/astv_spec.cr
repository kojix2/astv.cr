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
end
