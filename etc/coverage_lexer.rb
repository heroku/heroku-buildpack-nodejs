# frozen_string_literal: true

# Classify each line of a bash source file as executable (0) or non-executable
# (nil). Used by etc/generate-coverage-report to build the SimpleCov coverage
# array before overlaying trace hits.
#
# Bash's `set -x` cannot trace structural tokens (closing braces, `done`, `fi`,
# `else`, etc.) or multi-line construct bodies (heredocs, multi-line arrays).
# Treating those as executable would inflate the denominator and depress the
# coverage percentage. This module identifies them so they don't count.
#
# Rules ported from bashcov's Bashcov::Lexer (MIT, https://github.com/infertux/bashcov).

module CoverageLexer
  # Lines starting with one of these tokens are non-executable.
  IGNORE_START_WITH = %w[# function].freeze

  # Lines ending with one of these tokens are non-executable
  # (e.g. subshell-open `(` on its own).
  IGNORE_END_WITH = %w[(].freeze

  # Lines whose stripped content equals exactly one of these are non-executable.
  IGNORE_IS = %w[esac if then else elif fi while do done { } ;; ( )].freeze

  # Function declarations: `name() {` or `name() {`
  FUNC_DECL_REGEX = /\A[a-zA-Z_@][a-zA-Z0-9_@\-:.]*\(\)/.freeze

  # Case selectors: `--help)` on their own line.
  CASE_SELECTOR_REGEX = /\A[^)]+\)\Z/.freeze

  # Classify every line in `path`. Returns Array<nil|0> sized to the file's
  # line count. nil = non-executable, 0 = executable but not yet hit.
  def self.classify(path)
    lines = File.readlines(path)
    arr = Array.new(lines.length, 0)

    # First pass: line-level classification.
    lines.each_with_index do |line, i|
      arr[i] = nil unless relevant?(line)
    end

    # Second pass: multi-line constructs. Each match marks a *body* range as nil.
    lines.each_with_index do |_line, i|
      # multi-line array: name=(...) spanning lines
      mark_multiline!(arr, lines, i, /\A[^\n]*\b=\([^()]*\)/, forward: false)

      # heredoc: <<TAG ... TAG (also <<-TAG, <<'TAG', <<"TAG")
      mark_multiline!(arr, lines, i, /\A[^\n]+<<-?\s*'?(\w+)'?.*$.*\1/m)

      # multiline string concatenated with backslashes
      mark_multiline!(arr, lines, i,
                      /\A[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/)

      # bare backslash line continuations
      mark_multiline!(arr, lines, i,
                      /\A([^\n&|;]*[^\\&|;](\\\\)*\\\n)+[^\n&|;]*[^\n\\&|;](\\\\)*$/)

      # multiline string concatenated with newlines (single- and double-quoted)
      %w[' "].each do |q|
        mark_multiline!(arr, lines, i, /\A[^\n]+[\s=]+#{q}[^#{q}]*#{q}/m, forward: false)
      end
    end

    arr
  end

  # @api private
  def self.relevant?(line)
    line = line.dup
    line.sub!(/\s#.*\Z/, "")
    line.strip!
    return false if line.empty?
    return false if IGNORE_IS.include?(line)
    return false if IGNORE_START_WITH.any? { |p| line.start_with?(p) }
    return false if IGNORE_END_WITH.any? { |s| line.end_with?(s) }
    return false if FUNC_DECL_REGEX.match?(line)
    return false if CASE_SELECTOR_REGEX.match?(line)

    true
  end

  # Walk forward (or backward) from `lineno` looking for a multi-line match
  # starting on that line. If found, mark the body lines as non-executable
  # (unless they were already classified executable by line-level rules — those
  # win, since the regex is heuristic).
  #
  # @api private
  def self.mark_multiline!(arr, lines, lineno, regexp, forward: true)
    seek = lines[lineno..].join
    return unless (m = seek.match(regexp))

    length = m.to_s.count($/)
    first = lineno + 1
    last = lineno + length

    # bashcov's `range` is 0-indexed array positions: forward marks lines after
    # the current (`first..last`), backward marks lines before the reference
    # (`(last-1)..first-1`). The opener (idx = lineno) is intentionally
    # left to line-level classification.
    range = forward ? first.upto(last) : (last - 1).downto(first - 1)

    range.each do |idx|
      next if idx < 0 || idx >= arr.length
      arr[idx] = nil
    end
  end
end
