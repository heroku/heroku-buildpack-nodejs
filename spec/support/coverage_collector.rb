# Hatchet coverage collector. Active only when BUILDPACK_COVERAGE=1 is set in
# the host environment running rspec. After each example, fetches per-process
# trace files from the deployed app and writes them to coverage/traces/ on
# the host so etc/generate-coverage-report can consume them.

require "fileutils"
require "shellwords"

return unless ENV["BUILDPACK_COVERAGE"] == "1"

COVERAGE_TRACES_DIR = File.expand_path("../../coverage/traces", __dir__).freeze
FileUtils.mkdir_p(COVERAGE_TRACES_DIR)

RSpec.configure do |config|
  config.after(:each) do |example|
    app_name = nil
    [:@app, :app].each do |meth|
      candidate = instance_variable_get(meth) rescue nil
      candidate ||= (example.metadata[meth] rescue nil)
      if candidate.respond_to?(:name)
        app_name = candidate.name
        break
      end
    end
    next if app_name.nil?

    out = `heroku run --no-tty --app #{Shellwords.escape(app_name)} -- cat /app/.heroku/coverage/trace-*.log 2>/dev/null`
    next if out.empty?

    safe = app_name.gsub(/[^A-Za-z0-9_-]/, "_")
    File.write(File.join(COVERAGE_TRACES_DIR, "hatchet-#{safe}.log"), out)
  end
end

require "hatchet"

module Hatchet
  module CoverageConfigInjection
    def initialize(*args, **kwargs)
      kwargs[:config] = (kwargs[:config] || {}).merge(
        "BUILDPACK_COVERAGE" => "1"
      )
      super(*args, **kwargs)
    end
  end
end

if defined?(Hatchet::Runner)
  Hatchet::Runner.prepend(Hatchet::CoverageConfigInjection)
end
if defined?(Hatchet::App)
  Hatchet::App.prepend(Hatchet::CoverageConfigInjection)
end
