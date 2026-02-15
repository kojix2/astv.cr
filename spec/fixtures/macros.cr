macro upcase_getter(name)
  def {{ name.id }}
    @{{ name.id }}.upcase
  end
end

class Person
  upcase_getter name

  def initialize(@name : String)
  end
end

person = Person.new "John"
person.name # => "JOHN"
