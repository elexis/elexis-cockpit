source "http://rubygems.org"
# Is known to work with ruby 1.9.3 and 2.0.0
gem "sinatra", ">=1.3.5"
gem "shotgun"
gem "sqlite3" 
gem "datamapper" 
gem "dm-sqlite-adapter"
gem "builder"
gem "RedCloth"
gem "sys-filesystem"

# I did not find a way to use these packs with Ruby 1.9.2
# Therefore if you install under Ruby 1.9.2 do so using
# bundle install --without actionpack
group :actionpack do
  gem "actionpack" # , ">=4.0.0.beta1" 
  gem 'activesupport'
end
gem 'nokogiri'
gem 'i18n_rails_helpers'
gem 'haml'
gem 'rake'
group :test do
  gem 'watir'
  gem 'watir-webdriver'
  gem 'rspec'
  # gem 'capybara' # maybe later
end
group 'debugger' do
  gem 'pry'
end