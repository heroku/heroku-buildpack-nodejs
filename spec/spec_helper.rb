ENV['HATCHET_BUILDPACK_BASE'] = 'https://github.com/heroku/heroku-buildpack-nodejs.git'

require 'rspec/core'
require 'hatchet'
require 'fileutils'
require 'hatchet'
require 'rspec/retry'
require 'date'
require 'json'
require 'sem_version'

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
  Excon.get("http://#{app.name}.herokuapp.com#{path}",
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

def set_node_version(version)
  package_json = File.read('package.json')
  package = JSON.parse(package_json)
  package["engines"]["node"] = version
  File.open('package.json', 'w') do |f|
    f.puts JSON.dump(package)
  end
end

def run!(cmd)
  out = `#{cmd}`
  raise "Error running command #{cmd.inspect}: #{out}" unless $?.success?
  out
end

def resolve_binary_path
  RUBY_PLATFORM.match(/darwin/) ? './lib/vendor/resolve-version-darwin' : './lib/vendor/resolve-version-linux'
end

def resolve_node_version(requirements, options = {})
  requirements.map do |requirement|
    result = run!("#{resolve_binary_path} node #{requirement}")
    result.split(' ').first
  end
end

def resolve_all_supported_node_versions(options = {})
  result = run!("#{resolve_binary_path} list node")
  list = result.lines().map { |line| line.split(' ').first }
  list.select do |n|
    SemVersion.new(n).satisfies?('>= 10.0.0')
  end
end

def version_supports_metrics(version)
  SemVersion.new(version).satisfies?('>= 10.0.0') && SemVersion.new(version).satisfies?('< 20.0.0')
end

def get_test_versions
  if ENV['TEST_NODE_VERSION']
    versions = [ENV['TEST_NODE_VERSION']]
  elsif ENV['TEST_ALL_NODE_VERSIONS'] == 'true'
    versions = resolve_all_supported_node_versions()
  else
    versions = resolve_node_version(['14.x', '16.x', '18.x', '19.x'])
  end
  puts("Running tests for Node versions: #{versions.join(', ')}")
  versions
end
