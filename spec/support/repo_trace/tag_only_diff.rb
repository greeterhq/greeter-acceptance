# frozen_string_literal: true

module RepoTrace
  # Proves that an edit to an existing spec file only added or changed
  # requirement/scenario tags. Both versions are normalised the same way and
  # compared; any remaining difference is a problem naming the file.
  #
  # Normalising: unwrap tagged context wrappers (a context line carrying the
  # requirement and scenario tags) whose body is only it_behaves_like lines, drop
  # each requirement/scenario tag pair, then drop all whitespace. The comment is
  # worded without literal tags so the trace check's text scan of spec/**/*.rb
  # does not read it as a tag.
  #
  # Known limit: whitespace inside string literals is removed too.
  module TagOnlyDiff
    TAG = /,\s*(?:requirement|scenario):\s*'[^']*'/
    WRAPPER_OPEN = /
      ^(?<indent>[ \t]*)context\s+(?:'[^']*'|"[^"]*"),\s*
      requirement:\s*'[^']*',\s*scenario:\s*'[^']*'\s+do[ \t]*\n
    /x

    module_function

    def call(path:, before:, after:)
      return [] if normalise(before) == normalise(after)

      ["#{path}: changes more than requirement/scenario tags"]
    end

    def normalise(text)
      unwrap(text).gsub(TAG, '').gsub(/\s+/, '')
    end

    def unwrap(text)
      offset = 0
      while (open = WRAPPER_OPEN.match(text, offset))
        replaced = unwrap_at(text, open)
        text = replaced || text
        offset = replaced ? open.begin(0) : open.end(0)
      end
      text
    end

    # The text with one wrapper removed, or nil if it is not a pure wrapper.
    def unwrap_at(text, open)
      rest = text[open.end(0)..]
      close = rest.match(/^#{Regexp.escape(open[:indent])}end[ \t]*(?:\n|\z)/)
      return nil unless close

      body = rest[0...close.begin(0)]
      return nil unless shared_examples_only?(body)

      text[0...open.begin(0)] + body + rest[close.end(0)..]
    end

    def shared_examples_only?(body)
      body.lines.map(&:strip).all? { |line| line.empty? || line.start_with?('it_behaves_like') }
    end
  end
end
