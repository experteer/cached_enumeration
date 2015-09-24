require 'spec_helper'


describe 'simple caching' do
  before :all do
    ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
    ActiveRecord::Migration.create_table :models do |t|
      t.integer :id
      t.string :name
      t.string :other
    end
  end


  before do
    @klass=Class.new(ActiveRecord::Base)
    @klass.table_name="models"
    @klass.delete_all
    @klass.create(:name => 'one', :other => 'eins')
    @klass.create(:name => 'two', :other => 'zwei')
    @klass.create(:name => 'three', :other => 'drei')
  end

  let(:one) { @klass.find_by_name("one") }
  let(:three) { @klass.find_by_name("three") }
  let(:two) { @klass.find_by_name("two") }

  context "cache_enumeration?" do
    it "should return the rigth value" do
      @klass.should_not be_cache_enumeration
      @klass.cache_enumeration.cache!
      @klass.should be_cache_enumeration
    end
    it "should not cache if not activated" do
      @klass.all
      @klass.should_not be_cache_enumeration
    end
  end


  context "cached_all and all" do
    before do
      @klass.cache_enumeration(:constantize => false)
    end

    it 'should provide cached_all' do
      one; two; three
      @klass.cache_enumeration.cache!
      @klass.connection.should_not_receive(:exec_query)

      @klass.cached_all.size.should == 3
      @klass.cached_all.collect { |item| item.id }.should == [one.id, two.id, three.id]
      @klass.cached_all.frozen?().should be_true

      @klass.all.should == @klass.cached_all
    end

    it "should fire db queries if all is modified" do
      @klass.cache_enumeration.cache!
      @klass.connection.should_receive(:exec_query).and_call_original
      @klass.where("name in ('one','two')").all.size.should == 2
    end

    it 'should fire db queries if all has parameters' do
      @klass.cache_enumeration.cache!
      @klass.connection.should_receive(:exec_query).and_call_original
      @klass.all(:conditions => "name = 'one'").size.should == 1
    end

    it 'should fire db queries if all with parameters is used through find(:all)' do
      @klass.cache_enumeration.cache!
      @klass.connection.should_receive(:exec_query).and_call_original
      @klass.find(:all, :conditions => "name = 'one'").size.should == 1
    end

    it 'should fire db queries if all with select parameter is used through find(:all)' do
      @klass.cache_enumeration.cache!
      @klass.connection.should_receive(:exec_query).and_call_original
      entry = @klass.find(:all, :select => "id, name").first
      lambda {
        entry.other
      }.should raise_error(ActiveModel::MissingAttributeError, 'missing attribute: other')
    end

  end

  context "finders" do
    before do
      @klass.cache_enumeration(:constantize => false)
    end

    it 'should find objects by_id' do
      one
      @klass.cache_enumeration.cache!
      @klass.connection.should_not_receive(:exec_query)

      @klass.by_id(one.id).id.should == one.id
    end

    it 'should find objects by_name' do
      one
      @klass.cache_enumeration.cache!
      @klass.connection.should_not_receive(:exec_query)

      @klass.by_name('one').id.should == one.id
    end

  end

  context "multiple keys" do
    it 'it should store by multiple keys (hashing)' do
      one
      @klass.cache_enumeration(:hashed => ['id', 'other', 'name']).cache!
      @klass.connection.should_not_receive(:exec_query)

      @klass.by_other('eins').id.should == one.id
      @klass.by_name('one').id.should == one.id
    end
  end
  context "sorting of all" do
    it 'should sort by option' do
      one; two; three
      @klass.cache_enumeration(:order => 'name').cache!
      @klass.connection.should_not_receive(:exec_query)

      @klass.cached_all.collect { |item| item.id }.should == [one.id, three.id, two.id]
      @klass.cached_all.should == @klass.all
    end

  end
  context "constantize" do
    it "should constantize name by default" do
      @klass.cache_enumeration.options[:constantize].should == 'name'
    end
    it "should without no preloading" do
      one
      @klass.cache_enumeration
      @klass::ONE.id.should == one.id
    end

    it 'should constantize other fields' do
      one
      @klass.cache_enumeration(:constantize => 'other')
      @klass.cache_enumeration.options[:constantize].should == 'other'
      @klass::EINS.id.should == one.id
    end

    it "should contantize by lambda" do
      one
      @klass.cache_enumeration(:constantize => lambda { |model| model.other })
      @klass::EINS.id.should == one.id
    end
  end


end
