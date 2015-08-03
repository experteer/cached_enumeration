require 'spec_helper'


describe 'simple caching' do
  before :all do
    ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
    ActiveRecord::Migration.create_table :models do |t|
#      t.integer :id
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

  let(:one) { @klass.find_by(:name => "one") }
  let(:three) { @klass.find_by(:name => "three") }
  let(:two) { @klass.find_by(:name => "two") }

  context "cache_enumeration?" do
    it "should return the rigth value" do
      expect(@klass).not_to be_cache_enumeration
      @klass.cache_enumeration.cache!
      expect(@klass).to be_cache_enumeration
    end
    it "should not cache if not activated" do
      @klass.all
      expect(@klass).not_to be_cache_enumeration
    end
  end


  context "all" do
    before do
      @klass.cache_enumeration(:constantize => false)
    end

    it "should fire db queries if all is modified" do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      expect(@klass.where("name in ('one','two')").all.size).to eq(2)
    end

    it 'should fire db queries if all has parameters' do
      @klass.cache_enumeration.cache!
      #@klass.connection.should_receive(:exec_query)..and_call_original
      expect(@klass.where("name = 'one'").all.size).to eq(1)
    end

    it 'should fire db queries if all with parameters is used through find(:all)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      expect(@klass.where("name = 'one'").all.size).to eq(1)
    end
      
    it 'should fire db queries if all with select parameter is used through find(:all)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      entry = @klass.select("id, name").all.first
      expect {
        entry.other
      }.to raise_error(ActiveModel::MissingAttributeError, 'missing attribute: other')
    end
      
  end

  context 'first' do
    it 'should find the first entry' do
      @klass.cache_enumeration.cache!
      expect(@klass.first).to eq(one)
    end
    it 'should allwo string order (and use cache)' do
      @klass.cache_enumeration(:order => "other").cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.order('other').first).to eq(three)
    end
    it 'should allow hash condition (and use cache)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.where(:name => 'three').first).to eq(three)
    end
    it 'should allow string conditions (and ask db)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      expect(@klass.where("other = 'drei'").first).to eq(three)
    end

    it 'should allow hash conditions in first (and use cache)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)
      expect(@klass.where(:name => 'three' ).first).to eq(three)
    end

    it 'should allow conditions for first (and use db)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      expect(@klass.where("other = 'drei'").first).to eq(three)
    end
    it 'should allow conditions for first (and use db)' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).to receive(:exec_query).and_call_original
      expect(@klass.where("name = 'three'").first).not_to be_nil
    end
  end

  context "finders" do
    before do
      @klass.cache_enumeration(:constantize => false)
    end

    it 'should find objects providing id' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.find(one.id).id).to eq(one.id)
      expect(@klass.find(one.id).frozen?()).to eq(true)
      expect(@klass.find([one.id])[0].id).to eq(one.id)
      expect(@klass.find([]).size).to eq(0)

      expect { @klass.find(0) }.to raise_error(ActiveRecord::RecordNotFound)
      expect { @klass.find(nil) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "should find an array of object ids (and hit cache)" do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.find([one.id, three.id]).collect { |item| item.id }).to eq([one.id, three.id])
    end

    it 'should find_by' do
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.find_by(:id => one.id).id).to eq(one.id)
      expect(@klass.find_by(:id => one.id.to_s).id).to eq(one.id)
      expect(@klass.find_by(:id => 0)).to be_nil
    end

    it 'should find objects by_name' do
      one
      @klass.cache_enumeration.cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.find_by(:name => 'one').id).to eq(one.id)
      expect(@klass.find_by(:name => 'no such name')).to be_nil
    end

  end

  context "multiple keys" do
    it 'it should store by multiple keys (hashing)' do
      @klass.cache_enumeration(:hashed => ['id', 'other', 'name']).cache!
      expect(@klass.connection).not_to receive(:exec_query)
      expect(@klass.find_by(:other => 'eins').id).to eq(one.id)
      expect(@klass.find_by(:name => 'one').id).to eq(one.id)
    end
  end
  context "sorting of all" do
    it 'should sort by option' do
      @klass.cache_enumeration(:order => 'name').cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass.order("name").all.collect { |item| item.id }).to eq([one.id, three.id, two.id])
    end

  end
  context "constantize" do
    it "should constantize name by default" do
      expect(@klass.cache_enumeration.options[:constantize]).to eq('name')
    end
    it "should without no preloading" do

      @klass.cache_enumeration
      expect(@klass::ONE.id).to eq(one.id)
    end

    it 'should constantize other fields' do
      @klass.cache_enumeration(:constantize => 'other').cache!
      expect(@klass.cache_enumeration.options[:constantize]).to eq('other')
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass::EINS.id).to eq(one.id)
    end

    it "should contantize by lambda" do
      @klass.cache_enumeration(:constantize => lambda { |model| model.other }).cache!
      expect(@klass.connection).not_to receive(:exec_query)

      expect(@klass::EINS.id).to eq(one.id)
    end
  end


end
