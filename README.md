# CachedEnumeration

Loads your active record objects into memory so you don't have to include them.

Currently works with Rails 4.2.

## Installation

Add this line to your application's Gemfile:

    gem 'cached_enumeration'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cached_enumeration

## Usage

    class Gender < ActiveRecord::Base
      cache_enumeration :order => 'name', :hashed => [:id,:name], :constantize => true


Now the following situations are cached:

* `Gender.find(1)`
* `Gender.by_id(1)`
* `Gender.find_by_name('male')`
* `Gender.all`
* `Gender::MALE`
* `Gender::FEMALE`

## Development

    docker run -it \
      --name cached_enumeration \
      --volume $PWD:/home/default/cached_enumeration \
      --workdir /home/default/cached_enumeration \
      <ruby-image>

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
