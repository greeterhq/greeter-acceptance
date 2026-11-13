# frozen_string_literal: true

module GreeterAcceptance
  # The suite version. It must equal the git tag a release is cut from (without
  # the leading v); the record workflow checks that before it runs anything.
  # Consumers pin the suite by that tag (ACCEPTANCE_REF).
  VERSION = '0.2.2'
end
