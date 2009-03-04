module Fiveruns::JSON
  class << self
    # If _object_ is string-like parse the string and return the parsed result
    # as a Ruby data structure. Otherwise generate a FiverunsJSON text from the Ruby
    # data structure object and return it.
    #
    # The _opts_ argument is passed through to generate/parse respectively, see
    # generate and parse for their documentation.
    def [](object, opts = {})
      if object.respond_to? :to_str
        ::Fiveruns::JSON.parse(object.to_str, opts => {})
      else
        ::Fiveruns::JSON.generate(object, opts => {})
      end
    end

    # Returns the FiverunsJSON parser class, that is used by FiverunsJSON. This might be either
    # FiverunsJSON::Ext::Parser or FiverunsJSON::Pure::Parser.
    attr_reader :parser

    # Set the FiverunsJSON parser class _parser_ to be used by FiverunsJSON.
    # def parser=(parser) # :nodoc:
    #   @parser = parser
    #   remove_const :Parser if const_defined? :Parser
    #   const_set :Parser, parser
    # end

    # Return the constant located at _path_. The format of _path_ has to be
    # either ::A::B::C or A::B::C. In any case A has to be located at the top
    # level (absolute namespace path?). If there doesn't exist a constant at
    # the given path, an ArgumentError is raised.
    def deep_const_get(path) # :nodoc:
      path = path.to_s
      path.split(/::/).inject(Object) do |p, c|
        case
        when c.empty?             then p
        when p.const_defined?(c)  then p.const_get(c)
        else                      raise ArgumentError, "can't find const #{path}"
        end
      end
    end

    # Set the module _generator_ to be used by FiverunsJSON.
    def generator=(generator) # :nodoc:
      @generator = generator
      generator_methods = generator::GeneratorMethods
      for const in generator_methods.constants
        klass = deep_const_get(const)
        modul = generator_methods.const_get(const)
        klass.class_eval do
          instance_methods(false).each do |m|
            m.to_s == 'to_fjson' and remove_method m
          end
          include modul
        end
      end
      self.state = generator::State
      const_set :State, self.state
    end

    # Returns the FiverunsJSON generator modul, that is used by FiverunsJSON. This might be
    # either FiverunsJSON::Ext::Generator or FiverunsJSON::Pure::Generator.
    attr_reader :generator

    # Returns the FiverunsJSON generator state class, that is used by FiverunsJSON. This might
    # be either FiverunsJSON::Ext::Generator::State or FiverunsJSON::Pure::Generator::State.
    attr_accessor :state

    # This is create identifier, that is used to decide, if the _json_create_
    # hook of a class should be called. It defaults to 'json_class'.
    attr_accessor :create_id
  end
  self.create_id = 'json_class'

  NaN           = (-1.0) ** 0.5

  Infinity      = 1.0/0

  MinusInfinity = -Infinity

  # The base exception for FiverunsJSON errors.
  class JSONError < StandardError; end

  # This exception is raised, if a parser error occurs.
  class ParserError < ::Fiveruns::JSON::JSONError; end

  # This exception is raised, if the nesting of parsed datastructures is too
  # deep.
  class NestingError < ParserError; end

  # This exception is raised, if a generator or unparser error occurs.
  class GeneratorError < ::Fiveruns::JSON::JSONError; end
  # For backwards compatibility
  UnparserError = GeneratorError

  # If a circular data structure is encountered while unparsing
  # this exception is raised.
  class CircularDatastructure < GeneratorError; end

  # This exception is raised, if the required unicode support is missing on the
  # system. Usually this means, that the iconv library is not installed.
  class MissingUnicodeSupport < ::Fiveruns::JSON::JSONError; end

  module_function

  # Parse the FiverunsJSON string _source_ into a Ruby data structure and return it.
  #
  # _opts_ can have the following
  # keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Disable depth checking with :max_nesting => false, it defaults
  #   to 19.
  # * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
  #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
  #   to false.
  # * *create_additions*: If set to false, the Parser doesn't create
  #   additions even if a matchin class and create_id was found. This option
  #   defaults to true.
  # def parse(source, opts = {})
  #   ::Fiveruns::JSON.parser.new(source, opts).parse
  # end

  # Parse the FiverunsJSON string _source_ into a Ruby data structure and return it.
  # The bang version of the parse method, defaults to the more dangerous values
  # for the _opts_ hash, so be sure only to parse trusted _source_ strings.
  #
  # _opts_ can have the following keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Enable depth checking with :max_nesting => anInteger. The parse!
  #   methods defaults to not doing max depth checking: This can be dangerous,
  #   if someone wants to fill up your stack.
  # * *allow_nan*: If set to true, allow NaN, Infinity, and -Infinity in
  #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
  #   to true.
  # * *create_additions*: If set to false, the Parser doesn't create
  #   additions even if a matchin class and create_id was found. This option
  #   defaults to true.
  # def parse!(source, opts = {})
  #   opts = {
  #     :max_nesting => false,
  #     :allow_nan => true
  #   }.update(opts)
  #   ::Fiveruns::JSON.parser.new(source, opts).parse
  # end

  # Unparse the Ruby data structure _obj_ into a single line FiverunsJSON string and
  # return it. _state_ is
  # * a FiverunsJSON::State object,
  # * or a Hash like object (responding to to_hash),
  # * an object convertible into a hash by a to_h method,
  # that is used as or to configure a State object.
  #
  # It defaults to a state object, that creates the shortest possible FiverunsJSON text
  # in one line, checks for circular data structures and doesn't allow NaN,
  # Infinity, and -Infinity.
  #
  # A _state_ hash can have the following keys:
  # * *indent*: a string used to indent levels (default: ''),
  # * *space*: a string that is put after, a : or , delimiter (default: ''),
  # * *space_before*: a string that is put before a : pair delimiter (default: ''),
  # * *object_nl*: a string that is put at the end of a FiverunsJSON object (default: ''), 
  # * *array_nl*: a string that is put at the end of a FiverunsJSON array (default: ''),
  # * *check_circular*: true if checking for circular data structures
  #   should be done (the default), false otherwise.
  # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
  #   generated, otherwise an exception is thrown, if these values are
  #   encountered. This options defaults to false.
  # * *max_nesting*: The maximum depth of nesting allowed in the data
  #   structures from which FiverunsJSON is to be generated. Disable depth checking
  #   with :max_nesting => false, it defaults to 19.
  #
  # See also the fast_generate for the fastest creation method with the least
  # amount of sanity checks, and the pretty_generate method for some
  # defaults for a pretty output.
  def generate(obj, state = nil)
    if state
      state = State.from_state(state)
    else
      state = State.new
    end
    obj.to_fjson(state)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and
  # later delete them.
  alias unparse generate
  module_function :unparse
  # :startdoc:

  # Unparse the Ruby data structure _obj_ into a single line FiverunsJSON string and
  # return it. This method disables the checks for circles in Ruby objects, and
  # also generates NaN, Infinity, and, -Infinity float values.
  #
  # *WARNING*: Be careful not to pass any Ruby data structures with circles as
  # _obj_ argument, because this will cause FiverunsJSON to go into an infinite loop.
  def fast_generate(obj)
    obj.to_fjson(nil)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias fast_unparse fast_generate
  module_function :fast_unparse
  # :startdoc:

  # Unparse the Ruby data structure _obj_ into a FiverunsJSON string and return it. The
  # returned string is a prettier form of the string returned by #unparse.
  #
  # The _opts_ argument can be used to configure the generator, see the
  # generate method for a more detailed explanation.
  def pretty_generate(obj, opts = nil)
    state = ::Fiveruns::JSON.state.new(
      :indent     => '  ',
      :space      => ' ',
      :object_nl  => "\n",
      :array_nl   => "\n",
      :check_circular => true
    )
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state.configure(opts)
    end
    obj.to_fjson(state)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias pretty_unparse pretty_generate
  module_function :pretty_unparse
  # :startdoc:

  # Load a ruby data structure from a FiverunsJSON _source_ and return it. A source can
  # either be a string-like object, an IO like object, or an object responding
  # to the read method. If _proc_ was given, it will be called with any nested
  # Ruby object as an argument recursively in depth first order.
  #
  # This method is part of the implementation of the load/dump interface of
  # Marshal and YAML.
  def load(source, proc = nil)
    if source.respond_to? :to_str
      source = source.to_str
    elsif source.respond_to? :to_io
      source = source.to_io.read
    else
      source = source.read
    end
    result = parse(source, :max_nesting => false, :allow_nan => true)
    recurse_proc(result, &proc) if proc
    result
  end

  def recurse_proc(result, &proc)
    case result
    when Array
      result.each { |x| recurse_proc x, &proc }
      proc.call result
    when Hash
      result.each { |x, y| recurse_proc x, &proc; recurse_proc y, &proc }
      proc.call result
    else
      proc.call result
    end
  end
  private :recurse_proc
  module_function :recurse_proc

  alias restore load
  module_function :restore

  # Dumps _obj_ as a FiverunsJSON string, i.e. calls generate on the object and returns
  # the result.
  #
  # If anIO (an IO like object or an object that responds to the write method)
  # was given, the resulting FiverunsJSON is written to it.
  #
  # If the number of nested arrays or objects exceeds _limit_ an ArgumentError
  # exception is raised. This argument is similar (but not exactly the
  # same!) to the _limit_ argument in Marshal.dump.
  #
  # This method is part of the implementation of the load/dump interface of
  # Marshal and YAML.
  def dump(obj, anIO = nil, limit = nil)
    if anIO and limit.nil?
      anIO = anIO.to_io if anIO.respond_to?(:to_io)
      unless anIO.respond_to?(:write)
        limit = anIO
        anIO = nil
      end
    end
    limit ||= 0
    result = generate(obj, :allow_nan => true, :max_nesting => limit)
    if anIO
      anIO.write result
      anIO
    else
      result
    end
  rescue ::Fiveruns::JSON::NestingError
    raise ArgumentError, "exceed depth limit"
  end
