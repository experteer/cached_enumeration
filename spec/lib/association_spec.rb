require 'spec_helper'

#require 'logger'

def logged
  logger = ActiveRecord::Base.logger
  ActiveRecord::Base.logger=Logger.new(STDOUT)
  ActiveRecord::Base.logger.level=Logger::DEBUG
  yield
  ActiveRecord::Base.logger=logger
end

describe 'association caching' do
  before :all do
    ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
#    ActiveRecord::Base.logger=Logger.new(STDOUT)
#    ActiveRecord::Base.logger.level=Logger::DEBUG

    ActiveRecord::Migration.create_table :genders do |t|
      t.integer :id
      t.string :name
    end

    class Gender < ActiveRecord::Base
      cache_enumeration
    end

    Gender.create!(:name => 'male')
    Gender.create!(:name => 'female')
    Gender.cache_enumeration.cache!

    ActiveRecord::Migration.create_table :profiles do |t|
      t.integer :id
      t.string :name
      t.integer :gender_id
    end
    class Profile < ActiveRecord::Base
      belongs_to :gender
    end
    Profile.delete_all
  end

end
