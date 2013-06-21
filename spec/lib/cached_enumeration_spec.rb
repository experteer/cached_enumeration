require 'spec_helper'


describe 'ActiveRecord::Base::Caching::Enumeration' do
  before do
    class Model < ActiveRecord::Base


      def self.find(* args)
        if args[0] == :all
          one = self.new(:name=>'one', :other => 'eins')
          one.id = 1 # cannot set id in new :-(
          two = self.new(:name=>'two', :other => 'zwei')
          two.id = 2
          three = self.new(:name=>'three', :other => 'drei')
          three.id = 3
          args[1][:order] == 'name' ? [one, three, two] : [one, two, three]
        else
          super
        end
      end

      def self.columns
        @columns ||= []
      end

      def self.column(name, sql_type = nil, default = nil, null = true)
        columns << ActiveRecord::ConnectionAdapters::Column.new(name.to_s, default,
                                                                sql_type.to_s, null)
      end

      column :id, 'integer'
      column :name, 'string'
      column :other, 'string'

    end
  end

  after do
    Object.send(:remove_const, :Model)
  end

  context "basic methods" do
    before do
      Model.cache_enumeration
    end
    it 'should provide cached_all' do
      Model.cached_all.collect { |item| item.id }.should == [1, 2, 3]
      Model.cached_all.frozen?().should be_true
    end

    it 'should find objects providing id' do
      Model.find(1).id.should == 1
      Model.find(1).frozen?().should be_true
      Model.find([1])[0].id.should == 1
      Model.find([]).size.should == 0
      Model.find([1, 3]).collect { |item| item.id }.should == [1, 3]
      lambda { Model.find(0) }.should raise_error(ActiveRecord::RecordNotFound)
      lambda { Model.find(nil) }.should raise_error(ActiveRecord::RecordNotFound)
    end

    it 'should find objects by id' do
      Model.find_by_id(1).id.should == 1
      Model.by_id(1).id.should == 1
      Model.find_by_id('1').id.should == 1
      Model.find_by_id(0).should be_nil
    end

    it 'should find objects by name' do
      Model.find_by_name('one').id.should == 1
      Model.by_name('one').id.should == 1
      Model.find_by_name('no such name').should be_nil
    end

    it 'should have constants for names' do
        Model::ONE.id.should == 1
      end
    
  end

  context "options" do
  it 'it should store by multiple keys (hashing)' do
    lambda { Model.find_by_other('eins') }.should raise_error
    Model.cache_enumeration(:hashed => ['id', 'other'])
    Model.find_by_other('eins').id.should == 1
    Model.by_other('eins').id.should == 1
  end

  it 'should sort by option' do
    Model.cache_enumeration(:order => 'name')
    Model.cached_all.collect { |item| item.id }.should == [1, 3, 2]
  end

  it 'should constantize other fields' do
    Model.cache_enumeration(:constantize => 'other')
    Model::EINS.id.should == 1
  end
 end

end
