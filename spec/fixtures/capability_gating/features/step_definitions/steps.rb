# frozen_string_literal: true

# Each step leaves a marker file named after the scenario, so a spec can tell
# whether the steps of a gated scenario ran.
Given('the {word} scenario runs') do |name|
  File.write(File.join(ENV.fetch('GATING_MARKER_DIR'), name), 'ran')
  driver.greet('Fixture') if name == 'plain'
end
