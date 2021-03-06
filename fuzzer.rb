#encoding: UTF-8
require_relative 'ruby-utils/unicode-helpers'
MAX_RANDOM_TIMES = ENV['MAX'] ? ENV['MAX'].to_i : 10
ONLY_ASCII_IDENTS = true
ONLY_SNAKE_CASE_IDENTS = true
NESTED_BLOCK_COMMENTS = false
DEBUG = ENV['DEBUG'] || false

class FuzzyWuzzy
  def initialize
    @occurrences = Hash.new(0)
    @max_times = {
      comment: 1,
      const: 1,
      whitespace: 1,
      item: 100,
      function: 100,
      slot_declaration: 100,
      expression_statement: 100,
      mod: 100
    }
    # Turn off 2 of the allowed features to introduce more variety.
    # But not item because that's the entry point to everything else.
    (@max_times.keys - [:item]).sample(2).each do |k|
      puts "Turning off #{k}" if DEBUG
      @max_times[k] = 0
    end

    @idents = Hash.new { |h, k| h[k] = [] }
  end

  def record_occurrence(type)
    @occurrences[type] += 1
  end

  def allowed?(type)
    max = @max_times[type]
    !max || @occurrences[type] < max
  end

  def unicode
    UnicodeHelpers.new
  end

  def random_times
    rand(MAX_RANDOM_TIMES)
  end

  def generate_one(types)
    types.select! { |t| allowed? t }
    return '' if types.empty?
    which = types.sample
    puts "chose #{which}" if DEBUG
    record_occurrence(which)
    send("generate_#{which}")
  end

  def generate_some(types, how_many = 1)
    if how_many == 1
      generate_one(types)
    else
      how_many.times.map {
        generate_one(types)
      }.flatten.join
    end
  end

  def keywords
    %w{
      abstract 	alignof 	as 	be 	box
      break 	const 	continue 	crate 	do
      else 	enum 	extern 	false 	final
      fn 	for 	if 	impl 	in
      let 	loop 	macro 	match 	mod
      move 	mut 	offsetof 	override 	priv
      pub 	pure 	ref 	return 	sizeof
      static 	self 	struct 	super 	true
      trait 	type 	typeof 	unsafe 	unsized
      use 	virtual 	where 	while 	yield
    }
  end

  def generate_line_comment
    "// #{generate_comment_content}\n"
  end

  def generate_block_comment
    "/* #{block_comment_body} */ "
  end

  def generate_comment_content
    unicode.random_string(length: random_times, from: unicode.non_eol)
  end

  def block_comment_body
    return generate_comment_content unless NESTED_BLOCK_COMMENTS
    puts "in block_comment_body." if DEBUG
    generate_one [:block_comment, :comment_content]
  end

  def generate_comment
    puts "in generate_comment." if DEBUG
    generate_one [:block_comment, :line_comment]
  end

  def generate_whitespace_char
    unicode.whitespace_char
  end

  def generate_whitespace
    how_many = random_times + 1
    puts "in generate_whitespace." if DEBUG
    generate_some([:whitespace_char, :comment], how_many)
  end

  def generate_non_snake_case_ident
    ident = ''
    loop do
      ident = unicode.ident(length: random_times, only_ascii: ONLY_ASCII_IDENTS)
      break unless keywords.include?(ident)
    end
    ident
  end

  def generate_snake_case_ident
    ident = ''
    loop do
      ident = unicode.snake_case_ident(length: random_times, only_ascii: ONLY_ASCII_IDENTS)
      break unless keywords.include?(ident)
    end
    ident
  end

  def generate_unique_ident(type, options = {})
    ident = ''
    loop do
      ident = options[:uppercase] ? generate_uppercase_ident : generate_ident
      break unless @idents[type].include? ident
    end
    @idents[type] << ident
    ident
  end

  def generate_ident
    ONLY_SNAKE_CASE_IDENTS ? generate_snake_case_ident : generate_non_snake_case_ident
  end

  def generate_uppercase_ident
    # Keywords will never match these since keywords are all lowercase.
    unicode.screaming_snake_case_ident(length: random_times, only_ascii: ONLY_ASCII_IDENTS)
  end

  # 6.1.2
  def generate_mod
    puts "in generate_mod." if DEBUG

    ident = generate_unique_ident 'item'

    mod = " mod #{ ident } {\n"
    mod << generate_item
    mod << " } "
  end

  # 3.5.2.2.2
  def generate_static_string_literal
    how_many = random_times
    string_body = how_many.times.map {
      unicode.random_string(length: random_times, from: unicode.non_double_quote)
    }.join
    {
      type: "&'static str",
      expr: '"' + string_body + '"'
    }
  end

  # 3.5.2.2.1
  def generate_char_literal
    {
      type: 'char',
      expr: "'" + unicode.random_xid_start_character + "'"
    }
  end

  # 3.5.2.5
  def generate_boolean_literal
    {
      type: 'bool',
      expr: ['true', 'false'].sample
    }
  end

  # 3.5.2.4.1
  def generate_integer_literal
    {
      type: ['u8', 'i8', 'u16', 'i16', 'u32', 'i32', 'u64', 'i64', 'isize', 'usize'].sample,
      expr: rand(2 ** 8)
    }
  end

  # 7.2.1
  def generate_literal_expression
    generate_one [:static_string_literal, :char_literal, :boolean_literal, :integer_literal]
  end

  # 6.1.7
  def generate_const
    puts "in generate_const." if DEBUG

    ident = generate_unique_ident 'item', uppercase: true
    e     = generate_primitive_expression

    " const #{ ident }: #{ e[:type] } = #{ e[:expr] }; "
  end

  # 6.1.3
  def generate_function
    puts "in generate_function." if DEBUG

    ident = generate_unique_ident 'item'

    fn = " fn #{ ident }() {\n"
    random_times.times do
      fn << generate_statement
    end
    fn << " } "
  end

  # 7.1.1.1
  def generate_item
    puts "in generate_item." if DEBUG
    generate_one [:mod, :const, :function, :structure]
  end

  # 7.1.1.2
  def generate_slot_declaration
    ident = generate_unique_ident 'item'
    e     = generate_expression

    if e[:type]
      " let #{ ident }: #{ e[:type] } = #{ e[:expr] };\n"
    else
      " let #{ ident } = #{ e[:expr] };\n"
    end
  end

  # 7.1.1
  def generate_declaration_statement
    puts "in generate_declaration_statement" if DEBUG
    generate_one [:item, :slot_declaration]
  end

  # 7.2.12.1
  def generate_binary_arithmetic_expression
    operator = ['+', '-', '*', '/', '%'].sample
    op1 = generate_integer_literal
    op2 = generate_integer_literal

    # Disallow divide by 0
    while operator.match(/(\/|%)/) && op2[:expr] == 0
      op2 = generate_integer_literal
    end

    {
      type: op1[:type],
      expr: "#{op1[:expr]} #{operator} #{op2[:expr]}"
    }
  end

  # 7.2.12
  def generate_binary_operator_expression
    generate_one [:binary_arithmetic_expression] # There will be more things here eventually
  end

  # 7.2.4
  def generate_unit_expression
    { expr: '()' }
  end

  # 3.6
  def expr_path
    generate_unique_ident 'item'
  end

  def generate_struct_tuple
    tuple = (random_times + 2).times.map {
      generate_one([:primitive_expression])[:type]
    }.join(', ')
    { expr: " #{expr_path} (#{ tuple })" }
  end

  def generate_struct_expr_path_only
    { expr: expr_path }
  end

  # 7.2.5
  def generate_structure_expression
    generate_one [:struct_tuple, :struct_expr_path_only]
  end

  # 6.1.5
  def generate_structure
    " struct #{ generate_structure_expression[:expr] }; "
  end

  # 7.2
  def generate_expression
    generate_one [:literal_expression, :binary_operator_expression, :unit_expression]
  end

  # For use in consts
  def generate_primitive_expression
    generate_one [:literal_expression, :binary_operator_expression]
  end

  # 7.1.2
  def generate_expression_statement
    "#{generate_expression[:expr]};"
  end

  def generate_statement
    puts "in generate_statement." if DEBUG
    generate_one [:declaration_statement, :expression_statement]
  end

  def generate_rust
    how_many = random_times + 1 # Make this at least 2
    puts "generating #{how_many} fuzzy wuzzies outside main" if DEBUG
    outside_main = generate_some([:whitespace, :item], how_many)
    puts "occurrences = #{@occurrences.inspect}" if DEBUG

    @occurrences = Hash.new(0)

    how_many = random_times + 1 # Make this at least 2
    puts "generating #{how_many} fuzzy wuzzies inside main" if DEBUG
    main = "\nfn main() { " + generate_some([:whitespace, :item], how_many) + "}\n"
    puts "occurrences = #{@occurrences.inspect}" if DEBUG

    outside_main + main
  end

  # These are things that should go in any generated program.
  def static_preamble
    preamble = []

    unless ONLY_ASCII_IDENTS
      preamble << "#![feature(non_ascii_idents)]"
    end

    preamble.join("\n")
  end

  def write_generated_rust
    File.open('src/main.rs', 'w') do |f|
      f.puts static_preamble
      f.puts generate_rust
    end
  end

  def run_generated_rust
    write_generated_rust
    system("cargo build")
    system("cargo run")
  end
end

def limit?
  ENV['TIMES']
end

def limit
  ENV['TIMES'].to_i
end

if __FILE__ == $0
  run_times = 0

  loop do
    fw = FuzzyWuzzy.new
    run_succeeded = fw.run_generated_rust
    run_times += 1
    break if !run_succeeded || (limit? && run_times >= limit)
  end
end