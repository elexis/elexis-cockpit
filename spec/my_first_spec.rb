# encoding: utf-8
# Gute Bespiele unter http://www.johncdavison.com/articles/3
# nokogiri wandelt HTML -> text um

app = File.expand_path(File.join(File.dirname(__FILE__), '..', 'elexis-cockpit.rb'))
puts app
require app  # <-- your sinatra app
require 'rspec'
require 'rack/test'
require 'nokogiri'

set :environment, :test
def app
  Sinatra::Application
end


describe 'Elexis-Cockpit get /' do
  include Rack::Test::Methods

  before :each do
      get '/'
  end
  
  it "has a home page" do
    last_response.should be_ok
    last_response.body.should match /Elexis-Cockpit/
    last_response.body.should match /Auslastung/
    last_response.body.should match /Überwachungen/
    last_response.body.should match /Wartungsarbeiten/
    last_response.body.should match /starte beliebige/
    last_response.body.should match /Niklaus Giger/
  end

end

describe '/startDbBackup should start a bckup' do
  include Rack::Test::Methods

  before :each do
      get '/startDbBackup'
  end
  
  it "/startDbBackup should not have a configuration error" do
    last_response.should be_ok
    last_response.body.should_not match /Fehler in der Konfiguration/
  end
  
end

