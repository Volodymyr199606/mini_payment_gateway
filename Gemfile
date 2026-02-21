# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '>= 3.1.0'

gem 'bcrypt', '~> 3.1.7'
gem 'bootsnap', '>= 1.4.4', require: false
gem 'dotenv-rails', '~> 3.1', groups: %i[development test]
gem 'importmap-rails', '~> 2.0'
gem 'kaminari', '~> 1.2'
gem 'pg', '~> 1.5'
gem 'puma', '~> 6.0'
gem 'rack-cors', '~> 2.0'
gem 'rails', '~> 7.2'
gem 'sprockets-rails', '>= 3.4'
gem 'stimulus-rails', '~> 1.3'
gem 'turbo-rails', '~> 1.5'
# Timezone data for Windows (no system zoneinfo)
gem 'tzinfo-data', platforms: [:windows]

group :development, :test do
  gem 'brakeman', require: false
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
  gem 'rspec-rails', '~> 6.0'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
end

group :development do
  gem 'listen', '~> 3.3'
  gem 'wdm', '>= 0.1.0', platforms: [:windows]
  # Required by kamal/net-ssh on Ruby 4+ (fiddle removed from default gems)
  gem 'fiddle'
  gem 'kamal', '~> 2.10'
end
