module CachedEnumeration
=begin rdoc
provide cached access to enumeration values
       
usage: add cache_enumeration <params> to ActiveRecord class

parameters are
  :order  order of items in cached_all (default: 'id')
  :hashed list of attributes to provide hashes for (default: [ 'id', 'name' ];
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
#      p params
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
#create_find_by_methods(base_singleton)
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
      key=key.to_i if att.to_s == "id"
      @cache[att.to_s][key]
    end

    def hashed_by?(att)
      options[:hashed].include?(att.to_s)
    end

    #forces a cache
    #@return Boolean true is it just cached, false if it was already cached
    def cache!
      ensure_caches
    end

    def cached?
      @status==:cached
    end

    def order
      @options[:order]
    end

    def first
      @cache[order].first[1]
    end

    private

    def ensure_caches
      return false if cached? || caching?
      @status=:caching

      hashes = Hash.new do |hash, key|
        hash[key]=Hash.new
      end

      # the next line is weird but I want to have to Array so I use select
      # to dereference the relation
      @all = @klass.order(@options[:order]).all
      @klass.connection.cached_enumeration_cache do
        @klass.order(@options[:order]).all.to_a #just to execute the query
      end

      @all.each do |entry|
        #entry.freeze # no one should mess with the entries
        @options[:hashed].each do |att|
          #         puts "hashing: #{att}"
          hashes[att.to_s][entry.send(att)] = entry.freeze
        end
      end

      create_constants if @options[:constantize]

      @cache=hashes
      @klass.logger.try(:info, "Filled cache of #{@klass.name}: #{@options.inspect}")
      @status=:cached
      true
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

    def patch_const_missing(base_singleton)
      # no class caching in derived classes
      # introduced to avoid issues with Sales::ProductDomain 
      # and it's descendents
      return if @klass.parent.respond_to? :const_missing_with_cache_enumeration
      @klass.extend ConstMissing
      base_singleton.alias_method_chain :const_missing, :cache_enumeration
    end

    module ConstMissing
      def const_missing_with_cache_enumeration(const_name)
        if cache_enumeration.cache! #if we just cached
          self.const_get(const_name) #try again
        else
          const_missing_without_cache_enumeration(const_name) #fails as usual
        end
      end
    end
  end
end
require 'active_record/connection_adapters/abstract_adapter'

module ActiveRecord
  module ConnectionAdapters
    class AbstractAdapter
      def cached_enumeration_cache_clear
        #puts "clearing"
        @cached_enumeration_cache = Hash.new { |h, sql| h[sql] = {} }
      end

      def cached_enumeration_cache
        #NOT! THREADSAVE
        old, @cached_enumeration_cache_enabled = @cached_enumeration_cache_enabled, true
        yield
      ensure
        @cached_enumeration_cache_enabled=old
      end

      def select_all_with_cache_enumeration(arel, name = nil, binds = [])
        if !locked?(arel) #never ever cache things like 'FOR UPDATE'
          arel, binds = binds_from_relation arel, binds
          sql = to_sql(arel, binds)
          debugger
          cached_enumeration_cache_sql(sql, binds) { select_all_without_cache_enumeration(sql, name, binds) } ||
            select_all_without_cache_enumeration(arel, name, binds)
        else
          select_all_without_cache_enumeration(sql, name, binds)
        end

      end

      alias_method_chain :select_all, :cache_enumeration

      def cached_enumeration_cache_sql(sql, binds)
        @cached_enumeration_cache ||= Hash.new { |h, sql| h[sql] = {} }

        if @cached_enumeration_cache[sql].key?(binds)
          #ActiveSupport::Notifications.instrument("sql.active_record",
          #                                        :sql => sql,
          # :binds => binds,
          # :name => "ENUM CACHE",
          # :connection_id => object_id)
          @cached_enumeration_cache[sql][binds]
        else
          if @cached_enumeration_cache_enabled
            res=@cached_enumeration_cache[sql][binds]=yield
            #puts "caching ----->"
            #p @cached_enumeration_cache
            res
          else
            nil #this is important as this is a sign that the normal caching should be done
          end
        end
      end

    end
  end

#I override find_one, find_some and all so they do a cache lookup first
  class Relation

    def first_with_cache_enumeration(limit=nil)
      unless limit
        equal_op = nil

        if cache_enumeration? && cache_enumeration_unmodified_but_where?
          case
            when where_values.blank?
              cache_enumeration.first #tsk the first value of the default order
            when where_values.size == 1 &&
              where_values[0].kind_of?(Arel::Nodes::Node) &&
              where_values[0].operator == :== &&
              cache_enumeration.hashed_by?(where_values[0].left.name)

              cache_enumeration.get_by(where_values[0].left.name, where_values[0].right)
            else
              first_without_cache_enumeration
          end
        else
          first_without_cache_enumeration
        end

      else
        first_without_cache_enumeration
      end
    end

    alias_method_chain :first, :cache_enumeration

    def find_by_with_cache_enumeration(*args)

      if args[0].kind_of?(Hash)
        by_key=args[0].keys.first
        #p "lookup: #{by_key}"
        if args[0].size==1 && cache_enumeration.hashed_by?(by_key)
          res=cache_enumeration.get_by(by_key, args[0][by_key])
          #p "found: #{by_key} #{res.inspect}"
          res
        end
      else
        find_by_without_cache_enumeration(*args)
      end
    end

    alias_method_chain :find_by, :cache_enumeration

    def find_one_with_cache_enumeration(id)
      find_some([id]).first
    end

    alias_method_chain :find_one, :cache_enumeration

    def find_some_with_cache_enumeration(ids)
      if cache_enumeration_unmodified_query?
        result=ids.inject([]) do |res, id|
          res << find_by(:id => id)
        end.compact

        if result.size == ids.size #we don't have to handle limit_value and offset_value
          result
        else
          raise_record_not_found_exception!(ids, result.size, ids.size)
        end

      else
        find_some_without_cache_enumeration(ids)
      end

    end

    alias_method_chain :find_some, :cache_enumeration

    private

    def cache_enumeration_unmodified_query?
      where_values.blank? &&
        cache_enumeration_unmodified_but_where?
    end

    #the ordering of first is "id"
    def cache_enumeration_unmodified_but_where?
      limit_value.blank? && order_values.blank? && (select_values.blank? || select_values.empty?) &&
        includes_values.blank? && preload_values.blank? &&
        readonly_value.nil? && joins_values.blank? &&
        !@klass.locking_enabled?
    end
  end


  class Base
    class << self
      def cache_enumeration(params = {})
        #p "init: #{params.inspect}"
        if params.delete(:reset)
          @cache_enumeration = nil
        end

        @cache_enumeration ||= CachedEnumeration::Cache.new(self, params)

      end

      def cache_enumeration?
        !@cache_enumeration.nil?
      end

    end
  end
end
