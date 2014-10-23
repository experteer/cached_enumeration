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
#      t.integer :id
      t.string :name
    end

    class Gender < ActiveRecord::Base
      cache_enumeration
    end

    Gender.create!(:name => 'male')
    Gender.create!(:name => 'female')
    Gender.cache_enumeration.cache!

    ActiveRecord::Migration.create_table :profiles do |t|
 #     t.integer :id
      t.string :name
      t.integer :gender_id
    end
    class Profile < ActiveRecord::Base
      belongs_to :gender
    end
    Profile.delete_all
  end


  let(:him) { Profile.create(:name => 'Him', :gender => Gender::MALE) }
  let(:her) { Profile.create(:name => 'Her', :gender => Gender::FEMALE) }


  context "should use cached when going over association" do

    it 'should find the cached ones (no :include)' do
      him
      him.reload #to empty the assoc cache

      Gender.connection.should_not_receive(:exec_query)
      him.gender.name.should == 'male'
    end

=begin

does not work: Profile.includes(:gender).all creates two sql statements
to load profiles AND genders associated to them. The 2nd one (for genders)
does not run through standard finders but is done in the depth of AR.
So caching does not work here.

Possible improvements:
* intercept `all' for ALL AR models and take out inclusions where the
  model is cached (restricted to simple cases of belongs_to)
* find an entry point deeper in AR where associations are loaded and
  modify that to consider model caching

Until then, one should just leave out cached models in inclusions,
though that makes switching caching on or off for a model quite difficult.

    it "should take the :include from the cache" do
      #logged do
      him;her
        ActiveRecord::Base.connection.should_receive(:exec_query).once.and_call_original
        all=Profile.includes(:gender).all
        ActiveRecord::Base.connection.should_not_receive(:exec_query)
        him.gender.name.should == 'male'
        her.gender.name.should == 'female'
      #end
    end
=end


  end
end
