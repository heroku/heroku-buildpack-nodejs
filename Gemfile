source "https://rubygems.org"

ruby ">= 3.3", "< 4.1"

group :test, :development do
  gem "heroku_hatchet"
  # `threaded` (via heroku_hatchet) requires logger without declaring it, and
  # excon >= 1.9 no longer pulls it in. logger is a bundled gem on Ruby 4.0.
  gem "logger"
  gem "rspec-retry"
  gem "rspec-expectations"
  gem "parallel_split_test"
  gem "rake"
end
