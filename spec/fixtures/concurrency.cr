channel = Channel(Int32).new

3.times do |i|
  spawn do
    3.times do |j|
      sleep rand(100).milliseconds # add non-determinism for fun
      channel.send 10 * (i + 1) + j
    end
  end
end

9.times do
  puts channel.receive
end
