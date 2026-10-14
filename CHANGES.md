# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## Unreleased

### Added

- Identifiers: `Binding_id`, `Address`, `Event_id` over a shared `Short_id`.
- Locations and assets: `Venue`, `Location`, `Assets` (HYPE, token registration),
  counterparty `Category` with account kinds and custom categories.
- Normalised values: `Activity` (16 kinds, location or category counter), `Fill`,
  `Instrument`, `Exact`, `Observed`, `Normalized`, and the `Normalizer.S` module type.
- Books: `Chart` of accounts per binding, `Booking` of activities as single-currency
  ledger entries with a classification hook, `Opening` balances from the first
  observation, `Positions` with FIFO and average cost, `Reconciliation` of balances and
  perpetual positions, `Price_source` and `Valuation`, and `Books` tying them together.
- `Chain_write`: prepare, submit, resend and confirm record for writes to a chain.
- `chain-books.hyperliquid`: decoders for ledger updates, funding history, staking
  rewards and balances, spot balances; `Config`; `Adapter` implementing
  `Normalizer.S` over fills, funding, ledger updates, staking rewards, builder income
  and account state.
- Stable bin_prot types with pinned digests; `examples/quickstart.ml`.