end

module ::Kernel
  # Outputs _objs_ to STDOUT as FiverunsJSON strings in the shortest form, that is in
  # one line.
  def fj(*objs)
    objs.each do |obj|
      puts ::Fiveruns::JSON::generate(obj, :allow_nan => true, :max_nesting => false)
    end
    nil
  end

  # Ouputs _objs_ to STDOUT as FiverunsJSON strings in a pretty format, with
  # indentation and over many lines.
  def fjj(*objs)
    objs.each do |obj|
      puts ::Fiveruns::JSON::pretty_generate(obj, :allow_nan => true, :max_nesting => false)
    end
    nil
  end

  # If _object_ is string-like parse the string and return the parsed result as
  # a Ruby data structure. Otherwise generate a FiverunsJSON text from the Ruby data
  # structure object and return it.
  #
  # The _opts_ argument is passed through to generate/parse respectively, see
  # generate and parse for their documentation.
  def FJSON(object, opts = {})
    # if object.respond_to? :to_str
    #   ::Fiveruns::JSON.parse(object.to_str, opts)
    # else
      ::Fiveruns::JSON.generate(object, opts)
    # end
  end
end

class ::Class
  # Returns true, if this class can be used to create an instance
  # from a serialised FiverunsJSON string. The class has to implement a class
  # method _json_create_ that expects a hash as first parameter, which includes
  # the required data.
  def fjson_creatable?
    respond_to?(:fjson_create)
  end
end