module CachedEnumeration
=begin rdoc
Provide cached access to enumeration values

Usage: In your ActiveRecord class, add

  cache_enumeration <params>

Parameters are
  :order  order of items in cached_all (default: 'id')
  :hashed list of attributes to provide hashes for (default: [ 'id', 'name' ];
          id will always be added to that list, if missing
  :constantize  attribute to provide constants for (default: 'name')
              use nil, not to generate constants

Cached methods are:
  by_XY for all hashed attributes
  find_by_XY for all hashed attributes
  cached_all
  all
  cached_first
  first

Besides, constants using the upcase name are set up providing the entries

Note that all objects (arrays, maps and the models themselfs) are frozen
to avoid unintentional changes.

Cachability of enumerations does not imply that all enumeration access should
be cached. This is a question that needs to be well thought depending on the
size of the enumeration and the number of accesses to the cached data.
=end
  class Cache
    attr_reader :options

    def initialize(base, params)
      @options = init_options(params)
      @cache = {} # cache by keys
      @all = [] # cache of all
      @status = :uncached # can be :uncached,:caching,:cached
      @klass = base

      base_singleton = class << base;
        self
      end

      patch_const_missing(base_singleton) if @options[:constantize]
      create_by_methods(base_singleton)
      alias_all_method(base_singleton)
      alias_first_method(base_singleton)
    end

    def all
      ensure_caches
      @all
    end

    # Returns a value from a cache
    # @param String att name of the attribute
    # @param String key value of the attribute
    def get_by(att, key)
      ensure_caches
      @cache[att][key]
    end

    # Forces a cache
    # @return Boolean true is it just cached, false if it was already cached
    def cache!
      ensure_caches
    end

    def cached?
      @status == :cached
    end

    def caching?
      @status == :caching
    end

    private

    def ensure_caches
      return false if cached? || caching?
      @status = :caching

      hashes = Hash.new do |hash, key|
        hash[key] = Hash.new
      end

      @all = @klass.order(@options[:order]).all.freeze
      @all.each do |entry|
        entry.freeze # no one should mess with the entries
        @options[:hashed].each do |att|
          hashes[att][entry.send(att)] = entry
        end
      end

      create_constants if @options[:constantize]

      @cache = hashes
      @status = :cached
      true
    end

    def init_options(params)
      defaults = {
        :order => 'id',
        :hashed => ['id', 'name'],
        :constantize => 'name',
      }

      # params check logic
      params_diff = params.keys - defaults.keys
      raise ArgumentError.new("unexpected parameters #{params_diff.inspect}, only #{defaults.keys.inspect} are understood") unless params_diff.empty?

      params = defaults.merge(params)
      params[:hashed] << 'id' unless params[:hashed].include? 'id'
      params[:hashed].map! do |name|
        name.to_s
      end
      params
    end

    def create_constants
      proc = @options[:constantize].respond_to?(:call)

      @all.each do |model|
        if proc
          const_name = @options[:constantize].call(model).upcase
        else
          const_name = model.send(@options[:constantize]).upcase
        end

        @klass.const_set const_name, model
      end
    end

    def alias_all_method(base_singleton)
      base_singleton.__send__(:define_method, :cached_all) do
        cache_enumeration.all
      end
      base_singleton.__send__(:define_method, :all_with_cache_enumeration) do |*args|
        cache_enumeration.cached? && args.empty? ? cached_all : all_without_cache_enumeration(*args)
      end
      base_singleton.__send__(:alias_method_chain, :all, :cache_enumeration)
    end

    def alias_first_method(base_singleton)
      base_singleton.__send__(:define_method, :cached_first) do
        cache_enumeration.all.first
      end
      base_singleton.__send__(:define_method, :first_with_cache_enumeration) do |*args|
        cache_enumeration.cached? && args.empty? ? cached_first : first_without_cache_enumeration(*args)
      end
      base_singleton.__send__(:alias_method_chain, :first, :cache_enumeration)
    end

    def create_by_methods(base_singleton)
      @options[:hashed].each do |att|
        if att == 'id'
          base_singleton.__send__(:define_method, "by_#{att}") do |key|
            cache_enumeration.get_by(att, key.to_i)
          end
        else
          base_singleton.__send__(:define_method, "by_#{att}") do |key|
            cache_enumeration.get_by(att, key)
          end
        end
        base_singleton.__send__(:alias_method, "find_by_#{att}", "by_#{att}")
      end
      if @options[:hashed].include?("id")
        base_singleton.__send__(:define_method, :find_with_cache_enumeration) do |*args|
          if cache_enumeration.cached? && args.length == 1 && args.first.respond_to?(:to_i)
            by_id(args.first).tap{|res| raise ActiveRecord::RecordNotFound if res.nil? }
          else
            find_without_cache_enumeration(*args)
          end
        end
        base_singleton.__send__(:alias_method_chain, :find, :cache_enumeration)
      end
    end

    def patch_const_missing(base_singleton)
      base_singleton.__send__(:define_method, :const_missing_with_cache_enumeration) do |const_name|
        if cache_enumeration.cached? || cache_enumeration.caching?
          const_missing_without_cache_enumeration(const_name)
        elsif cache_enumeration.cache!
          self.const_get(const_name)
        end
      end
      base_singleton.__send__(:alias_method_chain, :const_missing, :cache_enumeration)
    end
  end

  class NoCache
    def cached?
      false
    end

    def caching?
      false
    end

    def cache!
      false
    end
  end
end

module ActiveRecord
  class Base
    class << self
      def cache_enumeration(params = {})
        if params[:reset]
          @cache_enumeration = nil
        elsif self.parent.respond_to? :const_missing_with_cache_enumeration
          @cache_enumeration ||= CachedEnumeration::NoCache.new
        else
          @cache_enumeration ||= CachedEnumeration::Cache.new(self, params)
        end
      end
    end
  end
end
