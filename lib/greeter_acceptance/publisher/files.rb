# frozen_string_literal: true

module GreeterAcceptance
  class Publisher
    # The files on a ledger branch: reading and writing the source records, and
    # regenerating the two generated views from them.
    module Files
      private

      def read_json(dir, path)
        file = File.join(dir, path)
        File.exist?(file) ? JSON.parse(File.read(file)) : nil
      end

      def write_json(dir, path, document)
        file = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "#{JSON.pretty_generate(document)}\n")
      end

      def updated_deployed(deployed, channel, entry)
        Deployed.update(
          deployed, channel: channel, version: entry['version'], sha: entry['sha'],
                    run_id: entry['run_id'], artifact: entry['artifact']
        )
      end

      # ledger.json and LEDGER.md are pure functions of the records on the branch.
      def write_views(dir)
        ledger = Ledger.build(
          environment: @environment, suite_version: @suite_version, channels: @channels,
          requirements: @requirements, results: channel_results(dir), deployed: read_json(dir, 'deployed.json')
        )
        write_json(dir, 'ledger.json', ledger)
        File.write(File.join(dir, 'LEDGER.md'), LedgerRenderer.render(ledger))
      end

      def channel_results(dir)
        Dir.glob(File.join(dir, 'channels', '*.json')).to_h do |file|
          document = JSON.parse(File.read(file))
          [document.dig('run', 'channel'), document]
        end
      end
    end
  end
end
