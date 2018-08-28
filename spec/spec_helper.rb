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
  config.filter_run focused: true unless ENV['IS_RUNNING_ON_TRAVIS']
  config.run_all_when_everything_filtered = true
  config.alias_example_to :fit, focused: true
  config.full_backtrace      = true
  config.verbose_retry       = true # show retry status in spec process
  config.default_retry_count = 2 if ENV['IS_RUNNING_ON_TRAVIS'] # retry all tests that fail again

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def successful_body(app, options = {})
  retry_limit = options[:retry_limit] || 100 
  path = options[:path] ? "/#{options[:path]}" : ''
  Excon.get("http://#{app.name}.herokuapp.com#{path}", :idempotent => true, :expects => 200, :retry_limit => retry_limit).body
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

def resolve_node_version(requirements, options = {})
  # use nodebin to get latest node versions
  requirements.map do |requirement|
    retry_limit = options[:retry_limit] || 50
    body = Excon.get("https://nodebin.herokai.com/v1/node/linux-x64/latest?range=#{requirement}", :idempotent => true, :expects => 200, :retry_limit => retry_limit).body
    JSON.parse(body)['number']
  end
end

def resolve_all_supported_node_versions(options = {})
  retry_limit = options[:retry_limit] || 50 
  body = Excon.get("https://nodebin.herokai.com/v1/node/linux-x64/", :idempotent => true, :expects => 200, :retry_limit => retry_limit).body
  list = JSON.parse(body).map { |n| n['number'] }

  list.select do |n|
    SemVersion.new(n).satisfies?('>= 6.0.0')
  end
end

def version_supports_metrics(version)
  SemVersion.new(version).satisfies?('>= 8.0.0')
end

def get_test_versions
  if ENV['TEST_NODE_VERSION']
    versions = [ENV['TEST_NODE_VERSION']]
  elsif ENV['TEST_ALL_NODE_VERSIONS'] == 'true'
    versions = resolve_all_supported_node_versions()
  else
    versions = resolve_node_version(['6.x', '8.x', '9.x', '10.x'])
  end
  puts("Running tests for Node versions: #{versions.join(', ')}")
  versions
end
