#!/usr/bin/env ruby
# frozen_string_literal: true

# Run with: bundle exec ruby etc/coverage_lexer_test.rb

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "coverage_lexer"

class CoverageLexerTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("cov-lexer-test")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def write(name, content)
    path = File.join(@tmp, name)
    File.write(path, content)
    path
  end

  # ---------- relevant? ----------

  def test_relevant_strips_blank_lines
    refute CoverageLexer.relevant?("")
    refute CoverageLexer.relevant?("   ")
    refute CoverageLexer.relevant?("\n")
  end

  def test_relevant_strips_pure_comments
    refute CoverageLexer.relevant?("# a comment")
    refute CoverageLexer.relevant?("  # indented comment")
  end

  def test_relevant_strips_trailing_comments_then_evaluates
    # `echo foo  # comment` → after stripping, "echo foo" is executable
    assert CoverageLexer.relevant?("echo foo  # trailing comment")
    # but `   # comment` after stripping is empty → non-executable
    refute CoverageLexer.relevant?("  # comment")
  end

  def test_relevant_strips_structural_only_lines
    %w[esac if then else elif fi while do done { } ;; ( )].each do |kw|
      refute CoverageLexer.relevant?(kw), "expected #{kw.inspect} to be non-executable"
      refute CoverageLexer.relevant?("  #{kw}  "), "expected #{kw.inspect} (with whitespace) to be non-executable"
    end
  end

  def test_relevant_strips_function_declarations
    refute CoverageLexer.relevant?("foo() {")
    refute CoverageLexer.relevant?("function foo() {")
    refute CoverageLexer.relevant?("function foo {")
    refute CoverageLexer.relevant?("output::error() {")
    refute CoverageLexer.relevant?("my_func() {")
  end

  def test_relevant_strips_case_selectors
    refute CoverageLexer.relevant?("--help)")
    refute CoverageLexer.relevant?("foo|bar)")
  end

  def test_relevant_strips_lines_ending_with_subshell_open
    refute CoverageLexer.relevant?("(")
    refute CoverageLexer.relevant?("foo (")
  end

  def test_relevant_keeps_real_statements
    assert CoverageLexer.relevant?("echo foo")
    assert CoverageLexer.relevant?("local x=1")
    assert CoverageLexer.relevant?("if [[ -n $x ]]; then")  # not just `if` — real condition
    assert CoverageLexer.relevant?("return 1")
    assert CoverageLexer.relevant?("foo=bar")
  end

  # ---------- classify ----------

  def test_classify_returns_array_sized_to_file
    path = write("a.sh", "echo a\necho b\necho c\n")
    arr = CoverageLexer.classify(path)
    assert_equal 3, arr.length
  end

  def test_classify_marks_blank_and_comment_as_nil
    path = write("a.sh", <<~SH)
      #!/usr/bin/env bash

      # a comment
      echo hello
    SH
    arr = CoverageLexer.classify(path)
    assert_nil arr[0],   "shebang should be nil"
    assert_nil arr[1],   "blank should be nil"
    assert_nil arr[2],   "comment should be nil"
    assert_equal 0, arr[3], "real statement should be 0"
  end

  def test_classify_marks_structural_tokens_as_nil
    path = write("a.sh", <<~SH)
      foo() {
        if [[ -n $x ]]; then
          echo a
        else
          echo b
        fi
      }
    SH
    arr = CoverageLexer.classify(path)
    assert_nil arr[0],   "foo() { → nil"
    assert_equal 0, arr[1], "if [[ ... ]]; then → 0"
    assert_equal 0, arr[2], "echo a → 0"
    assert_nil arr[3],   "else → nil"
    assert_equal 0, arr[4], "echo b → 0"
    assert_nil arr[5],   "fi → nil"
    assert_nil arr[6],   "} → nil"
  end

  def test_classify_marks_done_and_for_loop_keywords
    path = write("a.sh", <<~SH)
      for x in 1 2 3; do
        echo $x
      done
    SH
    arr = CoverageLexer.classify(path)
    assert_equal 0, arr[0], "for loop with do on same line is real"
    assert_equal 0, arr[1], "echo $x is real"
    assert_nil arr[2], "done → nil"
  end

  def test_classify_marks_case_selectors
    path = write("a.sh", <<~SH)
      case "$1" in
        --help)
          echo help
          ;;
        *)
          echo default
          ;;
      esac
    SH
    arr = CoverageLexer.classify(path)
    assert_equal 0, arr[0], "case ... in → real"
    assert_nil arr[1], "--help) → nil"
    assert_equal 0, arr[2], "echo help → real"
    assert_nil arr[3], ";; → nil"
    assert_nil arr[4], "*) → nil"
    assert_equal 0, arr[5], "echo default → real"
    assert_nil arr[6], ";; → nil"
    assert_nil arr[7], "esac → nil"
  end

  # ---------- multi-line constructs ----------

  def test_classify_marks_heredoc_body_as_nil
    path = write("a.sh", <<~'SH')
      output::error <<-EOF
        Error: bad input.
        Try again.
      EOF
      echo done
    SH
    arr = CoverageLexer.classify(path)
    assert_equal 0, arr[0], "heredoc opener is real (the command runs)"
    assert_nil arr[1], "heredoc body line 1 → nil"
    assert_nil arr[2], "heredoc body line 2 → nil"
    assert_equal 0, arr[4], "post-heredoc echo → real"
  end

  def test_classify_marks_multiline_array_body_as_nil
    path = write("a.sh", <<~SH)
      ARR=(
        foo
        bar
      )
      echo "${ARR[@]}"
    SH
    arr = CoverageLexer.classify(path)
    # Body lines (foo, bar, closing-paren) should be nil
    assert_nil arr[1], "array body 'foo' → nil"
    assert_nil arr[2], "array body 'bar' → nil"
    assert_equal 0, arr[4], "post-array echo → real"
  end

  def test_classify_handles_realistic_output_sh_snippet
    # Mirrors the actual lib/output.sh structure: function with if/else/fi.
    path = write("output.sh", <<~SH)
      output() {
        local logfile="$1"

        while IFS= read -r LINE;
        do
          if [[ "$LINE" =~ ^-----.* ]]; then
            echo "$LINE" || true
          else
            echo "       $LINE" || true
          fi
          echo "$LINE" >> "$logfile" || true
        done
      }
    SH
    arr = CoverageLexer.classify(path)
    expected_nil = [0, 4, 7, 9, 11, 12]  # function decl, do, else, fi, done, }
    expected_nil.each do |i|
      assert_nil arr[i], "line #{i + 1} should be nil (got #{arr[i].inspect})"
    end
    expected_zero = [1, 3, 5, 6, 8, 10]  # local, while, if, echo, echo, echo>>
    expected_zero.each do |i|
      assert_equal 0, arr[i], "line #{i + 1} should be 0 (got #{arr[i].inspect})"
    end
  end

  def test_classify_treats_function_keyword_form_as_nil
    path = write("a.sh", <<~SH)
      function foo() {
        echo foo
      }

      function bar {
        echo bar
      }
    SH
    arr = CoverageLexer.classify(path)
    assert_nil arr[0],   "function foo() { → nil"
    assert_equal 0, arr[1], "echo foo → real"
    assert_nil arr[2],   "} → nil"
    assert_nil arr[4],   "function bar { → nil"
    assert_equal 0, arr[5], "echo bar → real"
    assert_nil arr[6],   "} → nil"
  end
end
