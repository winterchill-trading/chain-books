# hyperliquid: Hyperliquid adapter

Library `chain-books.hyperliquid` (module `Chain_books_hyperliquid`).

- `Wire`: JSON field readers; decoders raise inside and return `Or_error` at the edge.
- `Ledger_update`, `Funding`, `Staking_reward`, `Spot_state`, `Delegator_summary`: info
  answers `hl-protocol` does not model. `Builder_fill` is a row the caller supplies.
- `Config` (account, binding addresses, token and spot-pair tables, rewards policy) and
  `Adapter` (`Chain_books.Normalizer.S`).

Rules:

- Event ids must not depend on which bound address read a record, or internal transfers
  book twice. See the id table in `adapter.mli`.
- Shapes come from real mainnet answers; when adding a delta type, check one with a
  read-only `POST /info` request and record what you saw in `../docs/hyperliquid.md`.
- Unknown tokens and spot pairs are dropped, never guessed.
