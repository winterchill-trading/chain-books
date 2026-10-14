# chain-books: agent guide

## Purpose

Double-entry books for an organisation's on-chain treasury: normalised on-chain activity
in, balanced `ledger` entries, positions with cost basis, valuations and reconciliation
breaks out. Pure OCaml (no storage, network or clock), with a Hyperliquid adapter as a
sub-library.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | Library `chain-books` (module `Chain_books`): ids, locations, activities, chart, booking, openings, positions, reconciliation, valuation, chain writes, `Books` |
| `hyperliquid/` | Library `chain-books.hyperliquid` (module `Chain_books_hyperliquid`): info-answer decoders, `Config`, `Adapter` |
| `test/` | Expect tests and Quickcheck properties for `lib/`, stable digests |
| `test/hyperliquid/` | Adapter tests over JSON fixtures in `fixtures/` |
| `examples/` | `quickstart.ml` and its expected output, run by `dune test` and CI |
| `docs/` | `hyperliquid.md`: what the venue's info answers contain |
| `.github/` | CI workflow |

## Build, test, docs

Run from this repository, inside the workspace (every org repository is a sibling
checkout):

    opam exec --switch 5.2.0+ox -- dune build --root .. @chain-books/all
    opam exec --switch 5.2.0+ox -- dune build --root .. @chain-books/runtest
    opam exec --switch 5.2.0+ox -- dune build --root .. @chain-books/doc

Several agents building at once set `DUNE_BUILD_DIR=_build-chain-books` (resolved from the
workspace root because of `--root ..`; `../_build-chain-books` fails with "path outside the
workspace"). Promote expect output with `dune promote` run from the workspace root.

Standalone: add the organisation's opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`) or
pin the dependencies listed in `README.md`, then `dune build` and `dune test` here.

## Conventions

- Format this repository only: `dune build --root .. @chain-books/fmt --auto-promote`, after
  tests pass and output is promoted. Never `dune fmt` across the workspace.
- `open! Core`, an `.mli` for every module, an odoc comment on every public value; the docs
  build has no warnings (CI fails on any).
- Persisted types have a `Stable.V1` with a pinned `[%bin_digest]` in `test/test_stable.ml`;
  decoding validates like the smart constructor. Never edit a pinned V1; add V2.
- Amounts are `Money.Amount.t`; sizes and prices are `Exact.t` (`Q.t`). No floats. Venue
  decimals are rounded once, half-even, in the adapter (`Normalizer.round`).
- Event ids are deterministic from venue ids and independent of which bound address read
  the record; idempotency keys are `chain:<binding>:<event id>` and must stay within the
  ledger's 128 characters (the id length caps exist for that).
- Expect tests for behaviour, Quickcheck (`Quickcheck.test` in `let%test_unit`) for
  invariants: trial balance, idempotent re-ingest, realised profit of flat positions,
  retry delays and nonces.
- Leave a short comment at any non-obvious choice. User-visible changes get a line under
  `## Unreleased` in `CHANGES.md`.

## Dependencies and dependents

- Sibling repositories: `fixed-decimal`, `money`, `ledger`; the adapter also uses
  `hl-protocol` (and through it `exchange-core`).
- External: `core`, `ppx_jane`, `zarith`, `yojson`.
- CI pin order: `fixed-decimal`, `exchange-core`, `hl-protocol`, `money`, `ledger`.
- No org repository depends on this one yet.

## CI

`.github/workflows/ci.yml` uses the `infra` ox-setup action with the pins above, then runs
`dune build`, `dune test`, the quickstart example and the odoc build with warnings as
errors; the `obj-magic` job calls the reusable workflow in `winterchill-trading/infra`.
Check a run with `gh run list --limit 1` and at most one `gh run watch <id> --exit-status`;
never poll in a loop.

## Pitfalls

- `Ledger.Balances.apply` refuses a `recorded_at` earlier than the last record's; `Books`
  moves the time forward, direct callers of `Booking` must do the same.
- Ledger entries are single-currency: a spot fill is two activities (base and quote legs),
  each its own entry, through the `spot_clearing` account.
- A sibling's `Stable` record field must use the sibling's stable type
  (`Money.Amount.Stable.V1.t`, `Time_ns.Stable.Alternate_sexp.V1.t`); use
  `Time_ns.Alternate_sexp.t` in unversioned types so expect output prints UTC.
- `[@sexp.opaque]` must sit inside parentheses with the type; here `Exact.t` gives `Q.t`
  a readable sexp instead.
- Venue order in maps follows constructor order (`Perp` before `Spot`); expect output lists
  rows in that order.
- Spot USDC is reported with 8 digits on Hyperliquid and booked with 6: reconcile with a
  one-minor-unit tolerance.
- The workspace build prints other repositories' errors; filter for `File "chain-books/`.

## Where to read more

- `README.md` (model, rules, adapter coverage, known gaps) and `docs/hyperliquid.md`
- `../specs/repos/chain-books.md` when present
- `../oxcaml-claude-skills/AGENTS.md` (workspace guide) and
  `../oxcaml-claude-skills/GOTCHAS.md`
- Skills in `../oxcaml-claude-skills/skills/`: `banking-standards`,
  `janestreet-ocaml-style`, `oxcaml-modes`

## Never do

- Run `opam install`, `upgrade` or `pin` that would change the compiler, `core`, `base`,
  `async` or `ppx_jane` on the shared `5.2.0+ox` switch.
- Publish, tag or release.
- Commit credentials or print secrets (`.env` is gitignored; values only from the
  environment). The library reads none.
- Replace a synthetic fixture with real account data.
- Poll CI in a loop.
