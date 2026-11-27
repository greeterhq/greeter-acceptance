# Spec Delta

## MODIFIED Requirements

### Requirement: CI publishes the merged trace on main and weekly
CI SHALL merge the partial traces in a `trace` job and, on push to `main` and on the
weekly schedule only, and only when every input job succeeded, upload artifact
`repo-trace` and send `repository_dispatch` `docs-refresh` with
`client_payload[repo]=greeter-acceptance` to `greeterhq/greeter-docs`. The input
jobs are `rspec`, `drivers` and `pact`.

#### Scenario: Trace job merges and uploads on main and schedule
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the schedule is `17 6 * * 1`, `trace` has `needs: [rspec, drivers, pact]`, `if: ${{ !cancelled() }}`, `permissions: {contents: read}`, a checkout with `persist-credentials: false`, downloads each of the four partial artifacts (`repo-trace-spec`, `repo-trace-drivers-cli`, `repo-trace-drivers-http`, `repo-trace-pact`) by name with neither `run-id` nor `merge-multiple`, runs `bin/merge-repo-trace` on all four only when `needs.rspec.result`, `needs.drivers.result` and `needs.pact.result` are all `success`, uploads `repo-trace` with `retention-days: 90` only on the gate (`github.event_name == 'schedule' || (github.event_name == 'push' && github.ref == 'refs/heads/main')`), and ends with a step that fails the job when an input job did not succeed
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Notify-docs dispatches docs-refresh
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `notify-docs` has `needs: trace`, `permissions: {}`, the same gate, a token from `actions/create-github-app-token@v3` (client-id `vars.DISPATCH_APP_CLIENT_ID`, private-key `secrets.DISPATCH_APP_PRIVATE_KEY`, owner `greeterhq`, repository `greeter-docs` only, `permission-contents: write`), and a `docs-refresh` dispatch with `client_payload[repo]=greeter-acceptance` that reads the token from `GH_TOKEN` in `env`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Failed runs and pull requests publish nothing
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the gate excludes `pull_request`, and `notify-docs` depends on `trace`, which fails when `rspec`, `drivers` or `pact` failed, so a red run on `main` uploads no `repo-trace` and sends no `docs-refresh`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Workflow credentials are least-privilege
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the workflow has top-level `permissions: {contents: read}`, and no `run:` step of `trace` or `notify-docs` contains a `${{` expression
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Main and weekly runs do not cancel each other
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `concurrency.group` is `ci-${{ github.event_name }}-${{ github.ref }}` and `cancel-in-progress` is `${{ github.event_name == 'pull_request' }}`
- Maps to: `spec/ci_workflow_spec.rb`
