require "json"
require "compiler/crystal/syntax"

module Astv
  module Core
    extend self

    def lex_response(source : String)
      lines = [] of String
      tokens = [] of Crystal::Token
      errors = [] of NamedTuple(message: String, kind: String)
      lexer = Crystal::Lexer.new(source)
      lexer.filename = "input.cr"

      begin
        loop do
          token = lexer.next_token
          tokens << token.dup
          lines << token_to_tsv(token)
          break if token.type == Crystal::Token::Kind::EOF
        end
      rescue ex
        if macro_syntax?(source)
          begin
            lines.clear
            tokens.clear
            macro_lexer = Crystal::Lexer.new(source)
            macro_lexer.filename = "input.cr"
            macro_state = Crystal::Token::MacroState.default

            loop do
              token = macro_lexer.next_macro_token(macro_state, false)
              tokens << token.dup
              lines << token_to_tsv(token)
              macro_state = token.macro_state
              break if token.type == Crystal::Token::Kind::EOF
            end
          rescue macro_ex
            errors << {message: (macro_ex.message || macro_ex.class.name), kind: macro_ex.class.name}
          end
        else
          errors << {message: (ex.message || ex.class.name), kind: ex.class.name}
        end
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
            json.array do
              errors.each do |error|
                json.object do
                  json.field "message", error[:message]
                  json.field "kind", error[:kind]
                end
              end
            end
          end
        end
      end
    end

    private def macro_syntax?(source : String)
      # NOTE: Fast heuristic for fallback lexing.
      # It intentionally handles only the main literal/comment forms needed to
      # avoid falling back to macro lexing for unrelated lexer failures.
      in_double_quote = false
      in_single_quote = false
      in_line_comment = false
      percent_literal_end = nil.as(Char?)
      percent_literal_nested = false
      percent_literal_depth = 0
      heredoc_end = nil.as(String?)
      i = 0

      while i < source.bytesize
        if heredoc_end
          i, heredoc_end = advance_heredoc(source, i, heredoc_end)
          next
        end

        char = source.byte_at(i).unsafe_chr

        if in_line_comment
          in_line_comment = false if char == '\n'
        elsif literal_end = percent_literal_end
          i, percent_literal_end, percent_literal_nested, percent_literal_depth = advance_percent_literal(
            source,
            i,
            char,
            literal_end,
            percent_literal_nested,
            percent_literal_depth
          )
        elsif in_double_quote
          i, in_double_quote = advance_quoted_literal(source, i, char, '"')
        elsif in_single_quote
          i, in_single_quote = advance_quoted_literal(source, i, char, '\'')
        else
          macro_found, i, in_line_comment, in_double_quote, in_single_quote, percent_literal_end, percent_literal_nested, percent_literal_depth, heredoc_end = advance_plain_context(
            source,
            i,
            char,
            in_line_comment,
            in_double_quote,
            in_single_quote,
            percent_literal_end,
            percent_literal_nested,
            percent_literal_depth,
            heredoc_end
          )
          return true if macro_found
        end

        i += 1
      end

      false
    end

    private def advance_heredoc(source : String, index : Int32, heredoc_end : String)
      line_end = source.byte_index('\n'.ord.to_u8, index) || source.bytesize
      line = source.byte_slice(index, line_end - index)
      next_heredoc_end = line.lstrip == heredoc_end ? nil : heredoc_end
      {line_end + 1, next_heredoc_end}
    end

    private def advance_percent_literal(source : String, index : Int32, char : Char, literal_end : Char, nested : Bool, depth : Int32)
      next_index = index
      next_end = literal_end.as(Char?)
      next_nested = nested
      next_depth = depth

      if char == '\\'
        next_index += 1 if next_index + 1 < source.bytesize
      elsif nested && char == literal_end
        next_depth -= 1
        if next_depth <= 0
          next_end = nil
          next_nested = false
        end
      elsif nested
        if opening = matching_delimiter(literal_end)
          next_depth += 1 if char == opening
        end
      elsif char == literal_end
        next_end = nil
      end

      {next_index, next_end, next_nested, next_depth}
    end

    private def advance_quoted_literal(source : String, index : Int32, char : Char, closing : Char)
      next_index = index
      still_open = true

      if char == '\\'
        next_index += 1 if next_index + 1 < source.bytesize
      elsif char == closing
        still_open = false
      end

      {next_index, still_open}
    end

    private def advance_plain_context(source : String, index : Int32, char : Char, in_line_comment : Bool, in_double_quote : Bool, in_single_quote : Bool, percent_literal_end : Char?, percent_literal_nested : Bool, percent_literal_depth : Int32, heredoc_end : String?)
      macro_found = false
      next_index = index
      next_line_comment = in_line_comment
      next_double_quote = in_double_quote
      next_single_quote = in_single_quote
      next_percent_literal_end = percent_literal_end
      next_percent_literal_nested = percent_literal_nested
      next_percent_literal_depth = percent_literal_depth
      next_heredoc_end = heredoc_end

      case char
      when '#'
        next_line_comment = true
      when '"'
        next_double_quote = true
      when '\''
        next_single_quote = true
      when '%'
        if literal = percent_literal(source, index)
          next_percent_literal_end = literal[:end_char]
          next_percent_literal_nested = literal[:nested]
          next_percent_literal_depth = 1
          next_index = literal[:next_index]
        end
      when '<'
        if i = heredoc_start_index(source, index)
          next_heredoc_end = heredoc_identifier(source, i)
        end
      when '{'
        macro_found = macro_delimiter?(source, index)
      end

      {
        macro_found,
        next_index,
        next_line_comment,
        next_double_quote,
        next_single_quote,
        next_percent_literal_end,
        next_percent_literal_nested,
        next_percent_literal_depth,
        next_heredoc_end,
      }
    end

    private def macro_delimiter?(source : String, index : Int32)
      return false unless index + 1 < source.bytesize

      nxt = source.byte_at(index + 1).unsafe_chr
      nxt == '{' || nxt == '%'
    end

    private def heredoc_start_index(source : String, index : Int32)
      return unless index + 1 < source.bytesize
      return unless source.byte_at(index + 1).unsafe_chr == '<'

      index + 2
    end

    private def percent_literal(source : String, index : Int32)
      cursor = index + 1
      return nil if cursor >= source.bytesize

      opener = source.byte_at(cursor).unsafe_chr
      if opener.ascii_letter?
        cursor += 1
        return nil if cursor >= source.bytesize
        opener = source.byte_at(cursor).unsafe_chr
      end

      closing = closing_delimiter(opener)
      return nil unless closing

      {end_char: closing, nested: closing != opener, next_index: cursor}
    end

    private def closing_delimiter(opener : Char)
      case opener
      when '('
        ')'
      when '['
        ']'
      when '{'
        '}'
      when '<'
        '>'
      else
        opener
      end
    end

    private def matching_delimiter(closing : Char)
      case closing
      when ')'
        '('
      when ']'
        '['
      when '}'
        '{'
      when '>'
        '<'
      end
    end

    private def heredoc_identifier(source : String, index : Int32)
      cursor = index
      return nil if cursor >= source.bytesize

      if source.byte_at(cursor).unsafe_chr.in?('-', '~')
        cursor += 1
        return nil if cursor >= source.bytesize
      end

      start = cursor
      while cursor < source.bytesize
        char = source.byte_at(cursor).unsafe_chr
        break unless char.alphanumeric? || char == '_'
        cursor += 1
      end

      return nil if cursor == start
      source.byte_slice(start, cursor - start)
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

    def error_response(ex : Exception, source : String)
      message = ex.message || ex.class.name
      %({"source":#{source.to_json},"text":"","ast":null,"errors":[{"message":#{message.to_json},"kind":#{ex.class.name.to_json}}]})
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
end
