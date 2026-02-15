# Define the lib bindings and link info:
@[Link("m")]
lib LibM
  fun pow(x : LibC::Double, y : LibC::Double) : LibC::Double
end

# Call a C function like a Crystal method:
puts LibM.pow(2.0, 4.0) # => 16.0
