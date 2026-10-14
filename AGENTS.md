# chain-books: agent guide

## Purpose

Double-entry books for an organisation's on-chain treasury: normalised on-chain activity in,
balanced `ledger` entries, positions, valuations and reconciliation breaks out. Pure OCaml, no
storage and no network.

## Build

Run from this repository, inside the workspace (sibling checkouts of every org repository):

    opam exec --switch 5.2.0+ox -- dune build --root .. @chain-books/all
    opam exec --switch 5.2.0+ox -- dune build --root .. @chain-books/runtest

Parallel agents set `DUNE_BUILD_DIR=_build-chain-books`.

## Never do

- Run `opam install`, `upgrade` or `pin` that would change the compiler, `core`, `base`, `async`
  or `ppx_jane` on the shared `5.2.0+ox` switch.
- Publish, tag or release; commit credentials; poll CI in a loop.
