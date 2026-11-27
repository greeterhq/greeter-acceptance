# Tasks

## 1. Red tests

The user opens the test guard before this group, commits the red tests, and
closes the guard before apply. Never run `tests-open` or `tests-close`.

- [ ] 1.0 Stage the `Gemfile` and `Gemfile.lock` changes already in the working tree with the red tests, so the pact spec loads. Those changes add `gem 'pact', '~> 2.1'` and lock 2.1.2 with `pact-ffi` for `arm64-darwin` and `x86_64-linux`. A `LoadError` is not a valid red. Verify: `bundle exec ruby -e "require 'pact/rspec'"` exits 0, and `bundle exec bundle-audit check` passes.
- [ ] 1.1 Write `spec/pact/providers/greeter_http_spec.rb`:
  - `require 'pact/rspec'`, then `has_http_pact_between 'greeter-acceptance', 'greeter-http'` with `order: :defined`.
  - A `before(:context)` that deletes `pacts/greeter-acceptance-greeter-http.json`.
  - The new-greeting, replay and invalid-name interactions, using the matchers from design.md (Interaction shapes). Each example builds the driver with `CompositionRoot.build_driver(env: ...)` and checks the neutral outcome.
  - A final group that reads the pact file and checks: exactly three interactions, the synthetic header and a key on every request, an integer rule on `$.count`, and no exact `count`, `greeted_at` or version value.
  - Tag every example with its `requirement:` and `scenario:` from `specs/pact-consumer/spec.md`.

  Verify: `bundle exec rspec -t pact spec/pact/providers` passes against the mock server. A first-time green is expected, because the driver already fits the contract. The mutation proofs in 1.7 and 1.8 show the spec can fail. If an interaction fails, report the mismatch and do not weaken it.
- [ ] 1.2 Add `config.filter_run_excluding :pact` to `spec/spec_helper.rb`, and add an example to `spec/ci_workflow_spec.rb` for "The default run skips the pact specs". Verify: plain `bundle exec rspec --exclude-pattern 'spec/drivers/**/*_spec.rb'` lists no example from `spec/pact/`, and `-t pact spec/pact/providers` runs them.
- [ ] 1.3 Add examples to `spec/ci_workflow_spec.rb`, tagged from `specs/pact-consumer/spec.md`, for:
  - the `pact` job;
  - the `pact-publish` gate, main publish, tag publish and deployment records;
  - PRs publishing nothing;
  - the token scope.

  Verify: they fail with expectation or `KeyError` failures because `pact` and `pact-publish` do not exist yet.
- [ ] 1.4 Change the existing `trace` examples in `spec/ci_workflow_spec.rb` to the MODIFIED scenarios: `needs: [rspec, drivers, pact]`, four downloads, merge and fail guards that include `needs.pact.result`. Verify: they fail on the current `ci.yml` for that reason only.
- [ ] 1.5 Add a behaviour example for "A tag off main fails before publishing". It runs the ancestry step's `run:` text in a temporary repo built with `GitHelpers`, which has an `origin/main` and a commit off main. Verify: it fails because the step does not exist yet.
- [ ] 1.6 Add one security example per scenario to `spec/ci_workflow_spec.rb` (design.md, Security considerations).
  - S1: tagged `requirement: 'the-broker-token-reaches-only-the-publish-steps'`, `scenario: 'the-publish-job-runs-in-the-pact-broker-environment'`. `pact-publish` has `environment: pact-broker`, no other job names that environment, and the workflow has no `pull_request_target` trigger.
  - S3: same requirement, `scenario: 'the-token-reaches-the-container-by-name-only'`. Every `docker run` in `pact-publish`:
    - has `--rm`;
    - passes the broker variables as `-e NAME` with no `=`;
    - mounts `"$PWD/pacts:/pacts:ro"`;
    - and no `pact-broker` command has `--verbose` or `-v`.
  - S2: `requirement: 'the-publish-job-checks-its-inputs-before-using-the-token'`, `scenario: 'only-the-greeter-acceptance-to-greeter-http-pact-is-published'`.
    - It runs the check step's `run:` against temporary directories holding an extra file, a wrong consumer and a wrong provider. Each must exit non-zero, and a valid directory must exit 0.
    - It also asserts the step comes after the download and before every step that has the token.
  - S4: same requirement, `scenario: 'a-non-https-broker-url-stops-the-job'`. It runs the check step with an `http://` URL, which must exit non-zero naming `PACT_BROKER_BASE_URL`, and with an `https://` URL, which must exit 0.
  - S5: same requirement, `scenario: 'a-tag-that-does-not-match-the-suite-version-stops-the-job'`.
    - It runs the tag check step with a non-matching `GITHUB_REF_NAME`, which must exit non-zero naming both values, and with `v` + `GreeterAcceptance::VERSION`, which must exit 0.
    - It also asserts the step is tag-only, comes before the publish step, and has no token.

  Verify: each example fails with expectation or `KeyError` failures because the steps do not exist yet.
