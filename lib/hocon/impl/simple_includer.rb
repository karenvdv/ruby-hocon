# encoding: utf-8

require 'stringio'
require 'hocon/impl'
require 'hocon/impl/full_includer'
require 'hocon/impl/url'
require 'hocon/impl/config_impl'
require 'hocon/config_error'
require 'hocon/config_syntax'
require 'hocon/impl/simple_config_object'
require 'hocon/impl/simple_config_origin'

class Hocon::Impl::SimpleIncluder < Hocon::Impl::FullIncluder

  ConfigBugorBrokenError = Hocon::ConfigError::ConfigBugOrBrokenError
  ConfigIOError = Hocon::ConfigError::ConfigIOError
  SimpleConfigObject = Hocon::Impl::SimpleConfigObject
  SimpleConfigOrigin = Hocon::Impl::SimpleConfigOrigin


  def initialize(fallback)
    @fallback = fallback
  end

  # ConfigIncludeContext does this for us on its options
  def self.clear_for_include(options)
    # the class loader and includer are inherited, but not this other stuff
    options.set_syntax(nil).set_origin_description(nil).set_allow_missing(true)
  end


  # this is the heuristic includer
  def include(context, name)
    obj = self.class.include_without_fallback(context, name)

    # now use the fallback includer if any and merge its result
    if ! (@fallback.nil?)
      obj.with_fallback(@fallback.include(context, name))
    else
      obj
    end
  end

  # the heuristic includer in static form
  def self.include_without_fallback(context, name)
    # the heuristic is valid URL then URL, else relative to including file;
    # relativeTo in a file falls back to classpath inside relativeTo().

    url = nil
    begin
      url = Hocon::Impl::Url.new(name)
    rescue Hocon::Impl::Url::MalformedUrlError => e
      url = nil
    end

    if !(url.nil?)
      include_url_without_fallback(context, url)
    else
      source = RelativeNameSource.new(context)
      from_basename(source, name, context.parse_options)
    end
  end

  class NameSource
    def name_to_parseable(name, parse_options)
      raise Hocon::ConfigError::ConfigBugOrBrokenError,
            "name_to_parseable must be implemented by subclass"
    end
  end

  class RelativeNameSource < NameSource
    def initialize(context)
      @context = context
    end
  end

  # this function is a little tricky because there are three places we're
  # trying to use it; for 'include "basename"' in a .conf file, for
  # loading app.{conf,json,properties} from classpath, and for
  # loading app.{conf,json,properties} from the filesystem.
  def self.from_basename(source, name, options)
    obj = nil
    if name.end_with?(".conf") || name.end_with?(".json") || name.end_with?(".properties")
      p = source.name_to_parseable(name, options)

      obj = p.parse(p.options.set_allow_missing(options.allow_missing?))
    else
      conf_handle = source.name_to_parseable(name + ".conf", options)
      json_handle = source.name_to_parseable(name + ".json", options)
      props_handle = source.name_to_parseable(name + ".properties", options)
      got_something = false
      fails = []

      syntax = options.get_syntax

      obj = SimpleConfigObject.empty(SimpleConfigOrigin.new_simple(name))
      if syntax.nil? || (syntax == Hocon::ConfigSyntax::CONF)
        begin
          obj = conf_handle.parse(conf_handle.options.set_allow_missing(false)).
                  set_syntax(Hocon::ConfigSyntax::CONF)
          got_something = true
        rescue ConfigIOError => e
          fails << e
        end
      end

      if syntax.nil? || (syntax == Hocon::ConfigSyntax::JSON)
        begin
          parsed = json_handle.parse(json_handle.options.set_allow_missing(false).
                                         set_syntax(Hocon::ConfigSyntax::JSON))
          obj = obj.with_fallback(parsed)
          got_something = true
        rescue ConfigIOError => e
          fails << e
        end
      end

      if syntax.nil? || (syntax == Hocon::ConfigSyntax::PROPERTIES)
        begin
          parsed = props_handle.parse(props_handle.options).set_allow_missing(false).
                      set_syntax(Hocon::ConfigSyntax::PROPERTIES)
          obj = obj.with_fallback(parsed)
          got_something = true
        rescue ConfigIOError => e
          fails.add(e)
        end
      end

      if (! options.allow_missing?) && (! got_something)
        if Hocon::Impl::ConfigImpl.trace_loads_enabled
          # the individual exceptions should have been logged already
          # with tracing enabled
          Hocon::Impl::ConfigImpl.trace("Did not find '#{name}'" +
            " with any extension (.conf, .json, .properties); " +
            "exceptions should have been logged above.")
        end

        if fails.empty?
          # this should not happen
          raise ConfigBugOrBrokenError, "should not be reached: nothing found but no exceptions thrown"
        else
          sb = StringIO.new
          fails.each do |t|
            sb << t
            sb << ", "
          end
          raise ConfigIOError.new(SimpleConfigOrigin.new_simple(name), sb.to_s, fails[0])
        end
      elsif !got_something
        if Hocon::Impl::ConfigImpl.trace_loads_enabled
          Hocon::Impl::ConfigImpl.trace("Did not find '#{name}'" +
            " with any extension (.conf, .json, .properties); but '#{name}'" +
            " is allowed to be missing. Exceptions from load attempts should have been logged above.")
        end
      end
    end

    obj
  end

  class Proxy < Hocon::Impl::FullIncluder
    def initialize(delegate)
      @delegate = delegate
    end
    ## TODO: port remaining implementation when needed
  end

  def self.make_full(includer)
    if includer.is_a?(Hocon::Impl::FullIncluder)
      includer
    else
      Proxy.new(includer)
    end
  end
end
