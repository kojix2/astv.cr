require "json"
require "kemal"
require "compiler/crystal/syntax"

module Astv
  VERSION                 = "0.1.0"
  MAX_INPUT_BYTES         = 1_000_000
  REQUEST_TIMEOUT_SECONDS =        10

  class RequestTooLarge < Exception
  end

  class RequestTimeout < Exception
  end

  extend self

  def run
    Kemal.config.public_folder = "astv"
    Kemal.config.serve_static = false

    get "/" do
      render "src/views/index.ecr"
    end

    post "/api/lex" do |env|
      source = read_source(env)
      env.response.content_type = "application/json"
      if env.response.status_code == 413
        next error_response(RequestTooLarge.new("payload too large"), "")
      end
      begin
        with_timeout(REQUEST_TIMEOUT_SECONDS) { lex_response(source) }
      rescue ex : RequestTimeout
        env.response.status_code = 408
        error_response(ex, source)
      rescue ex
        env.response.status_code = 400
        error_response(ex, source)
      end
    end

    post "/api/parse" do |env|
      source = read_source(env)
      env.response.content_type = "application/json"
      if env.response.status_code == 413
        next error_response(RequestTooLarge.new("payload too large"), "")
      end
      begin
        with_timeout(REQUEST_TIMEOUT_SECONDS) { parse_response(source) }
      rescue ex : RequestTimeout
        env.response.status_code = 408
        error_response(ex, source)
      rescue ex
        env.response.status_code = 400
        error_response(ex, source)
      end
    end

    Kemal.run
  end

  def read_source(env) : String
    if (length = env.request.content_length) && length > MAX_INPUT_BYTES
      env.response.status_code = 413
      return ""
    end

    body = env.request.body.try(&.gets_to_end) || ""
    if body.bytesize > MAX_INPUT_BYTES
      env.response.status_code = 413
      return ""
    end
    return body if body.empty?

    begin
      json = JSON.parse(body)
      code = json["code"]?
      return code.as_s if code && code.as_s?
    rescue
      # fall through
    end

    body
  end

  def lex_response(source : String)
    lines = [] of String
    tokens = [] of Crystal::Token
    lexer = Crystal::Lexer.new(source)
    lexer.filename = "input.cr" if lexer.responds_to?(:filename=)

    loop do
      token = lexer.next_token
      tokens << token
      lines << token_to_tsv(token)
      break if token.type == Crystal::Token::Kind::EOF
    end

    JSON.build do |json|
      json.object do
        json.field "source", source
        json.field "text", lines.join("\n")
        json.field "tokens" do
          json.array do
            tokens.each { |t| write_token_json(json, t) }
          end
        end
        json.field "errors" do
          json.array { }
        end
      end
    end
  end

  def parse_response(source : String)
    ast = Crystal::Parser.parse(source)
    text = String.build { |io| ast.to_s(io) }

    JSON.build do |json|
      json.object do
        json.field "source", source
        json.field "text", text
        json.field "ast" do
          write_ast_json(json, ast)
        end
        json.field "errors" do
          json.array { }
        end
      end
    end
  end

  def with_timeout(seconds : Int32, &block : -> String)
    result_channel = Channel(String).new(1)
    error_channel = Channel(Exception).new(1)
    operation = block

    spawn do
      begin
        result_channel.send(operation.call)
      rescue ex
        error_channel.send(ex)
      end
    end

    select
    when result = result_channel.receive
      result
    when ex = error_channel.receive
      raise ex
    when timeout(seconds.seconds)
      raise RequestTimeout.new("request timeout")
    end
  end

  def error_response(ex : Exception, source : String)
    %({"source":#{source.to_json},"text":"","ast":null,"errors":[{"message":#{ex.class.name.to_json},"kind":#{ex.class.name.to_json}}]})
  end

  def token_to_tsv(token : Crystal::Token)
    parts = [
      token.type.to_s,
      token.value.to_s,
      token.number_kind.to_s,
      token.line_number.to_s,
      token.column_number.to_s,
      token.filename.to_s,
      token.raw.to_s,
      token.start.to_s,
      token.passed_backslash_newline.to_s,
      token.invalid_escape.to_s,
    ]
    parts.join("\t")
  end

  def write_token_json(json : JSON::Builder, token : Crystal::Token)
    json.object do
      json.field "type", token.type.to_s
      json.field "value", token.value.to_s
      json.field "number_kind", token.number_kind.to_s
      json.field "line_number", token.line_number
      json.field "column_number", token.column_number
      json.field "filename", token.filename.to_s
      json.field "raw", token.raw.to_s
      json.field "start", token.start
      json.field "passed_backslash_newline", token.passed_backslash_newline
      json.field "invalid_escape", token.invalid_escape
    end
  end

  def write_ast_json(json : JSON::Builder, node : Crystal::ASTNode)
    json.object do
      json.field "type", node.class.name.split("::").last
      if loc = node.location
        write_location_json(json, loc, node.end_location)
      end

      children = child_nodes(node)

      rep = representative_value(node)
      if rep
        json.field rep[:key], rep[:value]
      end

      if children.size > 0
        json.field "children" do
          json.array do
            children.each { |child| write_ast_json(json, child) }
          end
        end
      end
    end
  end

  def write_location_json(json : JSON::Builder, start_loc : Crystal::Location, end_loc : Crystal::Location | Nil)
    json.field "location" do
      json.object do
        json.field "start_line", start_loc.line_number
        json.field "start_column", [start_loc.column_number - 1, 0].max
        if end_loc
          json.field "end_line", end_loc.line_number
          json.field "end_column", [end_loc.column_number - 1, 0].max
        else
          json.field "end_line", start_loc.line_number
          json.field "end_column", [start_loc.column_number - 1, 0].max
        end
      end
    end
  end

  def child_nodes(node : Crystal::ASTNode)
    collector = ChildCollector.new
    node.accept_children(collector)
    collector.nodes
  end

  def representative_value(node : Crystal::ASTNode)
    case node
    when Crystal::Alias
      {key: "name", value: node.name.to_s}
    when Crystal::Annotation
      {key: "name", value: node.path.to_s}
    when Crystal::AnnotationDef
      {key: "name", value: node.name.to_s}
    when Crystal::Arg
      {key: "name", value: node.name}
    when Crystal::ArrayLiteral
      value = "elements:#{node.elements.size}"
      node.of.try { |of_node| value += " of=#{summarize_node(of_node)}" }
      node.name.try { |name_node| value += " name=#{summarize_node(name_node)}" }
      {key: "value", value: value}
    when Crystal::Asm
      {key: "value", value: summarize_text(node.text)}
    when Crystal::AsmOperand
      {key: "value", value: node.constraint}
    when Crystal::Assign
      {key: "value", value: "="}
    when Crystal::BinaryOp
      {key: "value", value: node.class.name.split("::").last}
    when Crystal::Block
      {key: "value", value: "args:#{node.args.size}"}
    when Crystal::ClassDef
      {key: "name", value: node.name.to_s}
    when Crystal::Var
      {key: "name", value: node.name}
    when Crystal::InstanceVar
      {key: "name", value: node.name}
    when Crystal::ClassVar
      {key: "name", value: node.name}
    when Crystal::ControlExpression
      {key: "value", value: node.class.name.split("::").last}
    when Crystal::Global
      {key: "name", value: node.name}
    when Crystal::Path
      {key: "name", value: node.names.join("::")}
    when Crystal::Def
      {key: "name", value: node.name}
    when Crystal::DoubleSplat
      {key: "value", value: "**"}
    when Crystal::EnumDef
      {key: "name", value: node.name.to_s}
    when Crystal::ExceptionHandler
      flags = [] of String
      flags << "implicit" if node.implicit
      flags << "suffix" if node.suffix
      {key: "value", value: flags.empty? ? "rescue" : flags.join(",")}
    when Crystal::Expressions
      {key: "value", value: node.keyword.to_s}
    when Crystal::Extend
      {key: "value", value: summarize_node(node.name)}
    when Crystal::ExternalVar
      {key: "name", value: node.name}
    when Crystal::FunDef
      {key: "name", value: node.name}
    when Crystal::Generic
      suffix = node.suffix.to_s
      {key: "value", value: "vars:#{node.type_vars.size}#{suffix == "None" ? "" : " #{suffix}"}"}
    when Crystal::LibDef
      {key: "name", value: node.name.to_s}
    when Crystal::If
      {key: "value", value: node.ternary? ? "ternary" : "if"}
    when Crystal::ImplicitObj
      {key: "value", value: "implicit"}
    when Crystal::Include
      {key: "value", value: summarize_node(node.name)}
    when Crystal::InstanceAlignOf
      {key: "value", value: "instance_alignof"}
    when Crystal::InstanceSizeOf
      {key: "value", value: "instance_sizeof"}
    when Crystal::IsA
      {key: "value", value: "is_a"}
    when Crystal::Macro
      {key: "name", value: node.name}
    when Crystal::MacroExpression
      {key: "value", value: node.output? ? "{{}}" : "{% %}"}
    when Crystal::MacroFor
      {key: "value", value: "vars:#{node.vars.size}"}
    when Crystal::MacroIf
      {key: "value", value: node.is_unless? ? "unless" : "if"}
    when Crystal::MacroLiteral
      {key: "value", value: summarize_text(node.value)}
    when Crystal::Call
      {key: "name", value: node.name}
    when Crystal::MacroVar
      {key: "name", value: node.name}
    when Crystal::MacroVerbatim
      {key: "value", value: "verbatim"}
    when Crystal::MagicConstant
      {key: "name", value: node.name.to_s}
    when Crystal::Metaclass
      {key: "value", value: "metaclass"}
    when Crystal::ModuleDef
      {key: "name", value: node.name.to_s}
    when Crystal::MultiAssign
      {key: "value", value: "targets:#{node.targets.size}, values:#{node.values.size}"}
    when Crystal::NamedArgument
      {key: "name", value: node.name}
    when Crystal::NamedTupleLiteral
      {key: "value", value: "entries:#{node.entries.size}"}
    when Crystal::NilableCast
      {key: "value", value: "as?"}
    when Crystal::Nop
      {key: "value", value: "nop"}
    when Crystal::Not
      {key: "value", value: "not"}
    when Crystal::NumberLiteral
      {key: "value", value: "#{node.value}:#{node.kind}"}
    when Crystal::OffsetOf
      {key: "value", value: "offsetof"}
    when Crystal::OpAssign
      {key: "value", value: "#{node.op}="}
    when Crystal::Out
      {key: "value", value: "out"}
    when Crystal::PointerOf
      {key: "value", value: "pointerof"}
    when Crystal::ProcPointer
      {key: "name", value: node.name}
    when Crystal::ProcLiteral
      {key: "value", value: "->"}
    when Crystal::ProcNotation
      {key: "value", value: "inputs:#{node.inputs.try(&.size) || 0}"}
    when Crystal::RangeLiteral
      {key: "value", value: node.exclusive? ? "exclusive" : "inclusive"}
    when Crystal::Rescue
      {key: "value", value: node.name || "rescue"}
    when Crystal::ReadInstanceVar
      {key: "name", value: node.name}
    when Crystal::Require
      {key: "value", value: node.string}
    when Crystal::RegexLiteral
      {key: "value", value: "options:#{node.options}"}
    when Crystal::RespondsTo
      {key: "value", value: node.name}
    when Crystal::Return
      {key: "value", value: "return"}
    when Crystal::Select
      {key: "value", value: "whens:#{node.whens.size}"}
    when Crystal::Self
      {key: "value", value: "self"}
    when Crystal::SizeOf
      {key: "value", value: "sizeof"}
    when Crystal::Splat
      {key: "value", value: "*"}
    when Crystal::StringInterpolation
      {key: "value", value: "parts:#{node.expressions.size}"}
    when Crystal::StringLiteral
      {key: "value", value: node.value}
    when Crystal::CharLiteral
      {key: "value", value: node.value.to_s}
    when Crystal::SymbolLiteral
      {key: "value", value: node.value.to_s}
    when Crystal::BoolLiteral
      {key: "value", value: node.value}
    when Crystal::NilLiteral
      {key: "value", value: "nil"}
    when Crystal::TupleLiteral
      {key: "value", value: "elements:#{node.elements.size}"}
    when Crystal::TypeDeclaration
      {key: "name", value: summarize_node(node.var)}
    when Crystal::TypeDef
      {key: "name", value: node.name}
    when Crystal::TypeOf
      {key: "value", value: "expressions:#{node.expressions.size}"}
    when Crystal::UnaryExpression
      {key: "value", value: node.class.name.split("::").last}
    when Crystal::UninitializedVar
      {key: "name", value: summarize_node(node.var)}
    when Crystal::Underscore
      {key: "value", value: "_"}
    when Crystal::Union
      {key: "value", value: "types:#{node.types.size}"}
    when Crystal::Unless
      {key: "value", value: "unless"}
    when Crystal::Until
      {key: "value", value: "until"}
    else
      {key: "value", value: summarize_node(node)}
    end
  end

  def summarize_node(node : Crystal::ASTNode)
    text = node.to_s
    text = text.gsub(/\s+/, " ").strip
    return text if text.size <= 140

    "#{text[0, 137]}..."
  end

  def summarize_text(text : String, limit = 80)
    normalized = text.gsub(/\s+/, " ").strip
    return normalized if normalized.size <= limit

    "#{normalized[0, limit - 3]}..."
  end

  class ChildCollector < Crystal::Visitor
    getter nodes : Array(Crystal::ASTNode)

    def initialize
      @nodes = [] of Crystal::ASTNode
    end

    def visit(node : Crystal::ASTNode)
      @nodes << node
      false
    end
  end
end

Astv.run
