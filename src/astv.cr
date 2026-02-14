require "./astv/core"

module Astv
  extend self

  def run
    source = ""
    begin
      source = STDIN.gets_to_end
      mode = ARGV.first?
      output = mode == "lex" ? Core.lex_response(source) : Core.parse_response(source)
      puts output
    rescue ex
      STDERR.puts ex.message
      puts Core.error_response(ex, source)
      exit 1
    end
  end
end

Astv.run
