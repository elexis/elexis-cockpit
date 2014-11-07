# encoding: utf-8
# Copyright (c) 2013 by Niklaus Giger niklaus.giger@member.fsf.org

require 'rspec'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib/','elexis_helpers.rb'))
include Sinatra::ElexisHelpers
require 'yaml'
require 'socket'

describe "ElexisHelpers" do

  it "should return mysql" do
    Sinatra::ElexisHelpers.get_elexis_default('dummy').should == nil
    Sinatra::ElexisHelpers.get_elexis_default('elexis::params::db_type').should == 'mysql'
  end

end
