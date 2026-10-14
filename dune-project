(lang dune 3.17)

(name chain-books)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/chain-books))

(homepage "https://github.com/winterchill-trading/chain-books")

(bug_reports "https://github.com/winterchill-trading/chain-books/issues")

(documentation "https://github.com/winterchill-trading/chain-books#readme")

(package
 (name chain-books)
 (synopsis
  "Double-entry books for on-chain treasuries: normalised activity, ledger postings, cost basis, mark-to-market and reconciliation")
 (description
  "chain-books turns normalised on-chain activity (deposits, withdrawals, transfers, spot and perpetual trades, funding, fees, staking rewards, builder-fee income) into balanced double-entry ledger entries over a chart of accounts for an organisation's custody locations. It derives opening balances from the first observed balance, tracks positions and cost basis per asset and instrument, values holdings at market through a price source hook, reconciles booked balances against reported on-chain balances and lists the breaks, and keeps the two-step write record (prepare with a nonce, store the exact body, resend it on an unknown outcome). The sub-library chain-books.hyperliquid normalises Hyperliquid fills, funding, ledger updates, staking rewards and account states. Pure: no storage, no network. Requires the OxCaml compiler (through its money and fixed-decimal dependencies).")
 (tags
  (accounting ledger treasury crypto hyperliquid reconciliation cost-basis oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (zarith
   (>= 1.12))
  yojson
  ppx_yojson_conv
  fixed-decimal
  money
  ledger
  exchange-core
  hl-protocol
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
