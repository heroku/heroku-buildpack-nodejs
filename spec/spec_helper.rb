ENV['HATCHET_BUILDPACK_BASE'] = 'https://github.com/heroku/heroku-buildpack-nodejs.git'

require 'rspec/core'
require 'hatchet'
require 'fileutils'
require 'hatchet'
require 'rspec/retry'
require 'date'
require 'json'

ENV['RACK_ENV'] = 'test'

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.alias_example_to :fit, focused: true
  config.full_backtrace      = true
  config.verbose_retry       = true # show retry status in spec process
  config.default_retry_count = 2 # retry all tests that fail again

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def successful_body(app, options = {})
  retry_limit = options[:retry_limit] || 100
  path = options[:path] ? "/#{options[:path]}" : ''
  web_url = app.platform_api.app.info(app.name).fetch("web_url")
  Excon.get("#{web_url}#{path}",
              idempotent:     true,
              expects:        200,
              retry_interval: 0.5,
              retry_limit:    retry_limit
           ).body
rescue Excon::Error::HTTPStatus => e
  puts e.response.body
  raise e
end

def successful_json_body(app, options = {})
  body = successful_body(app, options)
  JSON.parse(body)
end

def run!(cmd)
  out = `#{cmd}`
  raise "Error running command #{cmd.inspect}: #{out}" unless $?.success?
  out
end
