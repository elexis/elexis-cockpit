#!/usr/bin/env 
# config.ru (run with rackup)
require "#{File.dirname(__FILE__)}/elexis-cockpit.rb"
run ElexisCockpit.new