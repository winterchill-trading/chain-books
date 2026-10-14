# test: chain-books tests

- `helpers.ml`: a chart, addresses, locations and builders shared by the tests.
- One file per module (`test_booking.ml`, `test_positions.ml`, `test_reconciliation.ml`,
  `test_valuation.ml`, `test_chain_write.ml`, `test_books.ml`), each with expect tests and
  Quickcheck properties; `test_stable.ml` pins the bin_prot digests.
- `hyperliquid/`: adapter tests over `hyperliquid/fixtures/*.json` (synthetic addresses and
  hashes, venue shapes).

Promote expect output with `dune promote` from the workspace root after reading the diff. A
changed digest in `test_stable.ml` is a compatibility break, not output to promote.
