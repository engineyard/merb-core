# encoding: UTF-8

module Kernel
  # Used in Merb.root/config/init.rb to tell Merb which ORM (Object Relational
  # Mapper) you wish to use. Currently Merb has plugins to support
  # ActiveRecord, DataMapper, and Sequel.
  #
  # If for some reason this is called more than once, later call takes
  # over other.
  #
  # @param [Symbol] orm The ORM to use.
  #
  # @return [nil]
  #
  # @example
  #     use_orm :datamapper
  #
  #     # This will use the DataMapper generator for your ORM
  #     $ merb-gen model ActivityEvent
  #
  # @api public
  def use_orm(orm)
    Merb.orm = orm
    nil
  end

  # Used in Merb.root/config/init.rb to tell Merb which testing framework to
  # use. Currently Merb has plugins to support RSpec and Test::Unit.
  #
  # @param [Symbol] test_framework The test framework to use. Currently
  #   only supports `:rspec` and `:test_unit`.
  #
  # @return [nil]
  #
  # @example
  #     use_test :rspec
  #
  #     # This will now use the RSpec generator for tests
  #     $ merb-gen model ActivityEvent
  #
  # @api public
  def use_testing_framework(test_framework)
    Merb.test_framework = test_framework
    nil
  end

  def use_test(*args)
    use_testing_framework(*args)
  end

  # Used in Merb.root/config/init.rb to tell Merb which template engine to
  # prefer.
  #
  # @param [Symbol] template_engine The template engine to use.
  #
  # @return [nil]
  #
  # @example
  #     use_template_engine :haml
  #
  #     # This will now use haml templates in generators where available.
  #     $ merb-gen resource_controller Project 
  #
  # @api public
  def use_template_engine(template_engine)
    Merb.template_engine = template_engine
    nil
  end


  # @param [Fixnum] i The caller number.
  #
  # @return [Array<String>] The file, line and method of the caller.
  # @todo Docs: originally, return type was given as `Array<Array>`, but
  #   that's inconsistent with the example.
  #
  # @example
  #     __caller_info__(1)
  #     # => ['/usr/lib/ruby/1.8/irb/workspace.rb', '52', 'irb_binding']
  #
  # @api private
  def __caller_info__(i = 1)
    file, line, meth = caller[i].scan(/(.*?):(\d+):in `(.*?)'/).first
  end

  # @param [String] file The file to read.
  # @param [Fixnum] line The line number to look for.
  # @param [Fixnum] size Number of lines to include above and below the
  #   line to look for.
  #
  # @return [Array<Array>] Triplets containing the line number, the line
  #   and whether this was the searched line.
  #
  # @example
  #     __caller_lines__('/usr/lib/ruby/1.8/debug.rb', 122, 2)
  #     # =>
  #       [
  #         [ 120, "  def check_suspend",                               false ],
  #         [ 121, "    return if Thread.critical",                     false ],
  #         [ 122, "    while (Thread.critical = true; @suspend_next)", true  ],
  #         [ 123, "      DEBUGGER__.waiting.push Thread.current",      false ],
  #         [ 124, "      @suspend_next = false",                       false ]
  #       ]
  #
  # @api private
  def __caller_lines__(file, line, size = 4)
    line = line.to_i
    if file =~ /\(erubis\)/
      yield :error, "Template Error! Problem while rendering", false
    elsif !File.file?(file) || !File.readable?(file)
      yield :error, "File `#{file}' not available", false
    else
      lines = File.read(file).split("\n")
      first_line = (f = line - size - 1) < 0 ? 0 : f
      
      if first_line.zero?
        new_size = line - 1
        lines = lines[first_line, size + new_size + 1]
      else
        new_size = nil
        lines = lines[first_line, size * 2 + 1]
      end

      lines && lines.each_with_index do |str, index|
        line_n = index + line
        line_n = (new_size.nil?) ? line_n - size : line_n - new_size
        yield line_n, str.chomp
      end
    end
  end

  # Takes a block, profiles the results of running the block
  # specified number of times and generates HTML report.
  #
  #     __profile__("MyProfile", 5, 30) do
  #       rand(10)**rand(10)
  #       puts "Profile run"
  #     end
  #
  # Assuming that the total time taken for #puts calls was less than 5% of
  # the total time to run, #puts won't appear in the profile report. The
  # code block will be run 30 times in the example above.
  #
  # @param [#to_s] name The file name. The result will be written out to
  #   `Merb.root/"log/#{name}.html"`.
  # @param [Fixnum] min Minimum percentage of the total time a method must
  #   take for it to be included in the result.
  #
  # @return [String] The result of the profiling.
  #
  # @note Requires the ruby-prof gem.
  #
  # @api private
  def __profile__(name, min=1, iter=100)
    require 'ruby-prof' unless defined?(RubyProf)
    return_result = ''
    result = RubyProf.profile do
      iter.times{return_result = yield}
    end
    printer = RubyProf::GraphHtmlPrinter.new(result)
    path = File.join(Merb.root, 'log', "#{name}.html")
    File.open(path, 'w') do |file|
      printer.print(file, {:min_percent => min, :print_file => true})
    end
    return_result
  end

  # Extracts an options hash if it is the last item in the args array. Used
  # internally in methods that take `*args`.
  #
  # @param [Array] args The arguments to extract the hash from.
  #
  # @example
  #     def render(*args,&blk)
  #       opts = extract_options_from_args!(args) || {}
  #       # [...]
  #     end
  #
  # @api public
  def extract_options_from_args!(args)
    args.pop if (args.last.instance_of?(Hash) || args.last.instance_of?(Mash))
  end

  # Checks that the given objects quack like the given conditions.
  #
  # @param [Hash] opts Conditions to enforce. Each key will receive a
  #   `quacks_like?` call with the value (see {Object#quacks_like?} for
  #   details).
  # @note `Object#quacks_like?` is provided by extlib.
  #
  # @raise <ArgumentError>
  #   An object failed to quack like a condition.
  #
  # @api public
  def enforce!(opts = {})
    opts.each do |k,v|
      raise ArgumentError, "#{k.inspect} doesn't quack like #{v.inspect}" unless k.quacks_like?(v)
    end
  end

  # Define a module from a string name.
  #
  # @example
  #   make_module('Foo::Bar::Baz') #=> Foo::Bar::Baz
  #
  # If the module already exists, no exception is raised.
  #
  # @param [String] name The name of the full module name to make
  #
  # @return [Module]
  def make_module(string)
    string.split('::').inject(Object) do |mod, part|
      begin
        mod.const_get(part)
      rescue NameError
        mod.const_set(part, Module.new)
      end
    end
  end

  unless Kernel.respond_to?(:debugger)

    # Define debugger method so that code even works if debugger was not
    # requested. Drops a note to the logs that Debugger was not available.
    def debugger
      Merb.logger.info! "\n***** Debugger requested, but was not " +
        "available: Start server with --debugger " +
        "to enable *****\n"
    end
  end

end