- [x] 1.7 Mutation proof (a): copy `lib/greeter_acceptance/drivers/http_driver.rb` to a temporary file, then stop the driver sending `X-Greeter-Synthetic`. Run `bundle exec rspec -t pact spec/pact/providers` and show the interactions fail with a header mismatch. Restore the file from the copy. Verify: `cmp` of the restored file against the copy exits 0, and the pact run is green again.
- [x] 1.8 Mutation proof (b): copy `spec/pact/providers/greeter_http_spec.rb` to a temporary file, then change the `count` matcher to a string matcher. Run the pact specs and show the integer-matcher example ("Count is expected as an integer") fails. Restore the file from the copy. Verify: `cmp` of the restored file against the copy exits 0, and the pact run is green again.
- [ ] 1.9 Hand the red tests to the user to commit; do not commit them yourself. They are 1.0 to 1.6, with the `ci.yml` examples from 1.3 to 1.6 as the real reds. Verify: `bundle exec rspec spec/trace_check_spec.rb` and the repo's own trace check report no unknown `requirement:` or `scenario:` slug, because the change deltas are known headings.

## 2. Repository setup

- [ ] 2.1 Add `/pacts/` to `.gitignore`. Verify: `git status` shows no `pacts/` after a pact run.

## 3. CI: pact job and trace merge

- [ ] 3.1 Add the `pact` job to `.github/workflows/ci.yml` as described in design.md (CI jobs). It uploads `repo-trace-pact` and `pacts`. Update the header comment diagram. Verify: the `pact` job examples from 1.3 pass.
- [ ] 3.2 Update `trace`: add `pact` to `needs`, download `repo-trace-pact`, pass it to `bin/merge-repo-trace`, and add `needs.pact.result == 'success'` to every guard and to the final failing step. Verify: the examples from 1.4 pass. Also merge a local pact partial with the spec partial using `bin/merge-repo-trace` and confirm it exits 0.

## 4. CI: publish and record deployments

- [ ] 4.1 Pick the latest `pactfoundation/pact-cli` release tag and read its digest with `docker buildx imagetools inspect pactfoundation/pact-cli:<tag>`. Record the tag and digest in design.md ("Pinned pact-cli image"), and set the workflow env `PACT_CLI_IMAGE: pactfoundation/pact-cli:<tag>@sha256:<digest>`. Then add the `pact-publish` job:
  - gate, `needs: pact`, `permissions: {contents: read}`;
  - checkout with `fetch-depth: 0` and `persist-credentials: false`;
  - download of `pacts`;
  - main publish with `--branch main`.

  Verify: the gate, main publish and PR examples from 1.3 pass.
- [ ] 4.2 Add the tag-only steps to `pact-publish`: the `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` check, a publish with neither `--branch` nor `--tag`, then `record-deployment` for `stage` and for `prod`. Verify: the tag and deployment examples from 1.3 pass, as does the behaviour example from 1.5.
- [ ] 4.3 Set `PACT_BROKER_BASE_URL` (from `vars`) and `PACT_BROKER_TOKEN` (from `secrets`) only in the `env:` of each `pact-broker` step, with no `${{` in any `run:`. Verify: the token-scope example passes, `spec/workflow_token_order_spec.rb` still passes, and `actionlint` (if installed) reports nothing for `ci.yml`.

- [ ] 4.4 Harden the token path (design.md S1, S3):
  - add `environment: pact-broker` to `pact-publish`;
  - write each `docker run` as `docker run --rm -e PACT_BROKER_BASE_URL -e PACT_BROKER_TOKEN -v "$PWD/pacts:/pacts:ro" "$PACT_CLI_IMAGE" pact-broker ...`, with no `--verbose`.

  Verify: the S1 and S3 examples from 1.6 pass.
- [ ] 4.5 Add the checks that run before the token steps (design.md S2, S4, S5). Both use standard-library Ruby and no bundler, and both read only from `env`.
  - The pact-file and HTTPS check runs on every `pact-publish` run, after the download and before any `pact-broker` step.
  - The `v` + `VERSION` tag check runs on tags only, before the publish, reading `lib/greeter_acceptance/version.rb`.

  Verify: the S2, S4 and S5 examples from 1.6 pass, including the behaviour runs.

## 5. Version

- [ ] 5.1 Bump `GreeterAcceptance::VERSION` to `0.4.0` in `lib/greeter_acceptance/version.rb`. Verify: any spec that compares the version to a tag (for example `spec/record_workflow_spec.rb`) still passes.

## 6. Verify and docs

- [ ] 6.1 Run the whole suite:
  - `bundle exec rspec --exclude-pattern 'spec/drivers/**/*_spec.rb'`
  - `bundle exec rspec -t pact spec/pact/providers`
  - `GREETER_CHANNEL=cli bundle exec cucumber`
  - `GREETER_CHANNEL=http GREETER_BASE_URL=<stage> bundle exec cucumber`

  Verify: all are green, and `bundle exec rubocop` is clean.
- [ ] 6.2 Check `tmp/traceability.json` from both Cucumber runs against `docs/traceability-schema.md` (`greeterhq.traceability.v2`). Check `tmp/repo-trace-pact.json` against `greeterhq.repo-trace.v1` by merging it with `bin/merge-repo-trace`. Verify: both are valid.
- [ ] 6.3 Document the pact consumer in `README.md`:
  - how to run `-t pact`;
  - where the pact is written;
  - when CI publishes and records deployments;
  - the two broker settings;
  - why the 400 response is not in the contract.

  Verify: the documented command runs as written.
- [ ] 6.4 Run `openspec validate add-pact-consumer --strict` and `openspec validate --all --strict --no-interactive`. Verify: both pass.

## Workflow follow-up

- Archive the change after review.
- Tag `v0.4.0` on main after the archive. It does not wait for greeter-http's provider verification (see design.md, Risks).
