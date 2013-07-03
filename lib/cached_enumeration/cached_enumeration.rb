module CachedEnumeration
=begin rdoc
provide cached access to enumeration values
       
usage: add cache_enumeration <params> to ActiveRecord class

parameters are
  :order  order of items in cached_all (default: 'id')
  :hashed list of attributes to provide hashes for (default: [ 'id', 'name' ];
          id will always be added to that list, if missing
  :constantize  attribute to provide constants for (default: 'name')
              use nil, not to generate constants

cached methods are:
find_from_ids( <id> ) or find_from_ids( [ <id>, <id>, ... ] )
   providing cached  find( <id> ) or find( [ <id>, <id>, ... ] )
find_by_XY / by_XY for all hashed attributes (by_XY is deprecated)
cached_all 

besides constants using the upcase name are set up providing the entries

note that all objects (arrays, maps and the models themselfs) are frozen
to avoid unintentional changes.

Cachability of enumerations does not imply that all enumeration access should
be cached. This is a question that needs to be well thought depending on the
size of the enumeration and the number of accesses to the cached data.

The by_XY finder should be avoided as the find_by_XY will be available with
and without cache.
=end
  class Cache
    attr_reader :options

    def initialize(base, params)
      @options=init_options(params)
      @cache={} #cache by keys
      @all=[] #cache of all
      @status=:uncached #can be :uncached,:cashing,:cached
      @klass=base

      #base.extend(ClassMethods)
      #base.reset_column_information
      base_singleton = class << base;
        self
      end

      patch_const_missing(base_singleton) if @options[:constantize]
      create_find_by_methods(base_singleton)
    end

    def all
      ensure_caches
      @all
    end

    #returns a value from a cache
    #@param String att name of the attribute
    #@param String key value of the attribute
    def get_by(att, key)
      ensure_caches
      @cache[att][key]
    end

    #forces a cache
    #@return Boolean true is it just cached, false if it was already cached
    def cache!
      ensure_caches
    end

    private

    def ensure_caches
      return false if cached? || caching?
      @status=:caching

      hashes = Hash.new do |hash, key|
        hash[key]=Hash.new
      end

      @all = @klass.order(@options[:order]).all.freeze
      @all.each do |entry|
        entry.freeze # no one should mess with the entries
        @options[:hashed].each do |att|
          hashes[att][entry.send(att)] = entry
        end
      end

      create_constants if @options[:constantize]

      @cache=hashes
      @status=:cached
      true
    end


    def cached?
      @status==:cached
    end

    def caching?
      @status==:caching
    end

    def init_options(params)
      defaults = {
        :order => 'id',
        :hashed => ['id', 'name'],
        :constantize => 'name',
      }
      #params check logic
      params_diff=params.keys - defaults.keys
      raise ArgumentError.new("unexpected parameters #{params_diff.inspect}, only #{defaults.keys.inspect} are understood") unless params_diff.empty?

      params = defaults.merge(params)
      params[:hashed] << 'id' unless params[:hashed].include? 'id'
      params[:hashed].map! do |name|
        name.to_s
      end
      params
    end

    def create_constants
      #puts "creating constants #{self.name}"
      proc=@options[:constantize].respond_to?(:call)

      @all.each do |model|
        if proc
          const_name=@options[:constantize].call(model).upcase
        else
          const_name=model.send(@options[:constantize]).upcase
        end

        #puts "caching: #{self.name}::#{const_name}"
        @klass.const_set const_name, model
      end
    end

    def create_find_by_methods(base_singleton)
      @options[:hashed].each do |att|
        if att == 'id'
          base_singleton.__send__(:define_method, "find_by_#{att}") do |key|
            #rewrite to use column type
            cache_enumeration.get_by(att, key.to_i)
          end
        else
          base_singleton.__send__(:define_method, "find_by_#{att}") do |key|
            cache_enumeration.get_by(att, key)
          end
        end
        base_singleton.__send__(:alias_method, "by_#{att}", "find_by_#{att}")
      end

    end

    def patch_const_missing(base_singleton)
      @klass.extend ConstMissing
      base_singleton.alias_method_chain :const_missing, :cache_enumeration
    end

    module ConstMissing
      def const_missing_with_cache_enumeration(const_name)
        if cache_enumeration && cache_enumeration.cache! #is we just cache
          self.const_get(const_name) #try again
        else
          super #fails as usual
        end
      end
    end
  end
end

#I override find_one, find_some and all so they do a cache lookup first
class ActiveRecord::Relation
  def find_one_with_cache_enumeration(id)
    if cache_enumeration_unmodified_query? && cache_enumeration?
      cache_enumeration.get_by('id', id) ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}")
    else
      find_one_without_cache_enumeration(id)
    end
  end

  alias_method_chain :find_one, :cache_enumeration

  def find_some_with_cache_enumeration(ids)
    if cache_enumeration_unmodified_query? && cache_enumeration?
      ids.inject([]) do |res, id|
        res << (cache_enumeration.get_by('id', id) ||
          raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}"))
      end
    else
      find_some_without_cache_enumeration(ids)
    end
  end

  alias_method_chain :find_some, :cache_enumeration

  def all_with_cache_enumeration(*args)
    if cache_enumeration_unmodified_query? && cache_enumeration?
      cache_enumeration.all
    else
      all_without_cache_enumeration(*args)
    end
  end

  alias_method_chain :all, :cache_enumeration

  private

  def cache_enumeration_unmodified_query?
    where_values.blank? &&
      limit_value.blank? && order_values.blank? &&
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

      #deprecated as 'all' should work now
      def cached_all
        cache_enumeration.all
      end


    end
  end
end