#!/usr/bin/env ruby
# Test for etc/generate-coverage-report. Run with: bundle exec ruby etc/generate-coverage-report-test.rb

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "shellwords"
require "json"

REPORT_GENERATOR = File.expand_path("generate-coverage-report", __dir__)
REPO_ROOT = File.expand_path("..", __dir__)

class CoverageReportTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("cov-report-test")
    @traces = File.join(@tmp, "coverage", "traces")
    @out = File.join(@tmp, "coverage")
    FileUtils.mkdir_p(@traces)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def write_trace(name, lines)
    File.write(File.join(@traces, name), lines.join("\n") + "\n")
  end

  def run_generator
    out = `cd #{Shellwords.escape(@tmp)} && BUILDPACK_REPO_ROOT=#{Shellwords.escape(REPO_ROOT)} bundle exec ruby #{Shellwords.escape(REPORT_GENERATOR)} 2>&1`
    [out, $?.exitstatus]
  end

  def test_parses_single_plus_cov_lines
    write_trace("trace-1.log", [
      "+COV:lib/output.sh:10: foo",
      "+COV:lib/output.sh:11: bar",
      "+COV:lib/output.sh:10: foo",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs], "expected coverage for #{abs} but got keys: #{cov.keys}"
    # Lines are 1-indexed; index 9 = line 10, index 10 = line 11
    assert_equal 2, cov[abs]["lines"][9], "line 10 should be hit twice"
    assert_equal 1, cov[abs]["lines"][10], "line 11 should be hit once"
  end

  def test_parses_multi_plus_cov_lines_from_sourced_files
    # Real bash xtrace prefixes sourced/subshell statements with multiple '+'.
    write_trace("trace-1.log", [
      "+COV:bin/compile:25: source ...",
      "++COV:lib/output.sh:3: ANSI_RED='[1;31m'",
      "+++COV:lib/failure.sh:3: mktemp -t heroku-buildpack-nodejs-XXXX",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs_compile = File.join(REPO_ROOT, "bin", "compile")
    abs_output = File.join(REPO_ROOT, "lib", "output.sh")
    abs_failure = File.join(REPO_ROOT, "lib", "failure.sh")
    refute_nil cov[abs_compile], "single-plus line should be parsed"
    refute_nil cov[abs_output], "double-plus line should be parsed"
    refute_nil cov[abs_failure], "triple-plus line should be parsed"
  end

  def test_drops_lines_outside_watched_globs
    write_trace("trace-1.log", [
      "+COV:test/unit:5: should be dropped",
      "+COV:lib/vendor/stdlib_v7.sh:5: also dropped (vendored, two-level path)",
      "+COV:lib/output.sh:5: kept",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs_test = File.join(REPO_ROOT, "test", "unit")
    abs_vendor = File.join(REPO_ROOT, "lib", "vendor", "stdlib_v7.sh")
    abs_output = File.join(REPO_ROOT, "lib", "output.sh")
    assert_nil cov[abs_test]
    assert_nil cov[abs_vendor]
    refute_nil cov[abs_output]
  end

  def test_drops_non_cov_lines
    write_trace("trace-1.log", [
      "+ regular xtrace line",
      "++ subshell line",
      "garbage",
      "+COV:lib/output.sh:5: kept",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs_output = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs_output]
    assert_equal 1, cov[abs_output]["lines"][4]
  end

  def test_drops_lines_with_absolute_paths
    # Real traces include lines like `source /tmp/codon/.../lib/foo.sh` which
    # are content of statements being traced, not coverage targets. They never
    # match the watched globs because they start with `/`.
    write_trace("trace-1.log", [
      "+COV:/tmp/codon/foo/bin/compile:5: should be dropped",
      "+COV:lib/output.sh:5: kept",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    refute cov.keys.any? { |k| k.start_with?("/tmp/codon/") }, "absolute-path entries should not appear: #{cov.keys}"
    abs_output = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs_output]
  end

  def test_writes_html_index
    write_trace("trace-1.log", ["+COV:lib/output.sh:5: x"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    assert File.exist?(File.join(@out, "index.html")), "expected index.html, got: #{Dir.entries(@out)}"
  end
end
