# CachedEnumeration

Loads your active record objects into memory so you don't have to include them.

## Warning
Prior to Rails 4.2, it was possible to cache using `find`, `find_by` and
`find_by_xyz`, as well as caching associations. Due to some
[performance improvements](http://tenderlovemaking.com/2014/02/19/adequaterecord-pro-like-activerecord.html)
this is not possible anymore. Now there is a SQL statement cache for those
methods, which means that they do not have to transform the Rails code to SQL
more than once. Unfortunately, that process was used by this gem to hook into
ActiveRecrod and prevent database access if possible.

Instead of the find methods, use `where().first`. Unfortunately, there is no
equivalent for the associations.

## Installation

Add this line to your application's Gemfile:

    gem 'cached_enumeration'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cached_enumeration

## Usage

    class Geneder < ActiveRecord::Base
      cache_enumeration :order => 'name', :hashed => [:id,:name], :constantize => true


Now the following situations are cached:
 * `Gender.where(name: 'male).first`
 * `Gender.all`
 * `Gender.order('name').all`
 * `Gender::MALE`
 * `Gender::FEMALE`

If a Profile belongs_to a Gender you can simply write:
    `profile.gender`
end no DB query whill be executed.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Write specs!
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request
