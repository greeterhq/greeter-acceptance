# frozen_string_literal: true

module GreeterAcceptance
  # Renders a greeterhq.ledger.v2 document as LEDGER.md for people. Like the
  # ledger it is a pure function of its input: no timestamp of its own, and rows
  # in the ledger's (sorted) order.
  #
  # Every value is untrusted text from a channel's result, so markup characters
  # are written as character references and cannot form a link, an HTML tag or a
  # table cell boundary.
  module LedgerRenderer
    EMPTY = '-'

    ESCAPES = {
      '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '[' => '&#91;', ']' => '&#93;',
      '|' => '&#124;', '`' => '&#96;', '*' => '&#42;', '\\' => '&#92;'
    }.freeze

    module_function

    def render(ledger)
      channels = ledger.fetch('channels')
      [
        heading(ledger), channels_table(channels), requirements_table(ledger.fetch('requirements'), channels.keys)
      ].join("\n\n") << "\n"
    end

    def heading(ledger)
      "# Ledger: #{text(ledger['environment'])}\n\nSuite #{text(ledger.dig('suite', 'version'))}"
    end

    def channels_table(channels)
      header = ['channel', 'state', 'channel version', 'core version', 'suite version', 'verification', 'recorded']
      rows = channels.map { |name, column| channel_row(name, column) }
      table(header, rows)
    end

    def channel_row(name, column)
      [
        text(name), state_text(column), text(column['channel_version']), text(column['core_version']),
        text(column['suite_version']), text(column['verification']), recorded_text(column)
      ]
    end

    def state_text(column)
      reasons = Array(column['reasons'])
      reasons.empty? ? text(column['state']) : "#{text(column['state'])} (#{reasons.map { |r| text(r) }.join(', ')})"
    end

    def recorded_text(column)
      return EMPTY if column['recorded_at'].nil?

      run = column['run_id'].nil? ? '' : ", run ##{text(column['run_id'])}"
      "#{text(column['recorded_at'].to_s[0, 10])}#{run}"
    end

    def requirements_table(requirements, channels)
      rows = requirements.map { |name, cells| [text(name)] + channels.map { |channel| text(cells[channel]) } }
      table(['requirement'] + channels.map { |channel| text(channel) }, rows)
    end

    def table(header, rows)
      lines = [header, header.map { '---' }, *rows].map { |cells| "| #{cells.join(' | ')} |" }
      lines.join("\n")
    end

    def text(value)
      return EMPTY if value.nil? || value.to_s.empty?

      value.to_s.gsub(/[&<>\[\]|`*\\]/) { |char| ESCAPES.fetch(char) }
    end
  end
end
