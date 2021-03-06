# encoding: UTF-8

# #### Why do we use Underscores?
# In Merb, views are actually methods on controllers. This provides
# not-insignificant speed benefits, as well as preventing us from
# needing to copy over instance variables, which we think is proof
# that everything belongs in one class to begin with.
#
# Unfortunately, this means that view helpers need to be included
# into the {Controller} class. To avoid causing confusion
# when your helpers potentially conflict with our instance methods,
# we use an _ to disambiguate. As long as you don't begin your helper
# methods with _, you only need to worry about conflicts with Merb
# methods that are part of the public API.
#
#
#
# #### Filters
# `#before` is a class method that allows you to specify before filters in
# your controllers. Filters can either be a symbol or string that
# corresponds to a method name to call, or a proc object. if it is a method
# name that method will be called and if it is a proc it will be called
# with an argument of self where self is the current controller object.
# When you use a proc as a filter it needs to take one parameter.
# 
# `#after` is identical, but the filters are run after the action is invoked.
#
# #### Examples
#     before :some_filter
#     before :authenticate, :exclude => [:login, :signup]
#     before :has_role, :with => ["Admin"], :exclude => [:index, :show]
#     before Proc.new { some_method }, :only => :foo
#     before :authorize, :unless => :logged_in?
#
# You can use either `:only => :actionname` or `:exclude => [:this, :that]`,
# but not both at once. `:only` will only run before the listed actions and
# `:exclude` will run for every action that is not listed.
#
# Merb's before filter chain is very flexible. To halt the filter chain you
# use <code>throw :halt</code>. If <code>throw</code> is called with only one 
# argument of <code>:halt</code> the return value of the method 
# <code>filters_halted</code> will be what is rendered to the view. You can 
# override <code>filters_halted</code> in your own controllers to control what 
# it outputs. But the <code>throw</code> construct is much more powerful than 
# just that.
#
# <code>throw :halt</code> can also take a second argument. Here is what that 
# second argument can be and the behavior each type can have:
#
# * `String`:
#   when the second argument is a string then that string will be what
#   is rendered to the browser. Since merb's <code>#render</code> method returns
#   a string you can render a template or just use a plain string:
#
#       throw :halt, "You don't have permissions to do that!"
#       throw :halt, render(:action => :access_denied)
#
# * `Symbol`:
#   If the second arg is a symbol, then the method named after that
#   symbol will be called
#
#       throw :halt, :must_click_disclaimer
#
# * `Proc`:
#   If the second arg is a Proc, it will be called and its return
#   value will be what is rendered to the browser:
#
#       throw :halt, proc { access_denied }
#       throw :halt, proc { Tidy.new(c.index) }
#
# #### Filter Options (`.before, .after, .add_filter, .if, .unless`)
# **`:only<Symbol, Array[Symbol]>`:**
#   A list of actions that this filter should apply to
#
# **`:exclude<Symbol, Array[Symbol]>`:**
#   A list of actions that this filter should *not* apply to
# 
# **`:if<Symbol, Proc>`:**
#   Only apply the filter if the method named after the symbol or calling the proc evaluates to true
# 
# **`:unless<Symbol, Proc>`:**
#   Only apply the filter if the method named after the symbol or calling the proc evaluates to false
#
# **`:with<Array[Object]>`:**
#   Arguments to be passed to the filter. Since we are talking method/proc calls,
#   filter method or Proc should to have the same arity
#   as number of elements in Array you pass to this option.
#
# #### Types (shortcuts for use in this file)
# `Filter`:: `<Array[Symbol, (Symbol, String, Proc)]>`
#
# #### `params[:action]` and `params[:controller]` deprecated
# <code>params[:action]</code> and <code>params[:controller]</code> have been deprecated as of
# the 0.9.0 release. They are no longer set during dispatch, and
# have been replaced by <code>action_name</code> and <code>controller_name</code> respectively.

