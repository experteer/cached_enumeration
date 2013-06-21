module ActiveRecord
  class Base
    def self.cache_enumeration(params = {})
      ActiveRecord::Caching::Enumeration.cache_enumeration(self, params)
    end
  end

  module Caching
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
find_by_XY / by_XY for all hashed attributes
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
    module Enumeration
      def self.cache_enumeration(base, params)
        defaults = {
          :order => 'id',
          :hashed => ['id', 'name'],
          :constantize => 'name',
        }
        raise "unexpected parameters #{(params.keys - defaults.keys).inspect}, only #{defaults.keys.inspect} are understood" unless (params.keys - defaults.keys).empty?

        params = defaults.merge(params)
        params[:hashed] << 'id' unless params[:hashed].include? 'id'

        base.cattr_accessor :cache_all
        base.cattr_accessor :caching
        base.cattr_accessor :cache_params
        base.cache_params = params

        base.extend(ClassMethods)
        base_singleton = class << base;
          self
        end
        base.cache_params[:hashed].each do |att|
          base.cattr_accessor "cache_by_#{att}"
          if att == 'id'
            base_singleton.__send__(:define_method, "find_by_#{att}") do |key|
              load_caches
              self.send("cache_by_#{att}")[key.to_i]
            end
          else
            base_singleton.__send__(:define_method, "find_by_#{att}") do |key|
              load_caches
              self.send("cache_by_#{att}")[key]
            end
          end
          base_singleton.__send__(:alias_method, "by_#{att}", "find_by_#{att}")
        end
      end

      module ClassMethods
        def cached?
          !!(cache_all && !caching)
        end


        #def find(*args)
        #  logger.debug("call to #{name}.find( #{args.inspect[1..-2]} )")
        #  super
        #end

        def find_from_ids(ids, options)
          load_caches
          if options.empty? || !options.values.detect { |v| v }
            # no options or no used options
            expects_array = ids.first.kind_of?(Array)
            return ids.first if expects_array && ids.first.empty?

            ids = ids.flatten.compact.uniq.collect { |id| id = id.respond_to?(:quoted_id) ? id.quoted_id.to_i : id.to_i }
            case ids.size
              when 0
                raise ActiveRecord::RecordNotFound, "Couldn't find #{name} without an ID"
              when 1
                result = cache_by_id[ids[0]] || raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{ids[0]}")
                expects_array ? [result] : result
              else
                ids.inject([]) do |res, id|
                  res << (cache_by_id[id] || raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}"))
                end
            end
          else # we do not handle options
            super
          end
        end

        def cached_all
          load_caches
          cache_all
        end

        private
        def load_caches(force=false)
          return false if (cached? && !force) || caching
          self.caching=true #should use some better form of reentry protection

          hashes = Hash.new do |hash, key|
            hash[key]=Hash.new
          end
          self.cache_all= find(:all, :order => cache_params[:order]).freeze
          self.cache_all.each do |entry|
            entry.freeze # no one should mess with the entries
            cache_params[:hashed].each do |att|
              hashes[att][entry.send(att)] = entry
            end
          end
          hashes.each do |att, hash|
            self.send("cache_by_#{att}=", hash.freeze)
          end
          create_constants if cache_params[:constantize]

          self.caching=false
          true
        end

        private :load_caches

        def const_missing(const_name)
          if load_caches
            self.const_get(const_name) #if just created then return
          else
            super
          end
        end


        def create_constants
          #puts "creating constants #{self.name}"
          cache_all.each do |model|

            const_name=model.send(cache_params[:constantize]).upcase
            #puts "caching: #{self.name}::#{const_name}"
            const_set const_name, model
          end
        end


      end
    end
  end
end
