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
      "+COV:lib/output.sh:10:: foo",
      "+COV:lib/output.sh:11:: bar",
      "+COV:lib/output.sh:10:: foo",
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
      "+COV:bin/compile:25:: source ...",
      "++COV:lib/output.sh:3:: ANSI_RED='[1;31m'",
      "+++COV:lib/failure.sh:3:: mktemp -t heroku-buildpack-nodejs-XXXX",
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
      "+COV:lib/output.sh:5:: a",
      "+COV:lib/output.sh:5:: a",
      "+COV:lib/output.sh:10:: b",
    ])
    write_trace("trace-2.log", [
      "+COV:lib/output.sh:5:: a",
      "+COV:lib/output.sh:20:: c",
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
      "+COV:test/unit:5:: should be dropped",
      "+COV:lib/vendor/stdlib_v7.sh:5:: also dropped (vendored, two-level path)",
      "+COV:lib/output.sh:5:: kept",
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
      "+COV:lib/output.sh:5:: kept",
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
      "+COV:/tmp/codon/foo/bin/compile:5:: should be dropped",
      "+COV:lib/output.sh:5:: kept",
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
    write_trace("trace-1.log", ["+COV:lib/output.sh:5:: x"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    assert File.exist?(File.join(@out, "index.html")), "expected index.html, got: #{Dir.entries(@out)}"
  end

  def test_unhit_executable_lines_default_to_zero
    # Real-world case: only line 5 of lib/output.sh ran. Every other
    # executable line in the file should appear as 0 (not nil), so the
    # coverage report shows what isn't tested rather than 100% of nothing.
    write_trace("trace-1.log", ["+COV:lib/output.sh:5:: x"])
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
    # lib/npm.sh — 5 source lines. After lexer classification:
    #   1 #!/usr/bin/env bash    → nil (comment), but trace promotes to 1
    #   2 (blank)                → nil
    #   3 npm_version_major() {  → nil (function declaration)
    #   4   npm --version | ...  → 0 (executable, not hit)
    #   5 }                      → nil (structural)
    write_trace("trace-1.log", ["+COV:lib/npm.sh:1:: dummy"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "npm.sh")
    refute_nil cov[abs]
    arr = cov[abs]["lines"]
    assert_equal 1, arr[0], "line 1 (shebang) traced — trace wins, expect 1"
    assert_nil arr[1],   "line 2 (blank) should be nil"
    assert_nil arr[2],   "line 3 (function decl) should be nil"
    assert_equal 0, arr[3], "line 4 (executable, not traced) should be 0"
    assert_nil arr[4],   "line 5 (closing brace) should be nil"
  end

  def test_function_declaration_lines_classified_non_executable
    # Function declaration lines (`name() {`) don't execute — they register a
    # name. The lexer marks them nil so they don't count for or against
    # coverage. Even when the function body is hit, the declaration stays nil
    # unless the trace itself records the declaration line (rare).
    write_trace("trace-1.log", [
      "+COV:lib/failure.sh:18:: echo foo",
      "+COV:lib/failure.sh:41:: is_invalid=...",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "failure.sh")
    refute_nil cov[abs], "expected coverage for #{abs}"
    arr = cov[abs]["lines"]
    # The body-line hits land where they're traced.
    assert arr[17].is_a?(Integer) && arr[17] > 0, "line 18 (body) should be hit"
    assert arr[40].is_a?(Integer) && arr[40] > 0, "line 41 (body) should be hit"
    # The function declaration lines stay nil — they're not executable code.
    assert_nil arr[16], "line 17 (failure_message() decl) should be nil"
    assert_nil arr[39], "line 40 (fail_invalid_package_json() decl) should be nil"
  end

  def test_trace_wins_over_lexer_nil_classification
    # If the trace records a hit on a line the lexer classified non-executable,
    # the trace wins. Use lib/output.sh line 11 (the closing `}` of `info()`).
    # The lexer marks `}` as nil; if the trace says it ran, the report reflects
    # that.
    write_trace("trace-1.log", [
      "+COV:lib/output.sh:11:: synthetic hit on a `}` line",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "output.sh")
    refute_nil cov[abs]
    arr = cov[abs]["lines"]
    assert_equal 1, arr[10], "trace-recorded hit on `}` line should win over nil classification"
  end

  def test_structural_lines_classified_non_executable
    # The whole point of the lexer pass: closing braces, fi, done, else on
    # their own line are nil, not counted as `0` (untested executable).
    # lib/output.sh line 11 = `}`, line 22 = `else`, line 24 = `fi`,
    # line 26 = `done`, line 27 = `}` of output(), line 32 = `}` of header().
    write_trace("trace-1.log", ["+COV:lib/output.sh:5:: dummy"])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    abs = File.join(REPO_ROOT, "lib", "output.sh")
    arr = cov[abs]["lines"]
    [11, 22, 24, 26, 27, 32].each do |ln|
      assert_nil arr[ln - 1], "line #{ln} should be classified non-executable (nil), got #{arr[ln - 1].inspect}"
    end
  end

  def test_drops_excluded_files
    # Files that match WATCHED but are explicitly excluded — the shim itself
    # plus scripts that aren't reachable from bin/compile.
    write_trace("trace-1.log", [
      "+COV:lib/coverage.sh:5:: should be dropped (the shim itself)",
      "+COV:bin/detect:5:: should be dropped",
      "+COV:bin/release:5:: should be dropped",
      "+COV:bin/report:5:: should be dropped",
      "+COV:bin/test:5:: should be dropped",
      "+COV:bin/test-compile:5:: should be dropped",
      "+COV:lib/output.sh:5:: kept",
    ])
    out, status = run_generator
    assert_equal 0, status, "generator failed: #{out}"
    resultset = JSON.parse(File.read(File.join(@out, ".resultset.json")))
    cov = resultset.dig("buildpack", "coverage")
    %w[lib/coverage.sh bin/detect bin/release bin/report bin/test bin/test-compile].each do |path|
      abs = File.join(REPO_ROOT, path)
      assert_nil cov[abs], "#{path} should be excluded but appeared in coverage"
    end
    refute_nil cov[File.join(REPO_ROOT, "lib", "output.sh")], "lib/output.sh should still appear"
  end
end
