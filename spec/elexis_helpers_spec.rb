# encoding: utf-8
# Copyright (c) 2013 by Niklaus Giger niklaus.giger@member.fsf.org

require 'rspec'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib/','elexis_helpers.rb'))
include Sinatra::ElexisHelpers
require 'yaml'
require 'socket'

describe "ElexisHelpers" do

  it "should return mysql" do
    expect(Sinatra::ElexisHelpers.get_elexis_default('dummy')).to eq(nil)
    expect(Sinatra::ElexisHelpers.get_elexis_default('elexis::db_type')).to eq('mysql')
  end

  it "should be okay for the reboot script" do
    cmd = Sinatra::ElexisHelpers.get_config("server::reboot_script", '/usr/local/bin/reboot.sh')
    puts "reboot cmd ist #{cmd}"
    expect(cmd).to eq('/usr/local/bin/reboot.sh')
  end

  it "should be okay for db main" do
    x = Sinatra::ElexisHelpers.get_db_backup_info('main')[:dump_script]
    expect(x).not_to match /unkown|unbekannt/
    x =  Sinatra::ElexisHelpers.get_db_backup_info('db_main')[:dump_script]
    expect(x).not_to match /unkown|unbekannt/
    x = Sinatra::ElexisHelpers.get_db_backup_info('db_test')[:dump_script]
    expect(x).not_to match /unkown|unbekannt/
  end
end
