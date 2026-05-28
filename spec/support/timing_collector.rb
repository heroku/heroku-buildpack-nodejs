# Hatchet timing collector. Active only when BUILDPACK_TIMING_OUT is set in the
# host environment running rspec. Wraps Hatchet::App#deploy so that, after the
# test's deploy block returns, we scan app.output for the BUILDPACK_TIMING_S
# marker that bin/compile emits at the end of a successful build, and append
# one CSV row to $BUILDPACK_TIMING_OUT.
#
# CSV columns: timestamp_iso, app_name, fixture, coverage, duration_seconds
#
# This file is intentionally narrow-scoped: it does not modify hatchet's deploy
# semantics or affect tests in any other way. Set BUILDPACK_TIMING_OUT to a
# file path (e.g. coverage/timings/run-1.csv) to enable.

require "fileutils"

return unless (TIMING_OUT_PATH = ENV["BUILDPACK_TIMING_OUT"])

require "hatchet"

FileUtils.mkdir_p(File.dirname(TIMING_OUT_PATH))

module Hatchet
  module TimingDeployWrapper
    def deploy(&block)
      return super unless block_given?
      super do |app, *rest|
        begin
          block.call(app, *rest)
        ensure
          ::TimingCollector.collect(app)
        end
      end
    end
  end
end

module TimingCollector
  # bin/compile emits: BUILDPACK_TIMING_S=<seconds> coverage=<0|1>
  MARKER = /BUILDPACK_TIMING_S=([\d.]+)\s+coverage=(\d)/.freeze

  def self.collect(app)
    name = app.respond_to?(:name) ? app.name : nil
    return if name.nil? || name.empty?

    output = app.respond_to?(:output) ? app.output.to_s : ""
    matches = output.scan(MARKER)
    return if matches.empty?

    fixture = app.respond_to?(:directory) ? File.basename(app.directory.to_s) : ""
    timestamp = Time.now.utc.iso8601

    File.open(TIMING_OUT_PATH, "a") do |f|
      matches.each do |duration, coverage|
        f.puts [timestamp, name, fixture, coverage, duration].join(",")
      end
    end
  rescue => e
    warn "[timing] failed for #{name}: #{e.class}: #{e.message}"
  end
end

Hatchet::App.prepend(Hatchet::TimingDeployWrapper)
