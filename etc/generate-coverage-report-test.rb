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

  def test_merges_hits_across_multiple_trace_files
    # Two trace files contribute hits to the same file. Hit counts must sum.
    write_trace("trace-1.log", [
      "+COV:lib/output.sh:5: a",
      "+COV:lib/output.sh:5: a",
      "+COV:lib/output.sh:10: b",
    ])
    write_trace("trace-2.log", [
      "+COV:lib/output.sh:5: a",
      "+COV:lib/output.sh:20: c",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs], "expected coverage for #{abs}"
    # 1-indexed line N → 0-indexed array slot N-1
    assert_equal 3, cov[abs]["lines"][4],  "line 5 should be hit 3 times (2 from trace-1 + 1 from trace-2)"
    assert_equal 1, cov[abs]["lines"][9],  "line 10 should be hit once (trace-1 only)"
    assert_equal 1, cov[abs]["lines"][19], "line 20 should be hit once (trace-2 only)"
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

  def test_unhit_executable_lines_default_to_zero
    # Real-world case: only line 5 of lib/output.sh ran. Every other
    # executable line in the file should appear as 0 (not nil), so the
    # coverage report shows what isn't tested rather than 100% of nothing.
    write_trace("trace-1.log", ["+COV:lib/output.sh:5: x"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs], "expected coverage for #{abs}"
    arr = cov[abs]["lines"]
    # Line 5 (idx 4) was hit
    assert_equal 1, arr[4]
    # Some line other than 5 should be 0 (executable, untested) — find at least one
    refute arr.compact.all? { |v| v > 0 }, "all executable lines hit, expected some 0s"
    has_executable_unhit = arr.each_with_index.any? { |v, _i| v == 0 }
    assert has_executable_unhit, "expected at least one executable line to be 0 (not nil), got #{arr.first(20).inspect}..."
  end

  def test_blank_and_comment_lines_marked_nil
    # Use a deliberately small file. Pick lib/npm.sh — only 5 source lines.
    write_trace("trace-1.log", ["+COV:lib/npm.sh:1: dummy"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "npm.sh")
    refute_nil cov[abs]
    arr = cov[abs]["lines"]
    source = File.readlines(abs).map(&:strip)
    arr.each_with_index do |val, i|
      stripped = source[i].to_s
      if stripped.empty? || stripped.start_with?("#")
        # Blank or comment — must be nil (unless it was actually traced, but
        # this test only traces line 1, which is `#!/usr/bin/env bash` so
        # it'd still be classified comment AND hit. Hit overrides.).
        if i + 1 == 1
          # Line 1 was traced — it's a shebang, so classified as comment but
          # promoted to hit-count.
          assert_equal 1, val, "line 1 (shebang, but traced) should be 1"
        else
          assert_nil val, "line #{i+1} (#{stripped.inspect}) is blank/comment, should be nil"
        end
      else
        # Executable line — should be 0 or a positive integer (never nil).
        refute_nil val, "line #{i+1} (#{stripped.inspect}) is executable, should be 0 or hit count"
      end
    end
  end
end
