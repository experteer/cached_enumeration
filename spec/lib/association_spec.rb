require 'spec_helper'

#require 'logger'

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


  let(:him) { Profile.create(:name => 'Him', :gender => Gender::MALE) }
  let(:her) { Profile.create(:name => 'Her', :gender => Gender::FEMALE) }


  context "should use cached when going over association" do

    it 'should find the cached ones (no :include)' do
      him
      him.reload #to empty the assoc cache

      Gender.connection.should_not_receive(:exec_query)
      him.gender.name.should == 'male'
    end

    it "should take the :include from the cache" do
      him;her
      all=Profile.includes(:gender).all
      Gender.connection.should_not_receive(:exec_query)
      him.gender.name.should == 'male'
      her.gender.name.should == 'female'
    end


  end
end