# Ledger publication

How a channel's result reaches a ledger branch, and what the publisher will and
will not do. The documents themselves are described in
[`traceability-schema.md`](traceability-schema.md).

## The ledger branches

Each environment has its own branch, named in `config/environments.yml`
(`ledger-prod`, `ledger-stage`). A result for one environment is never written to
another's branch. Every branch has the same layout:

```
channels/cli.json     the latest result for the cli channel      source record
channels/http.json    the latest result for the http channel     source record
deployed.json         what is deployed, per channel              source record
ledger.json           the requirement-by-channel matrix          generated
LEDGER.md             the same matrix, for people                generated
```

The source records are what the publisher writes. `ledger.json` and `LEDGER.md`
are generated from them and from nothing else, with no timestamp of their own, so
regenerating from the same records always gives the same files.

## What a publication does

A publication writes only its own channel's result file and its own channel's
entry in `deployed.json`, then regenerates the two generated files from every
record on the branch. A branch with nothing on it yet is created for the first
publication.

`deployed.json` is updated whatever the result says: a run whose scenarios fail or
error still records that the new version is deployed.

If nothing would change, no commit is made and the outcome is `unchanged`;
otherwise it is `committed`.

### When two publications meet

Two channels can publish to the same branch at the same time. Both would rewrite
`ledger.json` and `LEDGER.md`, so replaying one commit over the other would
conflict on exactly those files. The publisher therefore never rebases and never
forces. When its push is rejected it starts again from the branch as the remote
now has it:

```
repeat, up to --max-attempts (default 5):
  start from an empty directory and fetch the branch
  apply this publication's change
  regenerate ledger.json and LEDGER.md from all the records
  nothing differs?  stop, outcome unchanged
  commit, then push (never forced)
    rejected -> repeat
```

Every interleaving ends with a branch that holds both results. If the branch keeps
moving past the limit, the publication fails with a message saying so.

## What it refuses

The publisher stops with a message, and changes nothing, when:

- **the channel version is older** than the one already recorded for that channel
  in `deployed.json`. Versions are compared as semantic versions, so `v1.10.0` is
  newer than `v1.2.3`. The same or a newer version replaces the record.
- **the suite version is older** than the one `ledger.json` already records.
- **the version is not a semantic version** such as `v1.2.3`.
- **the result does not validate** (see below).

A **forced** publication skips the two ordering checks, which is how a rollback is
recorded. It must name the actor, and it is marked: the channel's result gets
`run.forced` set to the actor, and the commit message ends with `[forced]`.

## Untrusted data

The result file comes from the run that tested the channel, so it is treated as
data from outside:

- Only an allowlist of fields is kept, at every level. Anything else is dropped,
  and the file that is committed is rebuilt, not copied.
- Every value must match a strict pattern: versions look like `v1.2.3`, commits
  are 7 to 40 hex characters, requirement and scenario names are lowercase words
  and hyphens, statuses and verification states come from fixed lists.
- The result must name the channel and the environment it is being recorded for.
- A result over `--max-result-bytes` (1 MiB by default) is refused.
- In `LEDGER.md`, characters that could form a link, a tag or a table cell are
  written as character references.
- Nothing in the result is ever evaluated.

The publisher itself uses only the Ruby standard library and the `git` command. It
installs no gems, and it runs git with hooks disabled, so it executes no code that
the channel under test, or the environment it runs in, happens to provide.

## `bin/publish`

```bash
bin/publish --remote URL --branch ledger-prod --environment prod \
  --suite-version v0.2.0 --channel http --result result.json \
  --version v1.2.3 --sha def4567 [--run-id ID] [--artifact tag] \
  [--features DIR] [--max-attempts N] [--max-result-bytes N] [--force --actor NAME]
```

It prints `committed` or `unchanged`. A refusal, an invalid result file or a branch
that will not accept the push stops with a message on stderr and exit status 1.
`--features` (default `features`) is where the `@requirement-*` tags are read.
