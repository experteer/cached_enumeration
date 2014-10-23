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
      #only load if loading not yet in progress
      ensure_caches if @status == :uncached
    end

    def cached?
      @status==:cached
    end

    def order
      @options[:order]
    end

    def first
      @all.first
    end

    private

    def ensure_caches
      return false if cached? || caching?
      @status=:caching

      @cache = Hash.new do |hash, key|
        hash[key]=Hash.new
      end

      # the next line is weird but I want to have to Array so I use select
      # to dereference the relation
      @all = @klass.order(@options[:order]).all.to_a.freeze

      @all.each do |entry|
        @options[:hashed].each do |att|
          @cache[att.to_s][entry.send(att)] = entry.freeze
        end
      end

      create_constants if @options[:constantize]

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
        const_name = if proc
          @options[:constantize].call(model).upcase
        else
          model.send(@options[:constantize]).upcase
        end

        @klass.const_set const_name, model
      end
    end

    def patch_const_missing(base_singleton)
      # no class caching in derived classes!
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

module ActiveRecord
  class Relation
    def to_a_with_cache_enumeration
      res=nil

      if cache_enumeration? && cache_enumeration.cached? && order_is_cached?
        res=case
          when just_modified?(:order)
            #all and the order is cached?
            cache_enumeration.all
          when just_modified?(:limit, :order, :where)
            case
              when limit_value == 1 && where_values.blank?
                # usually the #first case
                [cache_enumeration.first]
              when limit_value == 1 && where_values.present? && where_is_cached?
                # usually "= 1" or "= ?" .first or find or find_by
                [get_by_where]
              when limit_value.blank? && where_values.present? && where_is_cached?
                # usually the association case (where id in (1,2,56,6))
                get_by_where
              else
                to_a_without_cache_enumeration #where is to complicated for us
            end
        end

      end

      if res #got a result the return it
        res
      else
        cache_enumeration.cache! if cache_enumeration?
        to_a_without_cache_enumeration
      end

    end

    alias_method_chain :to_a, :cache_enumeration

    def take_with_cache_enumeration
      if cache_enumeration? && cache_enumeration.cached?
        case
          #when just_modified?(:limit)
          #  cache_enumeration.first #tsk the first value of the default order
          when just_modified?(:where) && where_is_cached?
            get_by_where
          else
            take_without_cache_enumeration
        end
      else
        cache_enumeration.cache! if cache_enumeration?
        take_without_cache_enumeration
      end
    end

    alias_method_chain :take, :cache_enumeration

    private

    def get_by_where
      att_name=where_values[0].left.name
      identifier = where_values[0].right

      if identifier.kind_of?(Array)
        identifier.map do |id|
          cache_enumeration.get_by(att_name, id)
        end.compact
      else
        identifier=bind_values[0][1] if identifier=='?'
        cache_enumeration.get_by(att_name, identifier)
      end
    end

    # just one ascending order which is the same as the cached one or none
    def order_is_cached?
      order_values.empty? || (
      order_values.size == 1 &&
        ((order_values[0].respond_to?(:ascending?) && order_values[0].ascending? &&
          cache_enumeration.order == order_values[0].expr.name) ||
          order_values[0] == cache_enumeration.order #sometimes the order is just as string
        )
      )
    end

    def where_is_cached?
      where_values.size == 1 &&
        where_values[0].kind_of?(Arel::Nodes::Node) &&
        where_values[0].operator == :== &&
        cache_enumeration.hashed_by?(where_values[0].left.name)
    end

    #*modified is an array like :limit, :where, :order, :select, :includes, :preload
    #:readonly
    def just_modified?(*modified)
      return false if @klass.locking_enabled?
      return false if limit_value.present? && !modified.include?(:limit)
      return false if where_values.present? && !modified.include?(:where)
      return false if order_values.present? && !modified.include?(:order)
      return false if select_values.present? && !modified.include?(:select)
      return false if includes_values.present? && !modified.include?(:includes)
      return false if preload_values.present? && !modified.include?(:preload)
      return false if readonly_value.present? && !modified.include?(:readonly)
      return false if joins_values.present? && !modified.include?(:joins)
      true
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
        @cache_enumeration.present?
      end

    end
  end
end
