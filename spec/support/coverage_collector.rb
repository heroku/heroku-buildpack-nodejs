# Hatchet coverage collector. Active only when BUILDPACK_COVERAGE=1 is set in
# the host environment running rspec. Wraps Hatchet::App#deploy so that, after
# the test's deploy block returns but before Hatchet's teardown! destroys the
# app, we fetch /app/.heroku/coverage/trace-*.log and write it to the host's
# coverage/traces/ dir for etc/generate-coverage-report to consume.

require "fileutils"
require "shellwords"

return unless ENV["BUILDPACK_COVERAGE"] == "1"

require "hatchet"

COVERAGE_TRACES_DIR = File.expand_path("../../coverage/traces", __dir__).freeze
FileUtils.mkdir_p(COVERAGE_TRACES_DIR)

module Hatchet
  module CoverageConfigInjection
    def initialize(*args, **kwargs)
      kwargs[:config] = (kwargs[:config] || {}).merge(
        "BUILDPACK_COVERAGE" => "1"
      )
      super(*args, **kwargs)
    end
  end

  module CoverageDeployWrapper
    def deploy(&block)
      return super unless block_given?
      super do |app, *rest|
        begin
          block.call(app, *rest)
        ensure
          ::CoverageCollector.collect(app)
        end
      end
    end
  end
end

module CoverageCollector
  def self.collect(app)
    name = app.respond_to?(:name) ? app.name : nil
    return if name.nil? || name.empty?

    out = `heroku run --no-tty --app #{Shellwords.escape(name)} -- cat /app/.heroku/coverage/trace-*.log 2>/dev/null`
    return if out.empty?

    safe = name.gsub(/[^A-Za-z0-9_-]/, "_")
    File.write(File.join(COVERAGE_TRACES_DIR, "hatchet-#{safe}.log"), out)
    puts "[coverage] collected #{out.bytesize} bytes for #{name}"
  rescue => e
    warn "[coverage] failed for #{name}: #{e.class}: #{e.message}"
  end
end

Hatchet::App.prepend(Hatchet::CoverageConfigInjection)
Hatchet::App.prepend(Hatchet::CoverageDeployWrapper)
