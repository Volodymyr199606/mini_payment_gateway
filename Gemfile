source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby ">= 3.1.0"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"
gem "dotenv-rails", "~> 3.1", groups: [:development, :test]
gem "puma", "~> 6.0"
gem "rack-cors", "~> 2.0"
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", ">= 1.4.4", require: false
gem "kaminari", "~> 1.2"
gem "importmap-rails", "~> 2.0"
gem "turbo-rails", "~> 1.5"
gem "stimulus-rails", "~> 1.3"
# Timezone data for Windows (no system zoneinfo)
gem "tzinfo-data", platforms: [:windows]

group :development, :test do
  gem "rspec-rails", "~> 6.0"
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  gem "listen", "~> 3.3"
end
