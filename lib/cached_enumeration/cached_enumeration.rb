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
  cached_all

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


    def cached?
      @status == :cached
    end

    def caching?
      @status == :caching
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
      end

    end

    def patch_const_missing(base_singleton)
      # No class caching in derived classes
      # Introduced to avoid issues with Sales::ProductDomain
      # and it's descendents
      return if @klass.parent.respond_to? :const_missing_with_cache_enumeration
      @klass.extend ConstMissing
      base_singleton.alias_method_chain :const_missing, :cache_enumeration
    end

    module ConstMissing
      def const_missing_with_cache_enumeration(const_name)
        if cache_enumeration.cache! # if we just cached
          self.const_get(const_name) # try again
        else
          const_missing_without_cache_enumeration(const_name) # fails as usual
        end
      end
    end
  end
end

class ActiveRecord::Relation

  # There should be a Rails 4 version of this gem
  # which can remove the need for cache_enumeration_unmodified_query?
  # because +all+ does not take arguments anymore.
  def all_with_cache_enumeration(*args)
    if cache_enumeration_unmodified_query? && args.empty? && cache_enumeration?
      cache_enumeration.all
    else
      all_without_cache_enumeration(*args)
    end
  end

  alias_method_chain :all, :cache_enumeration

  private

  def cache_enumeration_unmodified_query?
    where_values.blank? &&
      cache_enumeration_unmodified_but_where?
  end

  def cache_enumeration_unmodified_but_where?
    limit_value.blank? && order_values.blank? && select_values.blank? &&
      includes_values.blank? && preload_values.blank? &&
      readonly_value.nil? && joins_values.blank? &&
      !@klass.locking_enabled?
  end
end


module ActiveRecord
  class Base
    class << self
      def cache_enumeration(params = {})
        if params[:reset]
          @cache_enumeration = nil
        else
          @cache_enumeration ||= CachedEnumeration::Cache.new(self, params)
        end
      end

      def cache_enumeration?
        !@cache_enumeration.nil?
      end

      def cached_all
        cache_enumeration.all
      end

    end
  end
end
