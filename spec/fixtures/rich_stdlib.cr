require "http/client"
require "json"

response = HTTP::Client.get("https://crystal-lang.org/api/versions.json")
json = JSON.parse(response.body)
version = json["versions"].as_a.find! { |entry| entry["released"]? != false }["name"]

puts "Latest Crystal version: #{version || "Unknown"}"