module Merb
  module InlineTemplates; end
  
  class AbstractController
    include Merb::RenderMixin
    include Merb::InlineTemplates

    extlib_inheritable_accessor :_layout, :_template_root, :template_roots
    extlib_inheritable_accessor :_before_filters, :_after_filters
    extlib_inheritable_accessor :_before_dispatch_callbacks, :_after_dispatch_callbacks

    cattr_accessor :_abstract_subclasses

    # @api plugin
    attr_accessor :body, :action_name, :_benchmarks
    # @api private
    attr_accessor :_thrown_content  

    # Stub so content-type support in RenderMixin doesn't throw errors
    # @api private
    attr_accessor :content_type

    FILTER_OPTIONS = [:only, :exclude, :if, :unless, :with]

    self._before_filters, self._after_filters = [], []
    self._before_dispatch_callbacks, self._after_dispatch_callbacks = [], []

    # We're using abstract_subclasses so that Merb::Controller can have its
    # own subclasses. We're using a Set so we don't have to worry about
    # uniqueness.
    self._abstract_subclasses = Set.new

    # @return [String] The controller name in path form, e.g. "admin/items".
    #
    # @api public
    def self.controller_name() @controller_name ||= self.name.underscore end

    # @return [String] The controller name in path form, e.g. "admin/items".
    #
    # @api public
    def controller_name()      self.class.controller_name                   end

    # Figure out where to look for templates under the _template_root after
    # instantiating the controller. Override this to define a new structure
    # for your app.
    #
    # @param [#to_s] context The controller context (action or template name).
    # @param [#to_s] type The content type. Could be nil. 
    # @param [#to_s] controller The name of the controller. Defaults to being
    #   called with the controller_name.  Set t
    # @todo "Set t" what?
    #
    # @return [String] Indicating where to look for the template for the
    #   current controller, context, and content-type.
    #
    # #### Notes
    # The type is irrelevant for controller-types that don't support
    # content-type negotiation, so we default to not include it in the
    # superclass.
    #
    # @example Modifying the template location
    #     # This would look for templates at controller.action.mime.type instead
    #     # of controller/action.mime.type
    #
    #     def _template_location
    #       "#{params[:controller]}.#{params[:action]}.#{content_type}"
    #     end
    #
    # @api public
    # @overridable
    def _template_location(context, type, controller)
      controller ? "#{controller}/#{context}" : context
    end

    # The location to look for a template.
    #
    # Override this method for particular behaviour.
    #
    # @param [String] template The absolute path to a template, without
    #   template extension.
    # @param [#to_s] type The mime-type of the template that will be
    #   rendered. Defaults to being called with nil.
    #
    # @api public
    # @overridable
    def _absolute_template_location(template, type)
      template
    end

    # Change the template roots.
    #
    # @param [#to_s] root The new path to set the template root to.
    #
    # @api public
    def self._template_root=(root)
      @_template_root = root
      _reset_template_roots
    end

    # Reset the template root based on the @_template_root ivar.
    #
    # @api private
    def self._reset_template_roots
      self.template_roots = [[self._template_root, :_template_location]]
    end

    # @return [Array<Array>] Template roots as pairs of template root path
    #   and template location method.
    #
    # @api plugin
    def self._template_roots
      self.template_roots || _reset_template_roots
    end

    # @param [Array<Array>] roots Template roots as pairs of template root
    #   path and template location method.
    #
    # @api plugin
    def self._template_roots=(roots)
      self.template_roots = roots
    end

    # Returns the list of classes that have specifically subclassed AbstractController.
    # Does not include all decendents.
    #
    # @return [Set] The subclasses.
    #
    # @api private
    def self.subclasses_list() _abstract_subclasses end

    # @param [Merb::AbstractController] klass The controller that is being
    #   inherited from Merb::AbstractController
    #
    # @api private
    def self.inherited(klass)
      _abstract_subclasses << klass.to_s
      helper_module_name = klass.to_s =~ /^(#|Merb::)/ ? "#{klass}Helper" : "Merb::#{klass}Helper"
      # support for unnamed module like "#<Class:0xa2e5e50>::TestController"
      helper_module_name.gsub!(/(::)|[:#<>]/, "\\1")

      klass.class_eval <<-HERE
        include #{make_module(helper_module_name)} rescue nil
      HERE
      super
    end

    # Initialize the controller.
    #
    # This is designed to be overridden in subclasses like {Merb::Controller}
    #
    # @param *args The args are ignored in this class, but we need this
    #   so that subclassed initializes can have parameters
    #
    # @api private
    def initialize(*args)
      @_benchmarks = {}
      @_caught_content = {}
    end

    # Dispatch the request, calling internal before/after dispatch callbacks.
    #
    # If the return value of _call_filters is not :filter_chain_completed,
    # the action is not called, and the return from the filters is used
    # instead.
    #
    # @param [#to_s] action The action to dispatch to. This will be #send'ed
    #   in _call_action. Defaults to :to_s.
    #
    # @return [#to_s] The string, or an object that responds to #to_s, that
    #   was returned from the action.
    # @todo Docs, correctness: It seems that the return value is never used,
    #   and {Merb::Controller#_dispatch} violates the contract by returning
    #   `self`. So for now, avoid using the return value. See ticket #1335.
    #
    # @raise [ArgumentError] Invalid result caught from before filters.
    #
    # @api plugin
    def _dispatch(action)
      self.action_name = action
      self._before_dispatch_callbacks.each { |cb| cb.call(self) }

      caught = catch(:halt) do
        start = Time.now
        result = _call_filters(_before_filters)
        @_benchmarks[:before_filters_time] = Time.now - start if _before_filters

        @body = _call_action(action_name) if result == :filter_chain_completed

        result
      end
  
      @body = case caught
      when :filter_chain_completed  then @body
      when String                   then caught
      # return *something* if you throw halt with nothing
      when nil                      then "<html><body><h1>Filter Chain Halted!</h1></body></html>"
      when Symbol                   then __send__(caught)
      when Proc                     then self.instance_eval(&caught)
      else
        raise ArgumentError, "Threw :halt, #{caught}. Expected String, nil, Symbol, Proc."
      end
      start = Time.now
      _call_filters(_after_filters)
      @_benchmarks[:after_filters_time] = Time.now - start if _after_filters
    
      self._after_dispatch_callbacks.each { |cb| cb.call(self) }
    
      @body
    end
  
    # This method exists to provide an overridable hook for ActionArgs.  It uses #send to call the action method.
    #
    # @param [#to_s] action The action method to dispatch to
    #
    # @api plugin
    # @overridable
    def _call_action(action)
      send(action)
    end
  
    # Calls a filter chain.
    #
    # @param [Array<Filter>] filter_set A set of filters in the form
    #   `[[:filter, rule], [:filter, rule]]`
    #
    # @return [Symbol] `:filter_chain_completed.`
    #
    # #### Notes
    # Filter rules can be Symbols, Strings, or Procs.
    #
    # * *Symbols or Strings:*
    #   Call the method represented by the `Symbol` or `String`.
    # * *Procs:*
    #   Execute the `Proc`, in the context of the controller (self will be the
    #   controller)
    #
    # @api private
    def _call_filters(filter_set)
      (filter_set || []).each do |filter, rule|
        if _call_filter_for_action?(rule, action_name) && _filter_condition_met?(rule)
          case filter
          when Symbol, String
            if rule.key?(:with)
              args = rule[:with]
              send(filter, *args)
            else
              send(filter)
            end
          when Proc then self.instance_eval(&filter)
          end
        end
      end
      return :filter_chain_completed
    end

    # Determine whether the filter should be called for the current action using :only and :exclude.
    #
    # @param [Hash] rule Rules for the filter.
    # @option rule [Array] :only Optional list of actions to fire. If given,
    #   action_name must be a part of it for this function to return true.
    # @option rule [Array] :exclude Optional list of actions not to fire. If
    #   given, action_name must not be a part of it for this function to
    #   return true.
    # @param [#to_s] action_name The name of the action to be called.
    #
    # @return [Boolean] True if the action should be called.
    #
    # @api private
    def _call_filter_for_action?(rule, action_name)
      # Both:
      # * no :only or the current action is in the :only list
      # * no :exclude or the current action is not in the :exclude list
      (!rule.key?(:only) || rule[:only].include?(action_name)) &&
      (!rule.key?(:exclude) || !rule[:exclude].include?(action_name))
    end

    # Determines whether the filter should be run based on the conditions passed (:if and :unless)
    #
    # @param [Hash] rule Rules for the filter.
    # @option rule [Array] :if Optional conditions that must be met for
    #   the filter to fire.
    # @option rule [Array] :unless Optional conditions that must not be
    #   met for the filter to fire.
    #
    # @return [Boolean] True if the conditions are met.
    #
    # @api private
    def _filter_condition_met?(rule)
      # Both:
      # * no :if or the if condition evaluates to true
      # * no :unless or the unless condition evaluates to false
      (!rule.key?(:if) || _evaluate_condition(rule[:if])) &&
      (!rule.key?(:unless) || ! _evaluate_condition(rule[:unless]))
    end

    # Evaluates a filter condition (:if or :unless)
    #
    # @param [Symbol, Proc] condition The condition to evaluate.
    #
    # @raise [ArgumentError] Condition not a Symbol or Proc.
    #
    # @return [Boolean] True if the condition is met.
    #
    # #### Alternatives
    # If condition is a symbol, it will be send'ed. If it is a Proc it will be
    # called directly with self as an argument.
    #
    # @api private
    def _evaluate_condition(condition)
      case condition
      when Symbol then self.send(condition)
      when Proc then self.instance_eval(&condition)
      else
        raise ArgumentError,
              'Filter condtions need to be either a Symbol or a Proc'
      end
    end

    # Adds a filter to the after filter chain.
    #
    # @param [Symbol, Proc] filter The filter to add.
    # @param [Hash] opts Filter options (see class documentation under
    #   *Filter Options*).
    # @param &block A block to use as a filter if filter is nil.
    #
    # #### Notes
    # If the filter already exists, its options will be replaced with opts.
    #
    # @api public
    def self.after(filter = nil, opts = {}, &block)
      add_filter(self._after_filters, filter || block, opts)
    end

    # Adds a filter to the before filter chain.
    #
    # (see AbstractController#after)
    #
    # @api public
    def self.before(filter = nil, opts = {}, &block)
      add_filter(self._before_filters, filter || block, opts)
    end
     
    # Removes a filter from the after filter chain.
    # This removes the filter from the filter chain for the whole
    # controller and does not take any options.
    #
    # @param [Symbol, String] filter A filter name to skip.
    #
    # @api public
    def self.skip_after(filter)
      skip_filter(self._after_filters, filter)
    end
  
    # Removes a filter from the before filter chain.
    #
    # (see AbstractController#skip_after)
    #
    # @api public
    def self.skip_before(filter)
      skip_filter(self._before_filters , filter)
    end

    # Generate URLs.
    #
    # @see Merb::Router.url
    #
    # @api public
    def url(name, *args)
      args << {}
      Merb::Router.url(name, *args)
    end
  
    alias_method :relative_url, :url

    # Returns the absolute URL including the passed protocol and host.
    #
    # This uses the same arguments as the {#url} method, with added requirements
    # of protocol and host options. 
    #
    # @api public
    def absolute_url(*args)
      # FIXME: arrgh, why request.protocol returns http://?
      # :// is not part of protocol name
      options  = extract_options_from_args!(args) || {}
      protocol = options.delete(:protocol)
      host     = options.delete(:host)
    
      raise ArgumentError, "The :protocol option must be specified" unless protocol
      raise ArgumentError, "The :host option must be specified"     unless host
    
      args << options
    
      protocol + "://" + host + url(*args)
    end
  
    # Generates a URL for a single or nested resource.
    #
    # @see Merb::Router.resource
    #
    # @api public
    def resource(*args)
      args << {}
      Merb::Router.resource(*args)
    end

    # Calls the capture method for the selected template engine.
    #
    # @param *args Arguments to pass to the block.
    # @param &block The block to call.
    #
    # @return [String] The output of a template block or the return value
    #   of a non-template block converted to a string.
    #
    # @api public
    def capture(*args, &block)
      ret = nil

      captured = send("capture_#{@_engine}", *args) do |*args|
        ret = yield *args
      end

      # return captured value only if it is not empty
      captured.empty? ? ret.to_s : captured
    end

    # Calls the concatenate method for the selected template engine.
    #
    # @param [String] str The string to concatenate to the buffer.
    # @param [Binding] binding The binding to use for the buffer.
    #
    # @api public
    def concat(str, binding)
      send("concat_#{@_engine}", str, binding)
    end

    private
    # Adds a filter to the specified filter chain.
    #
    # @param [Array<Filter>] filters The filter chain that this should be added to.
    # @param [Filter] filter A filter that should be added.
    # @param [Hash] opts Filter options (see class documentation under *Filter Options*).
    #
    # @raise [ArgumentError] Both :only and :exclude, or :if and :unless
    #   given, if filter is not a Symbol, String or Proc, or if an unknown
    #   option is passed.
    #
    # @api private
    def self.add_filter(filters, filter, opts={})
      raise(ArgumentError,
        "You can specify either :only or :exclude but 
         not both at the same time for the same filter.") if opts.key?(:only) && opts.key?(:exclude)
       
       raise(ArgumentError,
         "You can specify either :if or :unless but 
          not both at the same time for the same filter.") if opts.key?(:if) && opts.key?(:unless)
        
      opts.each_key do |key| raise(ArgumentError,
        "You can only specify known filter options, #{key} is invalid.") unless FILTER_OPTIONS.include?(key)
      end

      opts = normalize_filters!(opts)
    
      case filter
      when Proc
        # filters with procs created via class methods have identical signature
        # regardless if they handle content differently or not. So procs just
        # get appended
        filters << [filter, opts]
      when Symbol, String
        if existing_filter = filters.find {|f| f.first.to_s == filter.to_s}
          filters[ filters.index(existing_filter) ] = [filter, opts]
        else
          filters << [filter, opts]
        end
      else
        raise(ArgumentError, 
          'Filters need to be either a Symbol, String or a Proc'
        )        
      end
    end  

    # Skip a filter that was previously added to the filter chain. Useful in
    # inheritence hierarchies.
    #
    # @param [Array<Filter>] filters The filter chain that this should be removed from.
    # @param [Filter] filter A filter that should be removed.
    #
    # @raise [ArgumentError] filter not Symbol or String.
    #
    # @api private
    def self.skip_filter(filters, filter)
      raise(ArgumentError, 'You can only skip filters that have a String or Symbol name.') unless
        [Symbol, String].include? filter.class

      Merb.logger.warn("Filter #{filter} was not found in your filter chain.") unless
        filters.reject! {|f| f.first.to_s[filter.to_s] }
    end

    # Ensures that the passed in hash values are always arrays.
    #
    # @param [Hash] opts Options for the filters
    # @option opts [Symbol, Array<Symbol>] :only A list of actions.
    # @option opts [Symbol, Array<Symbol>] :exclude A list of actions.
    #
    # @example Use like:
    #     normalize_filters!(:only => :new) #=> {:only => [:new]}
    #
    # @api public
    def self.normalize_filters!(opts={})
      opts[:only]     = Array(opts[:only]).map {|x| x.to_s} if opts[:only]
      opts[:exclude]  = Array(opts[:exclude]).map {|x| x.to_s} if opts[:exclude]
      return opts
    end
  end
end
