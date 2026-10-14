# .github: CI

`workflows/ci.yml` installs the switch through the `infra` ox-setup action, pins sibling
repositories in dependency order (`fixed-decimal`, `exchange-core`, `hl-protocol`, `money`,
`ledger`), builds, tests, runs the example and builds the docs with warnings as errors.
When a new sibling dependency is added to `dune-project`, add its pin here in the same
order.
