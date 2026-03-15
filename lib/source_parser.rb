# frozen_string_literal: true

# Parses Ruby (.rb) and C (.c) source files to extract API definitions.
# Output format (pipe-delimited, one entry per line):
#   TYPE|QUALIFIED_NAME|SIGNATURE|FILE:LINE
#
# Types: class, module, imethod, cmethod, attr_r, attr_w, attr_rw
# Compatible with Ruby 2.6+

class SourceParser
  # --- public interface ---------------------------------------------------

  # Parse all relevant files under +source_dir+ and return an Array of
  # pipe-delimited index lines.
  def self.parse(source_dir, lang: :ruby)
    new(source_dir, lang: lang).parse
  end

  def initialize(source_dir, lang: :ruby)
    @source_dir = File.expand_path(source_dir)
    @lang = lang
    @entries = []
  end

  def parse
    parse_ruby_files
    parse_c_files if @lang == :ruby
    @entries.sort.uniq
  end

  private

  # -----------------------------------------------------------------------
  # Ruby (.rb) parser
  # -----------------------------------------------------------------------

  def parse_ruby_files
    Dir.glob(File.join(@source_dir, '**', '*.rb')).sort.each do |path|
      parse_rb_file(path)
    end
  end

  def parse_rb_file(filepath)
    content = File.read(filepath, encoding: 'utf-8') rescue return
    relative = filepath.sub("#{@source_dir}/", '')

    # Stack of [short_name, indent_level]
    ns_stack = []
    eigenclass_indent = nil
    in_heredoc = false
    heredoc_tag = nil

    content.each_line.with_index do |line, idx|
      lineno = idx + 1
      raw_indent = line[/\A\s*/].size
      s = line.strip

      # --- skip noise -----------------------------------------------------
      # Basic heredoc tracking
      if in_heredoc
        if s == heredoc_tag
          in_heredoc = false
          heredoc_tag = nil
        end
        next
      end
      if s =~ /<<[~-]?'?(\w+)'?\s*$/
        in_heredoc = true
        heredoc_tag = $1
        next
      end

      next if s.empty? || s.start_with?('#')
      next if s.start_with?('=begin') .. s.start_with?('=end')

      # --- eigenclass (class << self) ------------------------------------
      if s =~ /\Aclass\s*<<\s*self\b/
        eigenclass_indent = raw_indent
        next
      end
      if eigenclass_indent && s =~ /\Aend\b/ && raw_indent == eigenclass_indent
        eigenclass_indent = nil
        next
      end

      # --- class definition -----------------------------------------------
      if s =~ /\Aclass\s+(?:::)?([\w:]+)(?:\s*<\s*[\w:]+)?\s*(?:#.*)?$/
        name = $1
        # Pop stack to match indentation
        ns_stack.pop while !ns_stack.empty? && ns_stack.last[1] >= raw_indent
        fqn = resolve_fqn(ns_stack, name)
        ns_stack.push([name.include?('::') ? name.split('::').last : name, raw_indent])
        @entries << "class|#{fqn}||#{relative}:#{lineno}"
        next
      end

      # --- module definition ----------------------------------------------
      if s =~ /\Amodule\s+(?:::)?([\w:]+)\s*(?:#.*)?$/
        name = $1
        ns_stack.pop while !ns_stack.empty? && ns_stack.last[1] >= raw_indent
        fqn = resolve_fqn(ns_stack, name)
        ns_stack.push([name.include?('::') ? name.split('::').last : name, raw_indent])
        @entries << "module|#{fqn}||#{relative}:#{lineno}"
        next
      end

      # --- method definition ----------------------------------------------
      # Handles: def foo, def foo(args), def self.foo, def foo arg1, arg2
      if s =~ /\Adef\s+(self\.)?([\w!?=]+)(?:\((.*?)\)|\s+([\w:*&,\s='".\[\]{}|]+?))?(?:\s*#.*)?$/
        is_self = !$1.nil?
        mname = $2
        sig_args = $3 || $4 || ''
        sig_args = sig_args.strip.chomp(';')

        ns = namespace_for(ns_stack, raw_indent)
        in_eigen = eigenclass_indent && raw_indent > eigenclass_indent

        if is_self || in_eigen
          type = 'cmethod'
          fqn = ns.empty? ? ".#{mname}" : "#{ns}.#{mname}"
        else
          type = 'imethod'
          fqn = ns.empty? ? "##{mname}" : "#{ns}##{mname}"
        end

        sig = sig_args.empty? ? mname : "#{mname}(#{sig_args})"
        @entries << "#{type}|#{fqn}|#{sig}|#{relative}:#{lineno}"
        next
      end

      # --- attr_reader / attr_writer / attr_accessor ----------------------
      if s =~ /\A(attr_reader|attr_writer|attr_accessor)\s+(.+)/
        kind = $1
        attrs = $2.scan(/:([\w]+)/).flatten
        ns = namespace_for(ns_stack, raw_indent)

        type = case kind
               when 'attr_reader'   then 'attr_r'
               when 'attr_writer'   then 'attr_w'
               when 'attr_accessor' then 'attr_rw'
               end

        attrs.each do |attr|
          fqn = ns.empty? ? "##{attr}" : "#{ns}##{attr}"
          @entries << "#{type}|#{fqn}|#{attr}|#{relative}:#{lineno}"
        end
        next
      end

      # --- delegate / alias -----------------------------------------------
      # alias_method :new_name, :old_name
      if s =~ /\Aalias_method\s+:([\w!?=]+),\s*:([\w!?=]+)/
        new_name = $1
        ns = namespace_for(ns_stack, raw_indent)
        fqn = ns.empty? ? "##{new_name}" : "#{ns}##{new_name}"
        @entries << "imethod|#{fqn}|#{new_name}|#{relative}:#{lineno}"
        next
      end

      # alias new_name old_name  (bare alias, no colons)
      if s =~ /\Aalias\s+([\w!?=]+)\s+([\w!?=]+)\s*$/
        new_name = $1
        ns = namespace_for(ns_stack, raw_indent)
        fqn = ns.empty? ? "##{new_name}" : "#{ns}##{new_name}"
        @entries << "imethod|#{fqn}|#{new_name}|#{relative}:#{lineno}"
        next
      end

      # delegate :method_name, to: :target
      if s =~ /\Adelegate\s+((?::\w+(?:,\s*)?)+)/
        methods = $1.scan(/:([\w!?=]+)/).flatten
        ns = namespace_for(ns_stack, raw_indent)
        methods.each do |mname|
          fqn = ns.empty? ? "##{mname}" : "#{ns}##{mname}"
          @entries << "imethod|#{fqn}|#{mname}|#{relative}:#{lineno}"
        end
        next
      end
    end
  end

  def resolve_fqn(stack, name)
    if name.include?('::')
      # Fully-qualified or partially-qualified
      parts = name.split('::')
      # Check if first part matches top of stack
      ns = stack.map { |s| s[0] }.join('::')
      ns.empty? ? name : "#{ns}::#{name}"
    else
      ns = stack.map { |s| s[0] }.join('::')
      ns.empty? ? name : "#{ns}::#{name}"
    end
  end

  def namespace_for(stack, indent)
    stack.select { |s| s[1] < indent }.map { |s| s[0] }.join('::')
  end

  # -----------------------------------------------------------------------
  # C (.c) parser — for Ruby core methods defined in C
  # -----------------------------------------------------------------------

  C_VAR_MAP = {
    'rb_cObject'     => 'Object',
    'rb_cBasicObject'=> 'BasicObject',
    'rb_cArray'      => 'Array',
    'rb_cHash'       => 'Hash',
    'rb_cString'     => 'String',
    'rb_cInteger'    => 'Integer',
    'rb_cFloat'      => 'Float',
    'rb_cNumeric'    => 'Numeric',
    'rb_cSymbol'     => 'Symbol',
    'rb_cRegexp'     => 'Regexp',
    'rb_cRange'      => 'Range',
    'rb_cIO'         => 'IO',
    'rb_cFile'       => 'File',
    'rb_cDir'        => 'Dir',
    'rb_cTime'       => 'Time',
    'rb_cProc'       => 'Proc',
    'rb_cMethod'     => 'Method',
    'rb_cUnboundMethod' => 'UnboundMethod',
    'rb_cNilClass'   => 'NilClass',
    'rb_cTrueClass'  => 'TrueClass',
    'rb_cFalseClass' => 'FalseClass',
    'rb_cThread'     => 'Thread',
    'rb_cFiber'      => 'Fiber',
    'rb_cMutex'      => 'Mutex',
    'rb_cEnumerator' => 'Enumerator',
    'rb_cEncoding'   => 'Encoding',
    'rb_cStruct'     => 'Struct',
    'rb_cComplex'    => 'Complex',
    'rb_cRational'   => 'Rational',
    'rb_cException'  => 'Exception',
    'rb_cRuntimeError' => 'RuntimeError',
    'rb_cStandardError' => 'StandardError',
    'rb_cTypeError'  => 'TypeError',
    'rb_cArgError'   => 'ArgumentError',
    'rb_cNameError'  => 'NameError',
    'rb_cNoMethodError' => 'NoMethodError',
    'rb_cRangeError' => 'RangeError',
    'rb_cIOError'    => 'IOError',
    'rb_cEOFError'   => 'EOFError',
    'rb_cRegexpError'=> 'RegexpError',
    'rb_cSystemCallError' => 'SystemCallError',
    'rb_cMatchData'  => 'MatchData',
    'rb_mKernel'     => 'Kernel',
    'rb_mComparable' => 'Comparable',
    'rb_mEnumerable' => 'Enumerable',
    'rb_mErrno'      => 'Errno',
    'rb_mMath'       => 'Math',
    'rb_mProcess'    => 'Process',
    'rb_mGC'         => 'GC',
    'rb_mMarshal'    => 'Marshal',
    'rb_mSignal'     => 'Signal',
    'rb_mFileTest'   => 'FileTest',
    'rb_mObjectSpace'=> 'ObjectSpace',
    'rb_mWarning'    => 'Warning',
  }.freeze

  def parse_c_files
    # First pass: discover rb_define_class / rb_define_module calls
    # to build a var→name mapping beyond the hardcoded one.
    dynamic_map = {}

    c_files = Dir.glob(File.join(@source_dir, '**', '*.c')).sort
    c_files.each do |path|
      content = File.read(path, encoding: 'utf-8') rescue next

      # rb_define_class("Array", rb_cObject)
      content.scan(/(\w+)\s*=\s*rb_define_class\(\s*"(\w+)"/) do |var, name|
        dynamic_map[var] = name
      end
      # rb_define_class_under(rb_cIO, "Buffer", ...)
      content.scan(/(\w+)\s*=\s*rb_define_class_under\(\s*(\w+),\s*"(\w+)"/) do |var, parent, name|
        parent_name = C_VAR_MAP[parent] || dynamic_map[parent] || parent
        dynamic_map[var] = "#{parent_name}::#{name}"
      end
      # rb_define_module("Kernel")
      content.scan(/(\w+)\s*=\s*rb_define_module\(\s*"(\w+)"/) do |var, name|
        dynamic_map[var] = name
      end
      # rb_define_module_under(rb_mProcess, "Status")
      content.scan(/(\w+)\s*=\s*rb_define_module_under\(\s*(\w+),\s*"(\w+)"/) do |var, parent, name|
        parent_name = C_VAR_MAP[parent] || dynamic_map[parent] || parent
        dynamic_map[var] = "#{parent_name}::#{name}"
      end
    end

    var_map = C_VAR_MAP.merge(dynamic_map)

    # Second pass: extract method definitions
    c_files.each do |path|
      content = File.read(path, encoding: 'utf-8') rescue next
      relative = path.sub("#{@source_dir}/", '')

      content.each_line.with_index do |line, idx|
        lineno = idx + 1
        s = line.strip

        # rb_define_method(rb_cArray, "push", ...)
        if s =~ /rb_define_method\(\s*(\w+),\s*"([^"]+)"/
          cls = var_map[$1] || $1
          @entries << "imethod|#{cls}##{$2}|#{$2}|#{relative}:#{lineno}"
          next
        end

        # rb_define_private_method(rb_cHash, "initialize", ...)
        if s =~ /rb_define_private_method\(\s*(\w+),\s*"([^"]+)"/
          cls = var_map[$1] || $1
          @entries << "imethod|#{cls}##{$2}|#{$2}|#{relative}:#{lineno}"
          next
        end

        # rb_define_protected_method(...)
        if s =~ /rb_define_protected_method\(\s*(\w+),\s*"([^"]+)"/
          cls = var_map[$1] || $1
          @entries << "imethod|#{cls}##{$2}|#{$2}|#{relative}:#{lineno}"
          next
        end

        # rb_define_singleton_method / rb_define_module_function
        if s =~ /rb_define_(?:singleton_method|module_function)\(\s*(\w+),\s*"([^"]+)"/
          cls = var_map[$1] || $1
          @entries << "cmethod|#{cls}.#{$2}|#{$2}|#{relative}:#{lineno}"
          next
        end

        # rb_define_global_function("puts", ...)
        if s =~ /rb_define_global_function\(\s*"([^"]+)"/
          @entries << "cmethod|Kernel.#{$1}|#{$1}|#{relative}:#{lineno}"
          next
        end

        # rb_define_alloc_func — skip, not a user-facing API

        # Class/module definitions (for the index)
        if s =~ /rb_define_class\(\s*"([^"]+)"/
          @entries << "class|#{$1}||#{relative}:#{lineno}"
          next
        end
        if s =~ /rb_define_class_under\(\s*(\w+),\s*"([^"]+)"/
          parent = var_map[$1] || $1
          @entries << "class|#{parent}::#{$2}||#{relative}:#{lineno}"
          next
        end
        if s =~ /rb_define_module\(\s*"([^"]+)"/
          @entries << "module|#{$1}||#{relative}:#{lineno}"
          next
        end
        if s =~ /rb_define_module_under\(\s*(\w+),\s*"([^"]+)"/
          parent = var_map[$1] || $1
          @entries << "module|#{parent}::#{$2}||#{relative}:#{lineno}"
          next
        end
      end
    end
  end
end
