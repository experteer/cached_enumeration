# CachedEnumeration

Loads your active record objects into memory so you don't have to include them.

Currently only working for the ActiveRecord/Rails 2.3 series. A Rails 3.2 version is on the way.

## Installation

Add this line to your application's Gemfile:

    gem 'cached_enumeration'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cached_enumeration

## Usage

`
class Geneder < ActiveRecord::Base
  cache_enumeration :order => 'name', :hashed => [:id,:name], :constantize => true

`

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
